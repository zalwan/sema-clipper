import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/services.dart';

const maximumCaptionLength = 80;

enum ClipProcessError {
  invalidRange,
  invalidCaption,
  noSpace,
  cancelled,
  processingFailed,
}

final class ClipProcessRequest {
  const ClipProcessRequest({
    required this.sourcePath,
    required this.sourceDuration,
    required this.start,
    required this.end,
    required this.caption,
    required this.outputPath,
  });

  final String sourcePath;
  final Duration sourceDuration;
  final Duration start;
  final Duration end;
  final String caption;
  final String outputPath;

  ClipProcessRequest copyWith({
    String? sourcePath,
    Duration? sourceDuration,
    Duration? start,
    Duration? end,
    String? caption,
    String? outputPath,
  }) => ClipProcessRequest(
    sourcePath: sourcePath ?? this.sourcePath,
    sourceDuration: sourceDuration ?? this.sourceDuration,
    start: start ?? this.start,
    end: end ?? this.end,
    caption: caption ?? this.caption,
    outputPath: outputPath ?? this.outputPath,
  );
}

sealed class ClipProcessResult {
  const ClipProcessResult();
}

final class ClipProcessSuccess extends ClipProcessResult {
  const ClipProcessSuccess(this.path);

  final String path;

  @override
  bool operator ==(Object other) =>
      other is ClipProcessSuccess && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

final class ClipProcessFailure extends ClipProcessResult {
  const ClipProcessFailure(this.error);

  final ClipProcessError error;

  @override
  bool operator ==(Object other) =>
      other is ClipProcessFailure && other.error == error;

  @override
  int get hashCode => error.hashCode;
}

enum ClipCommandStatus { success, cancelled, failed }

final class ClipCommandResult {
  const ClipCommandResult.success()
    : status = ClipCommandStatus.success,
      details = '';

  const ClipCommandResult.cancelled()
    : status = ClipCommandStatus.cancelled,
      details = '';

  const ClipCommandResult.failed({this.details = ''})
    : status = ClipCommandStatus.failed;

  final ClipCommandStatus status;
  final String details;
}

abstract interface class ClipCommandRunner {
  Future<ClipCommandResult> execute(List<String> arguments);

  Future<void> cancel();
}

final class FfmpegKitCommandRunner implements ClipCommandRunner {
  FFmpegSession? _activeSession;

  @override
  Future<ClipCommandResult> execute(List<String> arguments) async {
    final completed = Completer<ClipCommandResult>();
    final session = await FFmpegKit.executeWithArgumentsAsync(arguments, (
      finishedSession,
    ) async {
      final returnCode = await finishedSession.getReturnCode();
      if (ReturnCode.isSuccess(returnCode)) {
        completed.complete(const ClipCommandResult.success());
      } else if (ReturnCode.isCancel(returnCode)) {
        completed.complete(const ClipCommandResult.cancelled());
      } else {
        completed.complete(
          ClipCommandResult.failed(
            details: await finishedSession.getAllLogsAsString() ?? '',
          ),
        );
      }
    });
    _activeSession = session;
    try {
      return await completed.future;
    } finally {
      if (_activeSession == session) _activeSession = null;
    }
  }

  @override
  Future<void> cancel() async => _activeSession?.cancel();
}

abstract interface class ClipProcessing {
  Future<ClipProcessResult> process(ClipProcessRequest request);

  Future<void> cancel();
}

ClipProcessError? validateClipRequest(ClipProcessRequest request) {
  final clipDuration = request.end - request.start;
  if (request.sourcePath.trim().isEmpty ||
      request.outputPath.trim().isEmpty ||
      request.start < Duration.zero ||
      request.start >= request.end ||
      request.end > request.sourceDuration ||
      clipDuration > const Duration(seconds: 60)) {
    return ClipProcessError.invalidRange;
  }

  final caption = request.caption.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  if (caption.isEmpty || caption.runes.length > maximumCaptionLength) {
    return ClipProcessError.invalidCaption;
  }
  return null;
}

String sanitizeCaption(String caption) {
  final singleLine = caption
      .replaceAll(RegExp(r'[\r\n]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return singleLine
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll(':', r'\:')
      .replaceAll("'", r"\'");
}

String _escapeDrawtextPath(String path) =>
    path.replaceAll(r'\', r'\\').replaceAll(':', r'\:').replaceAll("'", r"\'");

String buildVerticalCaptionFilter({
  required String fontPath,
  required String caption,
}) =>
    'scale=-2:1920,crop=1080:1920:(iw-1080)/2:0,'
    "drawtext=fontfile='${_escapeDrawtextPath(fontPath)}':"
    "text='${sanitizeCaption(caption)}':"
    'expansion=none:fontcolor=white:fontsize=64:'
    'borderw=4:bordercolor=black@0.85:'
    'x=(w-text_w)/2:y=h*2/3';

List<String> buildClipCommand(
  ClipProcessRequest request, {
  required String fontPath,
}) {
  final duration = request.end - request.start;
  String seconds(Duration value) =>
      (value.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(
        3,
      );

  return [
    '-y',
    '-ss',
    seconds(request.start),
    '-i',
    request.sourcePath,
    '-t',
    seconds(duration),
    '-map',
    '0:v:0',
    '-map',
    '0:a?',
    '-vf',
    buildVerticalCaptionFilter(fontPath: fontPath, caption: request.caption),
    '-c:v',
    'libx264',
    '-preset',
    'ultrafast',
    '-crf',
    '24',
    '-pix_fmt',
    'yuv420p',
    '-c:a',
    'aac',
    '-b:a',
    '128k',
    '-movflags',
    '+faststart',
    request.outputPath,
  ];
}

typedef FontFileFactory = Future<File> Function();

final class ClipProcessor implements ClipProcessing {
  ClipProcessor({ClipCommandRunner? runner, FontFileFactory? createFontFile})
    : _runner = runner ?? FfmpegKitCommandRunner(),
      _createFontFile = createFontFile ?? _writeBundledFont;

  final ClipCommandRunner _runner;
  final FontFileFactory _createFontFile;

  @override
  Future<ClipProcessResult> process(ClipProcessRequest request) async {
    final validationError = validateClipRequest(request);
    if (validationError != null) return ClipProcessFailure(validationError);

    final output = File(request.outputPath);
    File? font;
    try {
      await output.parent.create(recursive: true);
      if (await output.exists()) await output.delete();
      font = await _createFontFile();
      final commandResult = await _runner.execute(
        buildClipCommand(request, fontPath: font.path),
      );

      if (commandResult.status == ClipCommandStatus.cancelled) {
        await _deleteIfPresent(output);
        return const ClipProcessFailure(ClipProcessError.cancelled);
      }
      if (commandResult.status == ClipCommandStatus.failed) {
        await _deleteIfPresent(output);
        final noSpace = commandResult.details.toLowerCase().contains(
          'no space left on device',
        );
        return ClipProcessFailure(
          noSpace
              ? ClipProcessError.noSpace
              : ClipProcessError.processingFailed,
        );
      }
      if (!await output.exists() || await output.length() == 0) {
        await _deleteIfPresent(output);
        return const ClipProcessFailure(ClipProcessError.processingFailed);
      }
      return ClipProcessSuccess(output.path);
    } catch (_) {
      await _deleteIfPresent(output);
      return const ClipProcessFailure(ClipProcessError.processingFailed);
    } finally {
      if (font != null) await _deleteIfPresent(font);
    }
  }

  @override
  Future<void> cancel() => _runner.cancel();

  static Future<File> _writeBundledFont() async {
    final data = await rootBundle.load('assets/fonts/DejaVuSans.ttf');
    final directory = await Directory.systemTemp.createTemp('sema-font-');
    final font = File('${directory.path}/DejaVuSans.ttf');
    return font.writeAsBytes(data.buffer.asUint8List(), flush: true);
  }
}

Future<void> _deleteIfPresent(File file) async {
  try {
    if (await file.exists()) await file.delete();
    final parent = file.parent;
    if (parent.path.contains('sema-font-') && await parent.exists()) {
      await parent.delete(recursive: true);
    }
  } catch (_) {
    // Cleanup is best-effort; processing result remains the primary outcome.
  }
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sema_clipper/features/clipper/clip_processor.dart';

void main() {
  group('clip request validation', () {
    final valid = ClipProcessRequest(
      sourcePath: '/video/source.mp4',
      sourceDuration: const Duration(seconds: 90),
      start: const Duration(seconds: 12),
      end: const Duration(seconds: 52),
      caption: 'A strong moment',
      outputPath: '/video/output.mp4',
    );

    test('accepts a range within the source and 60 second limit', () {
      expect(validateClipRequest(valid), isNull);
    });

    test('rejects invalid boundaries and clips longer than 60 seconds', () {
      expect(
        validateClipRequest(valid.copyWith(start: const Duration(seconds: -1))),
        ClipProcessError.invalidRange,
      );
      expect(
        validateClipRequest(valid.copyWith(end: const Duration(seconds: 12))),
        ClipProcessError.invalidRange,
      );
      expect(
        validateClipRequest(valid.copyWith(end: const Duration(seconds: 91))),
        ClipProcessError.invalidRange,
      );
      expect(
        validateClipRequest(
          valid.copyWith(
            start: Duration.zero,
            end: const Duration(seconds: 61),
          ),
        ),
        ClipProcessError.invalidRange,
      );
    });

    test('requires a one-line caption of at most 80 characters', () {
      expect(
        validateClipRequest(valid.copyWith(caption: '   ')),
        ClipProcessError.invalidCaption,
      );
      expect(
        validateClipRequest(
          valid.copyWith(caption: List.filled(81, 'x').join()),
        ),
        ClipProcessError.invalidCaption,
      );
      expect(
        validateClipRequest(valid.copyWith(caption: 'first\nsecond')),
        isNull,
      );
    });
  });

  test('caption sanitizer strips newlines and escapes drawtext characters', () {
    expect(
      sanitizeCaption("  100%: it's \\ ready\nnow  "),
      r"100\%\: it\'s \\ ready now",
    );
  });

  test('vertical filter center-crops to 9:16 and burns readable text', () {
    final filter = buildVerticalCaptionFilter(
      fontPath: '/tmp/font.ttf',
      caption: 'SEMA: ready',
    );

    expect(filter, startsWith('scale=-2:1920,crop=1080:1920:(iw-1080)/2:0'));
    expect(filter, contains(r"fontfile='/tmp/font.ttf'"));
    expect(filter, contains(r"text='SEMA\: ready'"));
    expect(filter, contains('fontcolor=white'));
    expect(filter, contains('borderw=4'));
    expect(filter, contains('x=(w-text_w)/2:y=h*2/3'));
  });

  group('ClipProcessor', () {
    late Directory directory;
    late FakeClipCommandRunner runner;
    late ClipProcessor processor;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('clip-processor-test-');
      runner = FakeClipCommandRunner();
      processor = ClipProcessor(
        runner: runner,
        createFontFile: () async =>
            File('${directory.path}/font.ttf')..writeAsBytesSync([1, 2, 3]),
      );
    });

    tearDown(() async {
      await directory.delete(recursive: true);
    });

    ClipProcessRequest request() => ClipProcessRequest(
      sourcePath: '${directory.path}/source.mp4',
      sourceDuration: const Duration(seconds: 90),
      start: const Duration(milliseconds: 12500),
      end: const Duration(milliseconds: 52500),
      caption: 'SEMA moment',
      outputPath: '${directory.path}/output.mp4',
    );

    test(
      'builds a re-encoding command and returns the verified output',
      () async {
        runner.onExecute = (arguments) async {
          await File(arguments.last).writeAsBytes([1, 2, 3, 4]);
          return const ClipCommandResult.success();
        };

        final result = await processor.process(request());

        expect(result, ClipProcessSuccess(request().outputPath));
        expect(runner.arguments, containsAllInOrder(['-ss', '12.500']));
        expect(runner.arguments, containsAllInOrder(['-t', '40.000']));
        expect(runner.arguments, containsAllInOrder(['-map', '0:a?']));
        expect(runner.arguments, containsAllInOrder(['-c:v', 'libx264']));
        expect(runner.arguments, containsAllInOrder(['-c:a', 'aac']));
        expect(runner.arguments, containsAllInOrder(['-pix_fmt', 'yuv420p']));
        expect(
          runner.arguments,
          containsAllInOrder(['-movflags', '+faststart']),
        );
        expect(File('${directory.path}/font.ttf').existsSync(), isFalse);
      },
    );

    test('does not invoke FFmpeg for an invalid request', () async {
      final result = await processor.process(
        request().copyWith(end: const Duration(seconds: 80)),
      );

      expect(result, const ClipProcessFailure(ClipProcessError.invalidRange));
      expect(runner.arguments, isEmpty);
    });

    test('maps cancellation and removes a partial output', () async {
      runner.onExecute = (arguments) async {
        await File(arguments.last).writeAsBytes([1, 2, 3]);
        return const ClipCommandResult.cancelled();
      };

      final result = await processor.process(request());

      expect(result, const ClipProcessFailure(ClipProcessError.cancelled));
      expect(File(request().outputPath).existsSync(), isFalse);
    });

    test('cancel forwards to the active command runner', () async {
      await processor.cancel();
      expect(runner.cancelled, isTrue);
    });

    test('recognizes no-space failures without exposing native logs', () async {
      runner.onExecute = (_) async => const ClipCommandResult.failed(
        details: 'av_interleaved_write_frame: No space left on device',
      );

      final result = await processor.process(request());

      expect(result, const ClipProcessFailure(ClipProcessError.noSpace));
    });
  });
}

class FakeClipCommandRunner implements ClipCommandRunner {
  List<String> arguments = [];
  bool cancelled = false;
  Future<ClipCommandResult> Function(List<String>) onExecute = (_) async =>
      const ClipCommandResult.failed(details: 'test failure');

  @override
  Future<ClipCommandResult> execute(List<String> arguments) {
    this.arguments = arguments;
    return onExecute(arguments);
  }

  @override
  Future<void> cancel() async => cancelled = true;
}

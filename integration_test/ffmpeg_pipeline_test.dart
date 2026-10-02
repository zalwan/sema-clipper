import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sema_clipper/features/clipper/clip_export_actions.dart';
import 'package:sema_clipper/features/clipper/clip_processor.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('trims, crops, captions and encodes a vertical H.264 clip', (
    tester,
  ) async {
    const encodedVideo = String.fromEnvironment('SMOKE_VIDEO_BASE64');
    expect(
      encodedVideo,
      isNotEmpty,
      reason: 'Pass the fixture using --dart-define.',
    );

    final directory = await Directory.systemTemp.createTemp('sema-ffmpeg-');
    addTearDown(() async => directory.delete(recursive: true));
    final input = await File(
      '${directory.path}/landscape.mp4',
    ).writeAsBytes(base64Decode(encodedVideo));
    final output = File('${directory.path}/vertical-captioned.mp4');

    final result = await ClipProcessor().process(
      ClipProcessRequest(
        sourcePath: input.path,
        sourceDuration: const Duration(seconds: 4),
        start: const Duration(milliseconds: 500),
        end: const Duration(milliseconds: 2500),
        caption: "SEMA: it's 100% ready",
        outputPath: output.path,
      ),
    );
    expect(result, ClipProcessSuccess(output.path));
    expect(output.existsSync(), isTrue);
    expect(output.lengthSync(), greaterThan(1000));

    final probe = await FFprobeKit.getMediaInformation(output.path);
    final information = probe.getMediaInformation();
    expect(information, isNotNull);
    final video = information!.getStreams().singleWhere(
      (stream) => stream.getType() == 'video',
    );
    expect(video.getCodec(), 'h264');
    expect(video.getWidth(), 1080);
    expect(video.getHeight(), 1920);
    expect(double.parse(information.getDuration()!), closeTo(2, 0.5));

    final saved = await DeviceClipExportActions().saveToGallery(output.path);
    expect(saved, isTrue);
  });
}

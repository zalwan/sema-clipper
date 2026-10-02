import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

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
    final font = File('${directory.path}/DejaVuSans.ttf');
    final fontBytes = await rootBundle.load('assets/fonts/DejaVuSans.ttf');
    await font.writeAsBytes(
      Uint8List.sublistView(fontBytes),
      flush: true,
    );
    final output = File('${directory.path}/vertical-captioned.mp4');

    final filter =
        'scale=-2:1920,crop=1080:1920:(iw-1080)/2:0,'
        'drawtext=fontfile=${font.path}:text=SEMA pipeline:'
        'fontcolor=white:fontsize=64:borderw=4:bordercolor=black:'
        'x=(w-text_w)/2:y=h*2/3';
    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-ss',
      '0.5',
      '-i',
      input.path,
      '-t',
      '2',
      '-map',
      '0:v:0',
      '-map',
      '0:a?',
      '-vf',
      filter,
      '-c:v',
      'libx264',
      '-preset',
      'ultrafast',
      '-crf',
      '28',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      '-movflags',
      '+faststart',
      output.path,
    ]);
    final returnCode = await session.getReturnCode();
    final logs = await session.getAllLogsAsString();
    expect(
      ReturnCode.isSuccess(returnCode),
      isTrue,
      reason: 'FFmpeg failed (rc=$returnCode): $logs',
    );
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
  });
}

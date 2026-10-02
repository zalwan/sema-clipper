import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sema_clipper/main.dart' as app;
import 'package:video_player/video_player.dart';

import '../test/support/media_fakes.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android decodes, plays and replaces a local video', (
    tester,
  ) async {
    const encodedVideo = String.fromEnvironment('SMOKE_VIDEO_BASE64');
    expect(
      encodedVideo,
      isNotEmpty,
      reason: 'Pass the fixture using --dart-define.',
    );
    final directory = await Directory.systemTemp.createTemp('sema-smoke-');
    final video = await File(
      '${directory.path}/landscape.mp4',
    ).writeAsBytes(base64Decode(encodedVideo));
    final invalid = await File(
      '${directory.path}/invalid.mp4',
    ).writeAsString('not a video');
    final originalPicker = FilePickerPlatform.instance;
    final picker = FakePicker()..select = () async => PickedFile(video.path);
    FilePickerPlatform.instance = picker;
    addTearDown(() async {
      FilePickerPlatform.instance = originalPicker;
      await directory.delete(recursive: true);
    });

    Future<void> waitFor(Finder finder) async {
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(finder, findsOneWidget);
    }

    Future<void> tapButton(String label) async {
      final button = find.text(label);
      await tester.scrollUntilVisible(button, 150);
      await tester.pump();
      await tester.tap(button);
    }

    app.main();
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('initial');

    await tapButton('Choose video');
    await waitFor(find.text('Duration: 00:04'));
    final controller = tester
        .widget<VideoPlayer>(find.byType(VideoPlayer))
        .controller;
    expect(controller.value.size, const Size(320, 180));
    await tester.tap(find.byTooltip('Play video'));
    await tester.pump(const Duration(seconds: 1));
    expect(controller.value.isPlaying, isTrue);
    expect(controller.value.position, greaterThan(Duration.zero));
    await tester.tap(find.byTooltip('Pause video'));
    await tester.pump();
    expect(controller.value.isPlaying, isFalse);
    await binding.takeScreenshot('preview');

    picker.select = () async => null;
    await tapButton('Change video');
    await tester.pumpAndSettle();
    expect(find.text('Duration: 00:04'), findsOneWidget);

    picker.select = () async => PickedFile(invalid.path);
    await tapButton('Change video');
    await waitFor(find.textContaining('Could not load this video'));
    expect(find.byType(VideoPlayer), findsNothing);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('error');

    picker.select = () async => PickedFile(video.path);
    await tapButton('Choose video');
    await waitFor(find.text('Duration: 00:04'));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sema_clipper/main.dart' as app;
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/media_fakes.dart';

void main() {
  late FakePicker picker;
  late FakeVideoPlatform videos;

  setUp(() {
    picker = FakePicker();
    videos = FakeVideoPlatform();
    FilePickerPlatform.instance = picker;
    VideoPlayerPlatform.instance = videos;
  });

  Future<void> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    app.main();
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, {bool change = false}) async {
    final button = find.text(change ? 'Change video' : 'Choose video');
    await tester.scrollUntilVisible(button, 150);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    await tester.pump();
  }

  Future<void> load(WidgetTester tester) async {
    picker.select = () async => PickedFile('/local/landscape.mp4');
    await choose(tester);
    videos.initialize(1);
    await tester.pumpAndSettle();
  }

  testWidgets('starts with a video CTA and no allocated player', (
    tester,
  ) async {
    await launch(tester);
    expect(find.text('Create your clip'), findsOneWidget);
    expect(find.text('Choose video'), findsOneWidget);
    expect(find.byType(VideoPlayer), findsNothing);
    expect(videos.sources, isEmpty);
  });

  testWidgets('cancel from idle leaves the screen ready to choose', (
    tester,
  ) async {
    await launch(tester);
    await choose(tester);
    await tester.pumpAndSettle();
    expect(find.text('Choose video'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(videos.sources, isEmpty);
  });

  testWidgets(
    'loads a local video, keeps its ratio and displays full duration',
    (tester) async {
      await launch(tester);
      picker.select = () async => PickedFile('/local/landscape.mp4');
      await choose(tester);
      expect(find.text('Loading video…'), findsOneWidget);
      expect(picker.requestedType, FileType.video);
      expect(videos.sources.single.sourceType, DataSourceType.file);
      expect(videos.sources.single.uri, 'file:///local/landscape.mp4');
      videos.initialize(1);
      await tester.pumpAndSettle();
      expect(find.text('Duration: 01:24'), findsOneWidget);
      expect(find.byType(VideoPlayer), findsOneWidget);
      expect(
        tester.widget<AspectRatio>(find.byType(AspectRatio).first).aspectRatio,
        16 / 9,
      );
      await tester.tap(find.byTooltip('Play video'));
      await tester.pump();
      expect(videos.playing[1], isTrue);
      await tester.tap(find.byTooltip('Pause video'));
      await tester.pump();
      expect(videos.playing[1], isFalse);
    },
  );

  testWidgets('long video starts with a 60 second clip range', (tester) async {
    await launch(tester);
    await load(tester);

    expect(find.text('Choose your moment'), findsOneWidget);
    expect(find.text('Start\n00:00'), findsOneWidget);
    expect(find.text('End\n01:00'), findsOneWidget);
    expect(find.text('Clip duration: 01:00'), findsOneWidget);
    expect(find.byType(RangeSlider), findsOneWidget);
  });

  testWidgets('short video uses its full duration as the clip range', (
    tester,
  ) async {
    await launch(tester);
    picker.select = () async => PickedFile('/local/short.mp4');
    await choose(tester);
    videos.initialize(1, duration: const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.text('Start\n00:00'), findsOneWidget);
    expect(find.text('End\n00:05'), findsOneWidget);
    expect(find.text('Clip duration: 00:05'), findsOneWidget);
  });

  testWidgets('changing the range seeks and never exceeds 60 seconds', (
    tester,
  ) async {
    await launch(tester);
    await load(tester);

    var slider = tester.widget<RangeSlider>(find.byType(RangeSlider));
    slider.onChanged!(const RangeValues(12000, 52000));
    await tester.pump();

    expect(find.text('Start\n00:12'), findsOneWidget);
    expect(find.text('End\n00:52'), findsOneWidget);
    expect(find.text('Clip duration: 00:40'), findsOneWidget);
    expect(videos.seeks[1], [const Duration(seconds: 12)]);

    slider = tester.widget<RangeSlider>(find.byType(RangeSlider));
    slider.onChanged!(const RangeValues(12000, 80000));
    await tester.pump();

    expect(find.text('Start\n00:12'), findsOneWidget);
    expect(find.text('End\n01:12'), findsOneWidget);
    expect(find.text('Clip duration: 01:00'), findsOneWidget);
  });

  testWidgets('clip range cannot collapse to zero duration', (tester) async {
    await launch(tester);
    await load(tester);

    final slider = tester.widget<RangeSlider>(find.byType(RangeSlider));
    slider.onChanged!(const RangeValues(52000, 52000));
    await tester.pump();

    expect(find.text('Start\n00:51'), findsOneWidget);
    expect(find.text('End\n00:52'), findsOneWidget);
    expect(find.text('Clip duration: 00:01'), findsOneWidget);
  });

  testWidgets('cancel while changing preserves the paused preview', (
    tester,
  ) async {
    await launch(tester);
    await load(tester);
    await tester.tap(find.byTooltip('Play video'));
    await tester.pump();
    picker.select = () async => null;
    await choose(tester, change: true);
    await tester.pumpAndSettle();
    expect(find.text('Duration: 01:24'), findsOneWidget);
    expect(videos.disposed, isEmpty);
    expect(videos.playing[1], isFalse);
  });

  testWidgets('missing local path gives a recoverable message', (tester) async {
    await launch(tester);
    picker.select = () async => PickedFile.withoutPath();
    await choose(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Save it to your phone'), findsOneWidget);
    expect(videos.sources, isEmpty);
    await load(tester);
    expect(find.text('Duration: 01:24'), findsOneWidget);
    expect(find.textContaining('Save it to your phone'), findsNothing);
  });

  testWidgets(
    'corrupt video releases its player and allows another selection',
    (tester) async {
      await launch(tester);
      picker.select = () async => PickedFile('/local/bad.mp4');
      await choose(tester);
      videos.events[1]!.addError(
        PlatformException(code: 'decode', message: 'PRIVATE DECODER TRACE'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not load this video'), findsOneWidget);
      expect(find.textContaining('PRIVATE DECODER TRACE'), findsNothing);
      expect(videos.disposed, [1]);
      expect(find.byType(VideoPlayer), findsNothing);
      picker.select = () async => PickedFile('/local/good.mp4');
      await choose(tester);
      videos.initialize(2);
      await tester.pumpAndSettle();
      expect(find.text('Duration: 01:24'), findsOneWidget);
    },
  );

  testWidgets('replacement and page teardown release each native player', (
    tester,
  ) async {
    await launch(tester);
    await load(tester);
    picker.select = () async => PickedFile('/local/second.mp4');
    await choose(tester, change: true);
    expect(videos.disposed, [1]);
    expect(find.text('Duration: 01:24'), findsNothing);
    videos.initialize(2, duration: const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Duration: 00:05'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(videos.disposed, [1, 2]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late picker result after unmount creates no player', (
    tester,
  ) async {
    final result = Completer<PlatformFile?>();
    picker.select = () => result.future;
    await launch(tester);
    await choose(tester);
    await tester.pumpWidget(const SizedBox());
    result.complete(PickedFile('/local/video.mp4'));
    await tester.pump();
    expect(videos.sources, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unmount while initializing releases the native player', (
    tester,
  ) async {
    await launch(tester);
    picker.select = () async => PickedFile('/local/video.mp4');
    await choose(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(videos.disposed, [1]);
    await tester.pump(const Duration(seconds: 31));
    expect(tester.takeException(), isNull);
  });

  testWidgets('runtime decode error replaces preview with recovery UI', (
    tester,
  ) async {
    await launch(tester);
    await load(tester);
    videos.events[1]!.addError(
      PlatformException(code: 'decode', message: 'Decoder failed'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load this video'), findsOneWidget);
    expect(find.byType(VideoPlayer), findsNothing);
    expect(videos.disposed, [1]);
  });

  testWidgets('picker failure clears busy state and permits retry', (
    tester,
  ) async {
    await launch(tester);
    picker.select = () async =>
        throw PlatformException(code: 'picker_unavailable');
    await choose(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Please choose it again'), findsOneWidget);
    await load(tester);
    expect(find.text('Duration: 01:24'), findsOneWidget);
  });

  testWidgets('initialization timeout releases the player and allows retry', (
    tester,
  ) async {
    await launch(tester);
    picker.select = () async => PickedFile('/local/stalled.mp4');
    await choose(tester);
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load this video'), findsOneWidget);
    expect(videos.disposed, [1]);
    expect(find.text('Choose video'), findsOneWidget);
  });
}

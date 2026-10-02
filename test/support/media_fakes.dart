import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class FakePicker extends FilePickerPlatform {
  Future<PlatformFile?> Function() select = () async => null;
  FileType? requestedType;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) {
    requestedType = type;
    return select();
  }
}

final class PickedFile extends PlatformFile {
  PickedFile(String path) : uri = Uri.file(path);
  PickedFile.withoutPath() : uri = Uri.parse('content://video/1');

  @override
  final Uri uri;

  @override
  String get name => uri.pathSegments.last;

  // The screen reads metadata only; invoking byte-loading APIs is a test failure.
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected file operation: ${invocation.memberName}',
  );
}

class FakeVideoPlatform extends VideoPlayerPlatform {
  final sources = <DataSource>[];
  final events = <int, StreamController<VideoEvent>>{};
  final disposed = <int>[];
  final playing = <int, bool>{};
  final seeks = <int, List<Duration>>{};

  @override
  Future<void> init() async {}

  @override
  Future<int> createWithOptions(VideoCreationOptions options) async {
    sources.add(options.dataSource);
    final id = sources.length;
    events[id] = StreamController<VideoEvent>(onCancel: () async {});
    return id;
  }

  void initialize(int id, {Duration duration = const Duration(seconds: 84)}) {
    events[id]!.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: duration,
        size: const Size(1920, 1080),
      ),
    );
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
    playing.remove(playerId);
    await events[playerId]!.close();
  }

  @override
  Future<void> play(int playerId) async => playing[playerId] = true;

  @override
  Future<void> pause(int playerId) async => playing[playerId] = false;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    seeks.putIfAbsent(playerId, () => []).add(position);
  }

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand();
}

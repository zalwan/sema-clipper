import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'clip_export_actions.dart';
import 'clip_processor.dart';
import 'format_duration.dart';
import 'widgets/clip_range_selector.dart';
import 'widgets/empty_video_state.dart';
import 'widgets/video_preview.dart';

class ClipperPage extends StatefulWidget {
  const ClipperPage({this.processor, this.actions, super.key});

  final ClipProcessing? processor;
  final ClipExportActions? actions;

  @override
  State<ClipperPage> createState() => _ClipperPageState();
}

class _ClipperPageState extends State<ClipperPage> {
  VideoPlayerController? _controller;
  VideoPlayerController? _outputController;
  late final ClipProcessing _processor;
  late final ClipExportActions _actions;
  final _captionController = TextEditingController();
  String? _videoPath;
  String? _videoName;
  String? _outputPath;
  String? _errorMessage;
  String? _noticeMessage;
  bool _isChoosing = false;
  bool _isLoading = false;
  bool _isProcessing = false;
  bool _isSaving = false;
  RangeValues _clipRange = const RangeValues(0, 0);

  static const _maximumClipDuration = Duration(seconds: 60);
  static const _minimumClipDuration = Duration(seconds: 1);

  static const _loadError =
      'Could not load this video. It may be damaged or use an unsupported '
      'format. Try another video, such as an MP4.';

  @override
  void initState() {
    super.initState();
    _processor = widget.processor ?? ClipProcessor();
    _actions = widget.actions ?? DeviceClipExportActions();
  }

  Future<void> _chooseVideo() async {
    if (_isChoosing || _isProcessing) return;
    setState(() => _isChoosing = true);
    try {
      await _controller?.pause();
      if (!mounted) return;
      final file = await FilePicker.pickFile(type: FileType.video);
      if (!mounted || file == null) return;

      final path = file.path;
      if (path == null || path.trim().isEmpty) {
        setState(() {
          _errorMessage =
              'Could not access this file. Save it to your phone and choose it again.';
        });
        return;
      }

      _releaseOutput();
      _releaseVideo();
      _captionController.clear();
      final controller = VideoPlayerController.file(File(path));
      setState(() {
        _controller = controller;
        _videoPath = path;
        _videoName = file.name;
        _errorMessage = null;
        _noticeMessage = null;
        _isLoading = true;
      });

      try {
        // Some native decoders never return metadata for malformed files.
        await controller.initialize().timeout(const Duration(seconds: 30));
        if (!mounted || _controller != controller) return;
        final value = controller.value;
        if (value.hasError ||
            value.duration <= Duration.zero ||
            value.size.width <= 0 ||
            value.size.height <= 0) {
          throw const FormatException('No playable video track');
        }
        controller.addListener(_handleVideoError);
        setState(() {
          _clipRange = RangeValues(
            0,
            value.duration > _maximumClipDuration
                ? _maximumClipDuration.inMilliseconds.toDouble()
                : value.duration.inMilliseconds.toDouble(),
          );
          _isLoading = false;
        });
      } catch (_) {
        if (!mounted || _controller != controller) return;
        _releaseVideo();
        setState(() => _errorMessage = _loadError);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not open your video. Please choose it again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isChoosing = false;
          _isLoading = false;
        });
      }
    }
  }

  void _handleVideoError() {
    if (!mounted || _controller?.value.hasError != true) return;
    _releaseVideo();
    setState(() => _errorMessage = _loadError);
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || _isChoosing) return;
    try {
      if (controller.value.isPlaying) {
        await controller.pause();
      } else {
        await controller.play();
      }
    } catch (_) {
      if (!mounted || _controller != controller) return;
      _releaseVideo();
      setState(() => _errorMessage = _loadError);
    }
  }

  Future<void> _toggleOutputPlayback() async {
    final controller = _outputController;
    if (controller == null) return;
    try {
      if (controller.value.isPlaying) {
        await controller.pause();
      } else {
        await controller.play();
      }
    } catch (_) {
      if (!mounted || _outputController != controller) return;
      _releaseOutput();
      setState(() => _errorMessage = 'Could not play the exported clip.');
    }
  }

  void _updateClipRange(RangeValues proposed) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final maximum = controller.value.duration.inMilliseconds.toDouble();
    var start = proposed.start.clamp(0.0, maximum);
    var end = proposed.end.clamp(0.0, maximum);
    final movedStart = (start - _clipRange.start).abs();
    final movedEnd = (end - _clipRange.end).abs();
    final maximumLength = _maximumClipDuration.inMilliseconds.toDouble();
    final minimumLength = _minimumClipDuration.inMilliseconds
        .clamp(0, maximum)
        .toDouble();

    if (end - start > maximumLength) {
      if (movedStart >= movedEnd) {
        start = (end - maximumLength).clamp(0.0, maximum);
      } else {
        end = (start + maximumLength).clamp(0.0, maximum);
      }
    }
    if (end - start < minimumLength) {
      if (movedStart >= movedEnd) {
        start = (end - minimumLength).clamp(0.0, maximum);
      } else {
        end = (start + minimumLength).clamp(0.0, maximum);
      }
    }

    final seekPosition = movedStart >= movedEnd ? start : end;
    setState(() => _clipRange = RangeValues(start, end));
    unawaited(controller.pause());
    unawaited(controller.seekTo(Duration(milliseconds: seekPosition.round())));
  }

  Future<void> _exportClip() async {
    final sourceController = _controller;
    final sourcePath = _videoPath;
    if (_isProcessing || sourceController == null || sourcePath == null) return;

    await sourceController.pause();
    _releaseOutput();
    final outputPath =
        '${Directory.systemTemp.path}/sema-clip-${DateTime.now().microsecondsSinceEpoch}.mp4';
    if (!mounted) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _noticeMessage = null;
    });

    final result = await _processor.process(
      ClipProcessRequest(
        sourcePath: sourcePath,
        sourceDuration: sourceController.value.duration,
        start: Duration(milliseconds: _clipRange.start.round()),
        end: Duration(milliseconds: _clipRange.end.round()),
        caption: _captionController.text,
        outputPath: outputPath,
      ),
    );
    if (!mounted) {
      await _deleteOutputFile(outputPath);
      return;
    }

    if (result case ClipProcessSuccess(:final path)) {
      final outputController = VideoPlayerController.file(File(path));
      try {
        await outputController.initialize().timeout(
          const Duration(seconds: 30),
        );
        if (!mounted) {
          await outputController.dispose();
          await _deleteOutputFile(outputPath);
          return;
        }
        setState(() {
          _outputController = outputController;
          _outputPath = path;
          _isProcessing = false;
          _noticeMessage = null;
        });
      } catch (_) {
        await outputController.dispose();
        await _deleteOutputFile(outputPath);
        setState(() {
          _isProcessing = false;
          _errorMessage = 'The clip was created but could not be previewed.';
        });
      }
      return;
    }

    final error = (result as ClipProcessFailure).error;
    setState(() {
      _isProcessing = false;
      _errorMessage = switch (error) {
        ClipProcessError.invalidRange =>
          'Choose a clip between 1 and 60 seconds.',
        ClipProcessError.invalidCaption =>
          'Enter one caption of up to $maximumCaptionLength characters.',
        ClipProcessError.noSpace =>
          'There is not enough storage. Please free up some space and try again.',
        ClipProcessError.cancelled => 'Export cancelled.',
        ClipProcessError.processingFailed =>
          'Could not create this clip. Try a different video or shorter range.',
      };
    });
  }

  Future<void> _cancelExport() async {
    if (!_isProcessing) return;
    await _processor.cancel();
  }

  Future<void> _saveOutput() async {
    final path = _outputPath;
    if (path == null || _isSaving) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final saved = await _actions.saveToGallery(path);
      if (!mounted) return;
      setState(() {
        _noticeMessage = saved ? 'Saved to your gallery.' : null;
        _errorMessage = saved
            ? null
            : 'Could not save to the gallery. You can still use Share.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Could not save to the gallery. You can still use Share.';
      });
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _shareOutput() async {
    final path = _outputPath;
    if (path == null) return;
    try {
      await _actions.share(path);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Could not open the share sheet.');
    }
  }

  void _releaseVideo() {
    final controller = _controller;
    _controller = null;
    _videoPath = null;
    _videoName = null;
    _clipRange = const RangeValues(0, 0);
    if (controller != null) {
      controller.removeListener(_handleVideoError);
      unawaited(_disposeController(controller));
    }
  }

  void _releaseOutput() {
    final controller = _outputController;
    final path = _outputPath;
    _outputController = null;
    _outputPath = null;
    if (controller != null) unawaited(_disposeController(controller));
    if (path != null) {
      unawaited(_deleteOutputFile(path));
    }
  }

  Future<void> _deleteOutputFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Temporary output cleanup is best-effort.
    }
  }

  Future<void> _disposeController(VideoPlayerController controller) async {
    try {
      await controller.dispose();
    } catch (_) {
      // A native decoder may already be gone after an initialization failure.
    }
  }

  @override
  void dispose() {
    if (_isProcessing) unawaited(_processor.cancel());
    _captionController.dispose();
    _releaseOutput();
    _releaseVideo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = _controller;
    final outputController = _outputController;
    final ready =
        controller != null && controller.value.isInitialized && !_isLoading;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 12),
                Text(
                  'SEMA / CLIPPER',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Create your clip',
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  ready
                      ? 'Take a look at your source video.'
                      : 'A great clip starts with a great moment.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 64),
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 20),
                        Text('Loading video…'),
                      ],
                    ),
                  )
                else if (ready) ...[
                  VideoPreview(
                    key: ValueKey(_videoPath),
                    controller: controller,
                    onTogglePlayback: _isChoosing ? null : _togglePlayback,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _videoName ?? 'Selected video',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Duration: ${formatDuration(controller.value.duration)}',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 20),
                  ClipRangeSelector(
                    sourceDuration: controller.value.duration,
                    values: _clipRange,
                    onChanged: _updateClipRange,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _captionController,
                    maxLength: maximumCaptionLength,
                    maxLines: 1,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Caption',
                      hintText: 'Add one line to your clip',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_isProcessing) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    const Text(
                      'Creating your vertical clip…',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _cancelExport,
                      child: const Text('Cancel export'),
                    ),
                  ] else
                    FilledButton.icon(
                      onPressed: _exportClip,
                      icon: const Icon(Icons.movie_creation_outlined),
                      label: const Text('Export clip'),
                    ),
                  if (outputController != null &&
                      outputController.value.isInitialized) ...[
                    const SizedBox(height: 32),
                    Text(
                      'Your clip is ready',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    VideoPreview(
                      key: ValueKey(_outputPath),
                      controller: outputController,
                      onTogglePlayback: _toggleOutputPlayback,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isSaving ? null : _saveOutput,
                            icon: const Icon(Icons.download_outlined),
                            label: Text(
                              _isSaving ? 'Saving…' : 'Save to gallery',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _shareOutput,
                            icon: const Icon(Icons.share_outlined),
                            label: const Text('Share'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ] else
                  const EmptyVideoState(),
                if (_noticeMessage != null) ...[
                  const SizedBox(height: 20),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _noticeMessage!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 20),
                  Semantics(
                    liveRegion: true,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isChoosing || _isProcessing ? null : _chooseVideo,
                  icon: Icon(ready ? Icons.swap_horiz : Icons.add),
                  label: Text(
                    _isChoosing
                        ? 'Opening video…'
                        : (ready ? 'Change video' : 'Choose video'),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Your video stays on this device.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

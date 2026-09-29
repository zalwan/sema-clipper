import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'format_duration.dart';
import 'widgets/empty_video_state.dart';
import 'widgets/video_preview.dart';

class ClipperPage extends StatefulWidget {
  const ClipperPage({super.key});

  @override
  State<ClipperPage> createState() => _ClipperPageState();
}

class _ClipperPageState extends State<ClipperPage> {
  VideoPlayerController? _controller;
  String? _videoPath;
  String? _videoName;
  String? _errorMessage;
  bool _isChoosing = false;
  bool _isLoading = false;

  static const _loadError =
      'Could not load this video. It may be damaged or use an unsupported '
      'format. Try another video, such as an MP4.';

  Future<void> _chooseVideo() async {
    if (_isChoosing) return;
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

      _releaseVideo();
      final controller = VideoPlayerController.file(File(path));
      setState(() {
        _controller = controller;
        _videoPath = path;
        _videoName = file.name;
        _errorMessage = null;
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
        setState(() => _isLoading = false);
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

  void _releaseVideo() {
    final controller = _controller;
    _controller = null;
    _videoPath = null;
    _videoName = null;
    if (controller != null) {
      controller.removeListener(_handleVideoError);
      unawaited(_disposeController(controller));
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
    _releaseVideo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = _controller;
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
                ] else
                  const EmptyVideoState(),
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
                  onPressed: _isChoosing ? null : _chooseVideo,
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

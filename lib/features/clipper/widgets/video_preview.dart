import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../format_duration.dart';

class VideoPreview extends StatelessWidget {
  const VideoPreview({
    required this.controller,
    required this.onTogglePlayback,
    super.key,
  });

  final VideoPlayerController controller;
  final VoidCallback? onTogglePlayback;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: ColoredBox(
        color: colors.surfaceContainer,
        child: Column(
          children: [
            ColoredBox(
              color: Colors.black,
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: controller,
              builder: (context, value, child) => Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: value.isPlaying ? 'Pause video' : 'Play video',
                      onPressed: onTogglePlayback,
                      icon: Icon(
                        value.isPlaying ? Icons.pause : Icons.play_arrow,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: value.duration.inMilliseconds > 0
                            ? (value.position.inMilliseconds /
                                      value.duration.inMilliseconds)
                                  .clamp(0.0, 1.0)
                            : 0,
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(4),
                        semanticsLabel: 'Playback progress',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(formatDuration(value.position)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

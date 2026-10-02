import 'package:flutter/material.dart';

import '../format_duration.dart';

class ClipRangeSelector extends StatelessWidget {
  const ClipRangeSelector({
    required this.sourceDuration,
    required this.values,
    required this.onChanged,
    super.key,
  });

  final Duration sourceDuration;
  final RangeValues values;
  final ValueChanged<RangeValues> onChanged;

  Duration get _start => Duration(milliseconds: values.start.round());
  Duration get _end => Duration(milliseconds: values.end.round());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedDuration = _end - _start;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Choose your moment', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Select up to 60 seconds.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          RangeSlider(
            values: values,
            min: 0,
            max: sourceDuration.inMilliseconds.toDouble(),
            labels: RangeLabels(formatDuration(_start), formatDuration(_end)),
            onChanged: onChanged,
          ),
          Row(
            children: [
              Expanded(child: Text('Start\n${formatDuration(_start)}')),
              Expanded(
                flex: 2,
                child: Text(
                  'Clip duration: ${formatDuration(selectedDuration)}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'End\n${formatDuration(_end)}',
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

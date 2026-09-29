import 'package:flutter_test/flutter_test.dart';
import 'package:sema_clipper/features/clipper/format_duration.dart';

void main() {
  test('formats source durations without wrapping after an hour', () {
    const cases = {
      0: '00:00',
      9: '00:09',
      60: '01:00',
      84: '01:24',
      3599: '59:59',
      3600: '1:00:00',
      3661: '1:01:01',
    };
    for (final entry in cases.entries) {
      expect(formatDuration(Duration(seconds: entry.key)), entry.value);
    }
    expect(formatDuration(const Duration(milliseconds: 84999)), '01:24');
  });
}

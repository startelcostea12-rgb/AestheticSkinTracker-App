import 'package:flutter_test/flutter_test.dart';
import 'package:aesthetic_skin_tracker/utils/skincare_streak.dart';

void main() {
  group('SkincareStreakCalculator', () {
    test('counts consecutive logged days', () {
      final now = DateTime(2026, 8, 20, 14, 0);
      final dates = [
        DateTime(2026, 8, 16),
        DateTime(2026, 8, 17),
        DateTime(2026, 8, 18),
        DateTime(2026, 8, 19),
        DateTime(2026, 8, 20),
      ];

      expect(
        SkincareStreakCalculator.computeCurrentStreak(dates, now: now),
        5,
      );
    });

    test('resets after a gap day', () {
      final now = DateTime(2026, 8, 20, 14, 0);
      final dates = [
        DateTime(2026, 8, 15),
        DateTime(2026, 8, 16),
        DateTime(2026, 8, 17),
        DateTime(2026, 8, 19),
        DateTime(2026, 8, 20),
      ];

      expect(
        SkincareStreakCalculator.computeCurrentStreak(dates, now: now),
        2,
      );
    });

    test('does not falsely reset before the day ends', () {
      final now = DateTime(2026, 8, 20, 10, 0);
      final dates = [
        DateTime(2026, 8, 17),
        DateTime(2026, 8, 18),
        DateTime(2026, 8, 19),
      ];

      expect(
        SkincareStreakCalculator.computeCurrentStreak(dates, now: now),
        3,
      );
    });
  });
}

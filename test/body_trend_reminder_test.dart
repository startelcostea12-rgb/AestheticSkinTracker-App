import 'package:aesthetic_skin_tracker/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bodyTrendReminderAction', () {
    test('schedules after an insufficient first body scan', () {
      expect(
        bodyTrendReminderAction(
          trendStatus: 'insufficient_signal',
          consistentScanCount: 1,
        ),
        BodyTrendReminderAction.schedule,
      );
    });

    test('cancels when a qualifying second scan clears the requirement', () {
      expect(
        bodyTrendReminderAction(
          trendStatus: 'stable',
          consistentScanCount: kBodyTrendRequiredConsistentScans,
          priorConsistentScanCount: 1,
        ),
        BodyTrendReminderAction.cancel,
      );
    });

    test('does not schedule when the requirement is already met', () {
      expect(
        bodyTrendReminderAction(
          trendStatus: 'insufficient_signal',
          consistentScanCount: kBodyTrendRequiredConsistentScans,
          priorConsistentScanCount: 1,
        ),
        BodyTrendReminderAction.cancel,
      );
    });

    test('schedules again when an inconsistent capture resets a streak', () {
      expect(
        bodyTrendReminderAction(
          trendStatus: 'stable',
          consistentScanCount: 1,
          priorConsistentScanCount: kBodyTrendRequiredConsistentScans,
        ),
        BodyTrendReminderAction.schedule,
      );
    });
  });
}

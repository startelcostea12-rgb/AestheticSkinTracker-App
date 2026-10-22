/// Deleting procedures also cancels the local reminders scheduled for them
/// (recovery-plan days, appointment, body trend), so no reminder fires for
/// a procedure that no longer exists. A failed cancel is logged and never
/// blocks the deletion.
library;

import 'package:flutter/foundation.dart';

import '../services/notification_service.dart';
import 'app_prefs.dart';

Future<void> _cancelReminders(
  NotificationService notifications,
  String procedureId,
) async {
  try {
    await notifications.cancelProcedureReminders(procedureId);
  } catch (e) {
    debugPrint('[procedure_deletion] cancel reminders for $procedureId: $e');
  }
}

/// Removes [procedureId] from procedure history and cancels its reminders.
Future<void> deleteProcedureAndReminders(
  String procedureId, {
  NotificationService? notifications,
}) async {
  await AppPrefs.removeProcedureFromHistory(procedureId);
  await _cancelReminders(notifications ?? NotificationService(), procedureId);
}

/// Cancels the reminders of every saved procedure. Call before a bulk clear
/// that deletes all procedures.
Future<void> cancelRemindersForAllProcedures({
  NotificationService? notifications,
}) async {
  final service = notifications ?? NotificationService();
  for (final entry in await AppPrefs.getProcedureEntries()) {
    final id = entry['id']?.toString();
    if (id == null || id.isEmpty) continue;
    await _cancelReminders(service, id);
  }
}

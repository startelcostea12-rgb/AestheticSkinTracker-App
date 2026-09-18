import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive/hive.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/peptide_model.dart';
import '../models/procedure_log.dart';
import '../models/recovery_plan.dart';
import '../utils/app_prefs.dart';
import '../utils/peptide_service.dart';

// PROVISIONAL: revise after real same-person body tracking data accumulates.
const int kBodyTrendRequiredConsistentScans = 2;

enum BodyTrendReminderAction { schedule, cancel }

BodyTrendReminderAction bodyTrendReminderAction({
  required String? trendStatus,
  required int consistentScanCount,
  int priorConsistentScanCount = 0,
}) {
  final status = trendStatus?.trim().toLowerCase();
  final needsFirstFollowUp =
      status == 'insufficient_signal' &&
      consistentScanCount < kBodyTrendRequiredConsistentScans;
  final streakReset = priorConsistentScanCount > 0 &&
      consistentScanCount == 1;
  return needsFirstFollowUp || streakReset
      ? BodyTrendReminderAction.schedule
      : BodyTrendReminderAction.cancel;
}

/// Premium notification service for aesthetic procedure reminders.
///
/// Handles scheduling and displaying elegant treatment reminders for
/// professional injectables (Botox, fillers) and other tracked procedures.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Initialize the notification service with platform-specific settings.
  Future<void> initialize() async {
    if (_initialized) return;

    // Initialize timezone data for scheduling
    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channel for Android
    const androidChannel = AndroidNotificationChannel(
      'procedure_reminders',
      'Procedure Reminders',
      description: 'Reminders for upcoming aesthetic treatments',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(androidChannel);

    _initialized = true;
  }

  /// Request notification permissions (required for iOS/macOS).
  Future<bool> requestPermissions() async {
    // Request permission_handler notification permission
    final status = await Permission.notification.request();

    if (status.isDenied || status.isPermanentlyDenied) {
      return false;
    }

    // Also request platform-specific permissions for iOS/macOS
    final iosImplementation = _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();

    if (iosImplementation != null) {
      await iosImplementation.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    final macImplementation = _notifications
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();

    if (macImplementation != null) {
      await macImplementation.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    return true;
  }

  /// Schedule a reminder notification for a procedure log.
  ///
  /// Creates an elegant notification to remind the user when their next
  /// treatment is approaching (e.g., Botox at 3 months, fillers at 6 months).
  Future<void> scheduleReminderForProcedure(ProcedureLog log) async {
    if (!_initialized) {
      await initialize();
    }

    // Only schedule if reminder is enabled and date is set
    if (!log.reminderEnabled || log.nextReminderDate == null) {
      return;
    }

    // Don't schedule past reminders
    if (log.nextReminderDate!.isBefore(DateTime.now())) {
      return;
    }

    final scheduledDate = tz.TZDateTime.from(log.nextReminderDate!, tz.local);
    final notificationId = log.id.hashCode.abs();

    final procedureName = log.procedureType;

    const androidDetails = AndroidNotificationDetails(
      'procedure_reminders',
      'Procedure Reminders',
      channelDescription: 'Reminders for upcoming aesthetic treatments',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(''),
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    await _notifications.zonedSchedule(
      notificationId,
      '✨ Time for your next $procedureName',
      'Your ${log.expectedDuration ?? 'treatment window'} is approaching. Consider scheduling your appointment.',
      scheduledDate,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Cancel a reminder for a specific procedure log.
  Future<void> cancelReminder(String procedureLogId) async {
    final notificationId = procedureLogId.hashCode.abs();
    await _notifications.cancel(notificationId);
  }

  Future<void> scheduleBodyTrendReminder({
    required String procedureId,
    required String procedureName,
    required int consistentScanCount,
  }) async {
    if (!await AppPrefs.getNotificationsEnabled()) return;
    if (consistentScanCount >= kBodyTrendRequiredConsistentScans) return;
    if (!_initialized) await initialize();

    final notificationId = 'body_trend_$procedureId'.hashCode.abs();
    const androidDetails = AndroidNotificationDetails(
      'procedure_reminders',
      'Procedure Reminders',
      channelDescription: 'Local recovery and body tracking check-ins',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );
    final name = procedureName.trim().isEmpty ? 'body procedure' : procedureName.trim();
    await _notifications.zonedSchedule(
      notificationId,
      'Continue your $name tracking',
      'Take your next $name scan to start seeing your body tracking trend. '
          '$kBodyTrendRequiredConsistentScans consistent scans are needed to unlock trends.',
      tz.TZDateTime.now(tz.local).add(const Duration(days: 3)),
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelBodyTrendReminder(String procedureId) async {
    final notificationId = 'body_trend_$procedureId'.hashCode.abs();
    await _notifications.cancel(notificationId);
  }

  Future<void> scheduleRecoveryPlanReminders({
    required String procedureId,
    required String procedureName,
    required DateTime startDate,
    required RecoveryPlan plan,
  }) async {
    if (!await AppPrefs.getNotificationsEnabled()) return;
    if (!_initialized) await initialize();

    const androidDetails = AndroidNotificationDetails(
      'procedure_reminders',
      'Procedure Reminders',
      channelDescription: 'Local recovery and procedure tracking check-ins',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    final name = procedureName.trim().isEmpty ? 'procedure' : procedureName.trim();
    final now = DateTime.now();
    for (final day in plan.days) {
      final reminder = day.reminder;
      final localDate = DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
        reminder.hour,
        reminder.minute,
      ).add(Duration(days: day.day - 1));
      if (localDate.isBefore(now)) continue;
      await _notifications.zonedSchedule(
        'recovery_plan_${procedureId}_${day.day}'.hashCode.abs(),
        reminder.title,
        '$name day ${day.day}: ${reminder.body}',
        tz.TZDateTime.from(localDate, tz.local),
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  Future<void> cancelRecoveryPlanReminders(String procedureId) async {
    for (var day = 1; day <= 7; day++) {
      await _notifications.cancel('recovery_plan_${procedureId}_$day'.hashCode.abs());
    }
  }

  /// Schedule a daily/weekly reminder for an active peptide routine.
  Future<void> scheduleReminderForPeptide(PeptideEntry peptide) async {
    if (!_initialized) {
      await initialize();
    }

    if (!await AppPrefs.getNotificationsEnabled()) {
      return;
    }

    final now = DateTime.now();
    final nextBase = peptide.startDate.toLocal();
    DateTime scheduledDate = nextBase.isAfter(now)
        ? nextBase
        : now.add(const Duration(hours: 1));

    final lower = peptide.frequency.toLowerCase();
    if (lower.contains('daily')) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    } else if (lower.contains('weekly')) {
      scheduledDate = scheduledDate.add(const Duration(days: 7));
    } else if (lower.contains('month')) {
      scheduledDate = scheduledDate.add(const Duration(days: 30));
    } else if (lower.contains('twice')) {
      scheduledDate = scheduledDate.add(const Duration(days: 3));
    }

    final notificationId = 'peptide_${peptide.id}'.hashCode.abs();

    const androidDetails = AndroidNotificationDetails(
      'procedure_reminders',
      'Procedure Reminders',
      channelDescription: 'Local recovery and routine check-ins',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    await _notifications.zonedSchedule(
      notificationId,
      '💧 ${peptide.name} routine check-in',
      'Your ${peptide.frequency.toLowerCase()} peptide routine is due. Check in on your skin and recovery notes.',
      tz.TZDateTime.from(scheduledDate, tz.local),
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Reconcile local reminders with the current app data model.
  Future<void> resyncScheduledReminders() async {
    if (!await AppPrefs.getNotificationsEnabled()) {
      await cancelAllReminders();
      return;
    }

    final box = Hive.isBoxOpen('procedureLogs')
        ? Hive.box<ProcedureLog>('procedureLogs')
        : await Hive.openBox<ProcedureLog>('procedureLogs');

    for (final log in box.values) {
      if (log.reminderEnabled && log.nextReminderDate != null) {
        await scheduleReminderForProcedure(log);
      }
    }

    final peptides = await PeptideService.loadAll();
    for (final peptide in peptides.where((entry) => entry.isActive)) {
      await scheduleReminderForPeptide(peptide);
    }
  }

  /// Cancel all scheduled reminders.
  Future<void> cancelAllReminders() async {
    await _notifications.cancelAll();
  }

  /// Handle notification tap (navigate to relevant screen).
  void _onNotificationTapped(NotificationResponse response) {
    // Future enhancement: navigate to procedure log detail screen
    // For now, just opens the app
  }

  /// Check if notifications are enabled.
  Future<bool> areNotificationsEnabled() async {
    final status = await Permission.notification.status;
    return status.isGranted;
  }
}

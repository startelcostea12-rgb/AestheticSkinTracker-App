import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/procedure_log.dart';

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

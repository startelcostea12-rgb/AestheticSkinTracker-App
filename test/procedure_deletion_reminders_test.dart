import 'dart:io';

import 'package:aesthetic_skin_tracker/models/procedure.dart';
import 'package:aesthetic_skin_tracker/models/recovery_plan.dart';
import 'package:aesthetic_skin_tracker/services/notification_service.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import 'package:aesthetic_skin_tracker/utils/procedure_deletion.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('dexterous.com/flutter/local_notifications');

/// Notification IDs the fake platform currently has pending.
final Set<int> _pending = <int>{};

int _idOf(Object? arguments) =>
    arguments is Map ? (arguments['id'] as num).toInt() : (arguments as int);

RecoveryPlan _plan() => RecoveryPlan(
  id: 'plan',
  procedureType: 'Microneedling',
  title: 'Plan',
  reviewStatus: '',
  disclaimer: '',
  days: [
    for (var day = 1; day <= 7; day++)
      RecoveryPlanDay(
        day: day,
        whatsCommon: '',
        watchFor: '',
        suggestedAction: '',
        reminder: const RecoveryPlanReminder(
          kind: 'note',
          hour: 9,
          minute: 0,
          title: 'Check-in',
          body: 'How is it going?',
        ),
      ),
  ],
);

Procedure _procedure(String id) => Procedure(
  id: id,
  type: 'Microneedling',
  provider: 'Clinic',
  // Starts tomorrow, so every plan day is in the future and scheduled.
  startDate: DateTime.now().add(const Duration(days: 1)),
  numSessions: 1,
  nextAppointmentDate: DateTime.now().add(const Duration(days: 30)),
);

Set<int> _expectedIds(String id) => {
  for (var day = 1; day <= 7; day++)
    NotificationService.recoveryPlanReminderId(id, day),
  NotificationService.appointmentReminderId(id),
};

Future<void> _scheduleAll(Procedure procedure) async {
  final service = NotificationService();
  await service.scheduleRecoveryPlanReminders(
    procedureId: procedure.id,
    procedureName: procedure.type,
    startDate: procedure.startDate,
    plan: _plan(),
  );
  await service.scheduleAppointmentReminder(procedure);
  await AppPrefs.addProcedureToHistory(procedure.toJson());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      AppPrefs.notificationsEnabledKey: true,
    });
    _pending.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          switch (call.method) {
            case 'initialize':
              return true;
            case 'zonedSchedule':
              _pending.add(_idOf(call.arguments));
            case 'cancel':
              _pending.remove(_idOf(call.arguments));
            case 'cancelAll':
              _pending.clear();
          }
          return null;
        });
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );

  test('deleting a procedure cancels its reminders; others stay', () async {
    await _scheduleAll(_procedure('proc-a'));
    await _scheduleAll(_procedure('proc-b'));
    expect(_pending, {..._expectedIds('proc-a'), ..._expectedIds('proc-b')});

    await deleteProcedureAndReminders('proc-a');

    expect(_pending, _expectedIds('proc-b'));
    final remaining = await AppPrefs.getProcedureEntries();
    expect([for (final e in remaining) e['id']], ['proc-b']);
  });

  test(
    'clearing all procedures cancels every procedure\'s reminders',
    () async {
      await _scheduleAll(_procedure('proc-a'));
      await _scheduleAll(_procedure('proc-b'));
      final unrelated = 'peptide_reminder'.hashCode.abs();
      _pending.add(unrelated);

      await cancelRemindersForAllProcedures();

      expect(_pending, {unrelated});
    },
  );

  test('a failed cancel does not block deletion', () async {
    await AppPrefs.addProcedureToHistory(_procedure('proc-a').toJson());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          throw PlatformException(code: 'unavailable');
        });

    await deleteProcedureAndReminders('proc-a');

    expect(await AppPrefs.getProcedureEntries(), isEmpty);
  });

  test('schedule and cancel use the same IDs', () {
    final source = File(
      'lib/services/notification_service.dart',
    ).readAsStringSync();
    expect("'recovery_plan_".allMatchesIn(source), 1);
    expect("'appointment_".allMatchesIn(source), 1);
    expect("'body_trend_".allMatchesIn(source), 1);
  });

  test('wiring: every procedure delete path cancels reminders', () {
    final profiles = File(
      'lib/features/procedures/presentation/procedure_profiles_screen.dart',
    ).readAsStringSync();
    expect(
      profiles,
      contains('await deleteProcedureAndReminders(_procedure.id);'),
    );
    expect(profiles, isNot(contains('removeProcedureFromHistory')));
    final settings = File(
      'lib/screens/settings_screen.dart',
    ).readAsStringSync();
    expect(
      settings,
      contains(
        'await cancelRemindersForAllProcedures();\n'
        '    await AppPrefs.clearProcedureHistory();',
      ),
    );
    expect(
      settings,
      contains(
        'await cancelRemindersForAllProcedures();\n'
        '    await AppPrefs.clearAllDataAggressively();',
      ),
    );
    // Nothing else removes procedures from history (app_prefs.dart only
    // defines them).
    final removers = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.path.endsWith('app_prefs.dart')) continue;
      final text = file.readAsStringSync();
      if (text.contains('removeProcedureFromHistory(') ||
          text.contains('AppPrefs.clearProcedureHistory(')) {
        removers.add(file.path.replaceAll(r'\', '/'));
      }
    }
    removers.sort();
    expect(removers, [
      'lib/screens/settings_screen.dart',
      'lib/utils/procedure_deletion.dart',
    ]);
  });
}

extension on String {
  int allMatchesIn(String source) => allMatches(source).length;
}

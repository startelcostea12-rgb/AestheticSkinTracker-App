import 'dart:io';

import 'package:aesthetic_skin_tracker/models/procedure_log.dart';
import 'package:aesthetic_skin_tracker/providers/procedure_logs_provider.dart';
import 'package:aesthetic_skin_tracker/screens/at_home_procedure_log_screen.dart';
import 'package:aesthetic_skin_tracker/screens/procedure_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for the Hive-backed notifier, recording calls.
class _FakeLogs extends ProcedureLogsNotifier {
  _FakeLogs(this._logs);

  final List<ProcedureLog> _logs;
  final added = <ProcedureLog>[];
  final updated = <ProcedureLog>[];
  final deleted = <String>[];

  @override
  Future<List<ProcedureLog>> build() async => List.of(_logs);

  @override
  Future<List<ProcedureLog>> fetchLogs() async {
    state = AsyncData(List.of(_logs));
    return List.of(_logs);
  }

  @override
  Future<void> addLog(ProcedureLog log) async {
    added.add(log);
    _logs.add(log);
    state = AsyncData(List.of(_logs));
  }

  @override
  Future<void> updateLog(ProcedureLog log) async {
    updated.add(log);
    final i = _logs.indexWhere((l) => l.id == log.id);
    _logs[i] = log;
    state = AsyncData(List.of(_logs));
  }

  @override
  Future<void> deleteLog(String id) async {
    deleted.add(id);
    _logs.removeWhere((l) => l.id == id);
    state = AsyncData(List.of(_logs));
  }
}

ProcedureLog _log(String id, String type, {String? notes}) => ProcedureLog(
  id: id,
  procedureType: type,
  dateTime: DateTime(2026, 10, id == 'log-a' ? 1 : 5, 9),
  createdAt: DateTime(2026, 10, 1),
  notes: notes,
  intensity: 4,
  reactionScore: 6,
  settings: 'Category: At-Home\nSettings: 1.0mm, 2 passes',
  productsUsed: const ['GHK-Cu', 'My Recovery Balm'],
  aiFeedback: 'kept',
);

Future<void> _pump(
  WidgetTester tester,
  _FakeLogs fake,
  Widget home, {
  double width = 430,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 5000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [procedureLogsProvider.overrideWith(() => fake)],
      child: MaterialApp(home: home),
    ),
  );
  await tester.pumpAndSettle();
}

const _notifications = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);

/// Notification IDs cancelled through the plugin.
final List<int> _cancelled = <int>[];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _cancelled.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_notifications, (call) async {
          if (call.method == 'cancel') {
            final args = call.arguments;
            _cancelled.add(
              args is Map ? (args['id'] as num).toInt() : args as int,
            );
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_notifications, null),
  );

  group('provider (Hive)', () {
    late Directory dir;
    setUpAll(() {
      dir = Directory.systemTemp.createTempSync('procedure_logs_test');
      Hive.init(dir.path);
      if (!Hive.isAdapterRegistered(ProcedureLogAdapter().typeId)) {
        Hive.registerAdapter(ProcedureLogAdapter());
      }
    });
    tearDownAll(() async {
      await Hive.close();
      dir.deleteSync(recursive: true);
    });

    test('delete removes only that entry; update edits in place', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(procedureLogsProvider.notifier);
      await container.read(procedureLogsProvider.future);
      await notifier.addLog(_log('log-a', 'Red Light Therapy'));
      await notifier.addLog(_log('log-b', 'At-Home Chemical Peel'));

      final edited = _log('log-a', 'Red Light Therapy', notes: 'Edited');
      await notifier.updateLog(edited);
      var logs = container.read(procedureLogsProvider).value!;
      expect(logs.map((l) => l.id).toSet(), {'log-a', 'log-b'});
      expect(logs.firstWhere((l) => l.id == 'log-a').notes, 'Edited');

      await notifier.deleteLog('log-a');
      logs = container.read(procedureLogsProvider).value!;
      expect([for (final l in logs) l.id], ['log-b']);
      expect(logs.single.procedureType, 'At-Home Chemical Peel');
    });
  });

  testWidgets('delete from the menu removes only that log', (tester) async {
    final fake = _FakeLogs([
      _log('log-a', 'Red Light Therapy'),
      _log('log-b', 'At-Home Chemical Peel'),
    ]);
    await _pump(tester, fake, const ProcedureHistoryScreen());
    expect(find.text('Red Light Therapy'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('procedure_log_menu_log-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this log?'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('procedure_log_delete_confirm')),
    );
    await tester.pumpAndSettle();

    expect(fake.deleted, ['log-a']);
    // Its reminder is cancelled too (cancelReminder's ID).
    expect(_cancelled, ['log-a'.hashCode.abs()]);
    expect(
      find.byKey(const ValueKey('procedure_log_menu_log-a')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('procedure_log_menu_log-b')),
      findsOneWidget,
    );
    expect(find.text('Procedure log deleted.'), findsOneWidget);
  });

  testWidgets('cancelling the delete keeps the log', (tester) async {
    final fake = _FakeLogs([_log('log-a', 'Red Light Therapy')]);
    await _pump(tester, fake, const ProcedureHistoryScreen());
    await tester.tap(find.byKey(const ValueKey('procedure_log_menu_log-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fake.deleted, isEmpty);
    expect(find.text('Red Light Therapy'), findsOneWidget);
  });

  testWidgets('edit opens the form pre-filled and updates the same entry', (
    tester,
  ) async {
    final fake = _FakeLogs([
      _log('log-a', 'Red Light Therapy', notes: 'Original'),
      _log('log-b', 'At-Home Chemical Peel'),
    ]);
    await _pump(tester, fake, const ProcedureHistoryScreen());
    await tester.tap(find.byKey(const ValueKey('procedure_log_menu_log-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Procedure Log'), findsOneWidget);
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('1.0mm, 2 passes'), findsOneWidget);
    // A custom product from the log is shown so it can be unselected.
    expect(find.text('My Recovery Balm'), findsOneWidget);

    await tester.enterText(
      find.text('Original'),
      'Mild redness, gone by evening',
    );
    await tester.ensureVisible(find.text('Save Changes'));
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(fake.added, isEmpty);
    expect(fake.updated, hasLength(1));
    final saved = fake.updated.single;
    expect(saved.id, 'log-a');
    expect(saved.notes, 'Mild redness, gone by evening');
    expect(saved.procedureType, 'Red Light Therapy');
    expect(saved.createdAt, DateTime(2026, 10, 1));
    expect(saved.aiFeedback, 'kept');
    expect(saved.productsUsed, ['GHK-Cu', 'My Recovery Balm']);
    // Back on the history list, with both entries.
    expect(find.text('Procedure log updated.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('procedure_log_menu_log-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('procedure_log_menu_log-b')),
      findsOneWidget,
    );
  });

  testWidgets('a custom procedure name is kept when editing', (tester) async {
    final fake = _FakeLogs([_log('log-a', 'Gua Sha Session')]);
    await _pump(
      tester,
      fake,
      AtHomeProcedureLogScreen(existingLog: fake._logs.first),
    );
    expect(find.text('Gua Sha Session'), findsOneWidget);
    await tester.ensureVisible(find.text('Save Changes'));
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(fake.updated.single.procedureType, 'Gua Sha Session');
    expect(fake.updated.single.id, 'log-a');
  });

  testWidgets('history and the edit form fit at 320px', (tester) async {
    final fake = _FakeLogs([
      _log('log-a', 'At-Home Microneedling (SkinPen)'),
      _log('log-b', 'At-Home Chemical Peel'),
    ]);
    await _pump(tester, fake, const ProcedureHistoryScreen(), width: 320);
    expect(tester.takeException(), isNull);
    await _pump(
      tester,
      fake,
      AtHomeProcedureLogScreen(existingLog: fake._logs.first),
      width: 320,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Edit Procedure Log'), findsOneWidget);
  });
}

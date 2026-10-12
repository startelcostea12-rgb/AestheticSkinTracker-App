import 'dart:async';
import 'dart:io';

import 'package:aesthetic_skin_tracker/utils/startup_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('runStartupStep', () {
    test('a step that finishes reports success', () async {
      var ran = false;
      final ok = await runStartupStep('ok', () async => ran = true);
      expect(ok, isTrue);
      expect(ran, isTrue);
    });

    test('a step that throws is skipped instead of stopping startup', () async {
      final ok = await runStartupStep(
        'throws',
        () async => throw StateError('decode failed'),
      );
      expect(ok, isFalse);
    });

    test('a step that never finishes times out', () async {
      final stopwatch = Stopwatch()..start();
      final ok = await runStartupStep(
        'hangs',
        () => Completer<void>().future,
        timeout: const Duration(milliseconds: 50),
      );
      expect(ok, isFalse);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });

  test('main() reaches runApp without an unbounded startup await', () {
    final source = File('lib/main.dart').readAsStringSync();
    final mainStart = source.indexOf('Future<void> main() async {');
    final runAppAt = source.indexOf('runApp(', mainStart);
    expect(mainStart, isNonNegative);
    expect(runAppAt, greaterThan(mainStart));
    final beforeRunApp = source.substring(mainStart, runAppAt);

    // The steps that could hang or throw are all bounded.
    for (final unguarded in const [
      'await Hive.initFlutter()',
      'await ReportService.cleanupLegacyStorage()',
      'await NotificationService()',
    ]) {
      expect(beforeRunApp, isNot(contains(unguarded)), reason: unguarded);
    }
    final warmUpAt = beforeRunApp.indexOf(
      "runStartupStep('scan history warm-up'",
    );
    expect(warmUpAt, isNonNegative);
    final warmUpClosure = beforeRunApp.substring(
      warmUpAt,
      beforeRunApp.indexOf('});', warmUpAt),
    );
    expect(warmUpClosure, contains('await AppPrefs.getScanEntries()'));
    expect(
      beforeRunApp.indexOf('await AppPrefs.getScanEntries()'),
      greaterThan(warmUpAt),
    );
    expect(
      source.substring(source.indexOf('Future<bool> _initializeCrashlytics')),
      contains('Firebase.initializeApp().timeout('),
    );

    // Notifications (and their permission dialog) start after runApp.
    final notificationsAt = source.indexOf(
      "runStartupStep('notifications'",
      mainStart,
    );
    expect(notificationsAt, greaterThan(runAppAt));
  });
}

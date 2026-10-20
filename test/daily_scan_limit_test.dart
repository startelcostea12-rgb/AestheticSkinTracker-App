import 'dart:io';

import 'package:aesthetic_skin_tracker/utils/daily_scan_limit.dart';
import 'package:aesthetic_skin_tracker/utils/premium_access.dart';
import 'package:aesthetic_skin_tracker/utils/upload_gate.dart';
import 'package:aesthetic_skin_tracker/widgets/paywall_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _useScans(int count) async {
  for (var i = 0; i < count; i++) {
    await DailyAiScans.recordScan();
  }
}

/// A button that does what each AI scan entry point does first.
Future<List<String>> _pumpScanButton(WidgetTester tester) async {
  final started = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                if (await showDailyScanLimitIfReached(context)) return;
                started.add('scan');
              },
              child: const Text('Start scan'),
            ),
          ),
        ),
      ),
    ),
  );
  return started;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    PremiumAccess.debugTesterPremiumUnlockOverride = null;
    UploadGate.debugBypassOverride = null;
  });

  group('counting', () {
    test('the free limit is 3 AI scans per day', () {
      expect(kFreeDailyAiScanLimit, 3);
    });

    test('counts per local calendar day and resets the next day', () async {
      final morning = DateTime(2026, 10, 20, 8);
      final evening = DateTime(2026, 10, 20, 22);
      final tomorrow = DateTime(2026, 10, 21, 7);
      await DailyAiScans.recordScan(now: morning);
      await DailyAiScans.recordScan(now: evening);
      expect(await DailyAiScans.usedToday(now: evening), 2);
      expect(await DailyAiScans.usedToday(now: tomorrow), 0);
      await DailyAiScans.recordScan(now: tomorrow);
      expect(await DailyAiScans.usedToday(now: tomorrow), 1);
    });

    test('free: reached at 3, not below', () async {
      await _useScans(2);
      expect(await DailyAiScans.limitReached(), isFalse);
      await _useScans(1);
      expect(await DailyAiScans.limitReached(), isTrue);
    });

    test('still enforced while the upload testing bypass is on', () async {
      UploadGate.debugBypassOverride = true;
      await _useScans(3);
      expect(await DailyAiScans.limitReached(), isTrue);
    });

    test('premium and scan-credit holders are never limited', () async {
      await _useScans(10);
      PremiumAccess.debugTesterPremiumUnlockOverride = true;
      expect(await DailyAiScans.limitReached(), isFalse);
      PremiumAccess.debugTesterPremiumUnlockOverride = false;
      expect(await DailyAiScans.limitReached(), isTrue);
      await UploadGate.setScanCredits(1);
      expect(await DailyAiScans.limitReached(), isFalse);
    });
  });

  group('starting a scan', () {
    testWidgets('free user below the limit can scan; no message', (
      tester,
    ) async {
      await _useScans(2);
      final started = await _pumpScanButton(tester);
      await tester.tap(find.text('Start scan'));
      await tester.pumpAndSettle();
      expect(started, ['scan']);
      expect(
        find.byKey(const ValueKey('daily_scan_limit_dialog')),
        findsNothing,
      );
    });

    testWidgets('free user at the limit cannot start a scan and sees the '
        'upsell, which opens Premium', (tester) async {
      await _useScans(3);
      final started = await _pumpScanButton(tester);
      await tester.tap(find.text('Start scan'));
      await tester.pumpAndSettle();
      expect(started, isEmpty);
      expect(find.text(DailyScanLimitDialog.title), findsOneWidget);
      expect(find.text(DailyScanLimitDialog.message), findsOneWidget);
      expect(DailyScanLimitDialog.message, contains('3 AI scans per day'));
      expect(DailyScanLimitDialog.message, contains('scan again tomorrow'));
      expect(find.text('See Premium'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('daily_scan_limit_premium')));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(started, isEmpty);
    });

    testWidgets('"Not now" closes the message without scanning', (
      tester,
    ) async {
      await _useScans(3);
      final started = await _pumpScanButton(tester);
      await tester.tap(find.text('Start scan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('daily_scan_limit_dialog')),
        findsNothing,
      );
      expect(find.byType(PaywallScreen), findsNothing);
      expect(started, isEmpty);
    });

    testWidgets('premium user at any count scans with no limit message', (
      tester,
    ) async {
      PremiumAccess.debugTesterPremiumUnlockOverride = true;
      await _useScans(25);
      final started = await _pumpScanButton(tester);
      await tester.tap(find.text('Start scan'));
      await tester.pumpAndSettle();
      expect(started, ['scan']);
      expect(
        find.byKey(const ValueKey('daily_scan_limit_dialog')),
        findsNothing,
      );
    });
  });

  test('every AI scan entry point checks the daily limit and every '
      'completed scan is counted', () {
    final source = File(
      'lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart',
    ).readAsStringSync();
    for (final entry in [
      'Future<void> _pickFromCamera() async {',
      'Future<void> _pickAndCrop(ImageSource source, String errorLabel) async {',
      'Future<void> _runAnalysis() async {',
    ]) {
      final start = source.indexOf(entry);
      expect(start, isNonNegative, reason: entry);
      expect(
        source.substring(start, start + 400),
        contains('if (await showDailyScanLimitIfReached(context)) return;'),
        reason: entry,
      );
    }
    expect(
      source,
      contains(
        'await UploadGate.recordCompletedBackendScan();\n'
        '      await DailyAiScans.recordScan();',
      ),
    );
    expect(
      source,
      contains(
        'await FreeLocalScans.recordLocalScan();\n'
        '        await DailyAiScans.recordScan();',
      ),
    );
  });
}

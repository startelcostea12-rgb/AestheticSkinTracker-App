import 'dart:io';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:aesthetic_skin_tracker/utils/free_scan_limit.dart';
import 'package:aesthetic_skin_tracker/utils/premium_access.dart';
import 'package:aesthetic_skin_tracker/utils/upload_gate.dart';
import 'package:aesthetic_skin_tracker/widgets/paywall_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A button that does what every AI scan entry point does first.
Future<List<String>> _pumpScanButton(WidgetTester tester) async {
  final started = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                if (await openPaywallIfFreeScanCapReached(context)) return;
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
    UploadGate.endFreeAiScanUpload();
  });

  group('counting', () {
    test('a free user gets one AI scan', () async {
      expect(kFreeAiScanLimit, 1);
      expect(await FreeAiScans.freeScanAvailable(), isTrue);
      expect(await FreeAiScans.limitReached(), isFalse);
      await FreeAiScans.recordScan();
      expect(await FreeAiScans.used(), 1);
      expect(await FreeAiScans.freeScanAvailable(), isFalse);
      expect(await FreeAiScans.limitReached(), isTrue);
    });

    test('applies while the upload testing bypass is on too', () async {
      UploadGate.debugBypassOverride = true;
      await FreeAiScans.recordScan();
      expect(await FreeAiScans.limitReached(), isTrue);
    });

    test('Premium / Test Premium: never limited and never counted', () async {
      PremiumAccess.debugTesterPremiumUnlockOverride = true;
      for (var i = 0; i < 5; i++) {
        await FreeAiScans.recordScan();
      }
      expect(await FreeAiScans.used(), 0);
      expect(await FreeAiScans.limitReached(), isFalse);
      // Already-used free scan: Premium still is not limited.
      await FreeAiScans.setUsed(1);
      expect(await FreeAiScans.limitReached(), isFalse);
      expect(await resolveScanRoute(), ScanRoute.backend);
    });

    test('a paid scan credit is not limited', () async {
      await FreeAiScans.setUsed(1);
      await UploadGate.setScanCredits(1);
      expect(await FreeAiScans.limitReached(), isFalse);
    });
  });

  group('routing with the upload gate enforced', () {
    setUp(() => UploadGate.debugBypassOverride = false);

    test('the free scan is a full backend scan; then the paywall', () async {
      expect(await resolveScanRoute(), ScanRoute.freeAiScan);
      expect(await UploadGate.canUpload(), isFalse);
      UploadGate.beginFreeAiScanUpload();
      expect(await UploadGate.canUpload(), isTrue);
      UploadGate.endFreeAiScanUpload();
      expect(await UploadGate.canUpload(), isFalse);
      await FreeAiScans.recordScan();
      expect(await resolveScanRoute(), ScanRoute.paywall);
    });
  });

  group('starting a scan', () {
    testWidgets('free user who has not scanned can scan', (tester) async {
      final started = await _pumpScanButton(tester);
      await tester.tap(find.text('Start scan'));
      await tester.pumpAndSettle();
      expect(started, ['scan']);
      expect(find.byType(PaywallScreen), findsNothing);
    });

    testWidgets('second attempt opens the paywall instead of scanning', (
      tester,
    ) async {
      await FreeAiScans.recordScan();
      final started = await _pumpScanButton(tester);
      await tester.tap(find.text('Start scan'));
      await tester.pumpAndSettle();
      expect(started, isEmpty);
      expect(find.byType(PaywallScreen), findsOneWidget);
    });

    testWidgets('Premium after the free scan keeps scanning', (tester) async {
      await FreeAiScans.recordScan();
      PremiumAccess.debugTesterPremiumUnlockOverride = true;
      final started = await _pumpScanButton(tester);
      await tester.tap(find.text('Start scan'));
      await tester.pumpAndSettle();
      expect(started, ['scan']);
      expect(find.byType(PaywallScreen), findsNothing);
    });
  });

  test('wiring: counted only when an AI scan completes, pass always closed, '
      'and nothing else counts', () {
    final scan = File(
      'lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart',
    ).readAsStringSync();
    expect(
      scan,
      contains(
        'await UploadGate.recordCompletedBackendScan();\n'
        '      await FreeAiScans.recordScan();',
      ),
    );
    expect(
      scan,
      contains(
        'if (scanRoute == ScanRoute.freeAiScan) {\n'
        '        UploadGate.beginFreeAiScanUpload();',
      ),
    );
    expect(
      scan,
      contains('} finally {\n      UploadGate.endFreeAiScanUpload();'),
    );
    // Only the AI scan screen counts scans.
    final counters = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.readAsStringSync().contains('FreeAiScans.recordScan(')) {
        counters.add(file.path.replaceAll(r'\', '/'));
      }
    }
    expect(counters, [
      'lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart',
    ]);
  });
}

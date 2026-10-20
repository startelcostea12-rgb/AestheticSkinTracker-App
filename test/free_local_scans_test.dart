import 'dart:io';
import 'dart:typed_data';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/free_local_scan_results_screen.dart';
import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:aesthetic_skin_tracker/models/ai_scan_frame_exposure.dart';
import 'package:aesthetic_skin_tracker/models/journal_entry.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/premium_access.dart';
import 'package:aesthetic_skin_tracker/utils/recommendation_context.dart';
import 'package:aesthetic_skin_tracker/utils/skin_analysis_service.dart';
import 'package:aesthetic_skin_tracker/utils/upload_gate.dart';
import 'package:aesthetic_skin_tracker/widgets/from_your_logs.dart';
import 'package:aesthetic_skin_tracker/widgets/paywall_screen.dart';
import 'package:aesthetic_skin_tracker/widgets/scan_based_recommendations_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

({MockClient client, List<http.Request> requests}) _recordingClient() {
  final requests = <http.Request>[];
  final client = MockClient((request) async {
    requests.add(request);
    return http.Response('{"status":"success"}', 200);
  });
  return (client: client, requests: requests);
}

Future<void> _upload(MockClient client) =>
    SkinAnalysisService.uploadSingleImageFile(
      image: XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'scan.jpg'),
      uri: Uri.parse('https://example.test/api/skin/analyze-single'),
      allowBackend: true,
      httpClient: client,
    );

FreeLocalScanSummary _summary({int scansUsed = 1}) =>
    FreeLocalScanSummary.fromLocal(
      faceFound: true,
      faceCoverage: 0.42,
      symmetryScore: 0.91,
      hasBaseline: true,
      lightingCheck: (
        wouldLock: false,
        missingExposure: false,
        currentBrightnessValue: 3.1,
        baselineBrightnessValue: 3.0,
      ),
      frames: const [
        AiScanFrameExposure(iso: 64, brightnessValue: 3.05),
        AiScanFrameExposure(iso: 80, brightnessValue: 3.2),
      ],
      scansUsed: scansUsed,
    );

/// Stand-in for one scan attempt on the AI scan screen: the cap check,
/// then the route, then the free local results view.
Future<String> _attemptScan(WidgetTester tester, BuildContext context) async {
  if (await openPaywallIfFreeScanCapReached(context)) return 'paywall';
  final route = await resolveScanRoute();
  if (route == ScanRoute.paywall) return 'paywall';
  if (route == ScanRoute.backend) return 'backend';
  await FreeLocalScans.recordLocalScan();
  final summary = _summary(scansUsed: await FreeLocalScans.used());
  if (!context.mounted) return 'unmounted';
  // ignore: unawaited_futures
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => FreeLocalScanResultsScreen(summary: summary),
    ),
  );
  return 'local';
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => UploadGate.debugBypassOverride = null);

  test('free local scan limit is 3', () {
    expect(kFreeLocalScanLimit, 3);
    expect(FreeLocalScans.usedKey, 'free_local_scans_used');
  });

  group('free user, bypass off', () {
    setUp(() => UploadGate.debugBypassOverride = false);

    testWidgets('3 local scans show the limited view; the 4th opens paywall', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navKey, home: const Scaffold()),
      );
      BuildContext ctx() => navKey.currentContext!;

      Future<void> settle() async {
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      for (var i = 1; i <= 3; i++) {
        final attempt = _attemptScan(tester, ctx());
        await settle();
        expect(await attempt, 'local', reason: 'scan $i');
        expect(find.byType(FreeLocalScanResultsScreen), findsOneWidget);
        expect(find.text('Free scans left: ${3 - i} of 3'), findsOneWidget);
        // A short note only after the last free scan.
        expect(
          find.text(FreeLocalScanResultsScreen.lastFreeScanText),
          i == 3 ? findsOneWidget : findsNothing,
        );
        navKey.currentState!.pop();
        await settle();
      }
      expect(find.byType(FreeLocalScanResultsScreen), findsNothing);
      expect(await FreeLocalScans.used(), 3);
      expect(await FreeLocalScans.capReached(), isTrue);

      final fourth = _attemptScan(tester, ctx());
      await settle();
      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(find.byType(FreeLocalScanResultsScreen), findsNothing);
      navKey.currentState!.pop();
      await settle();
      expect(await fourth, 'paywall');
      expect(await FreeLocalScans.used(), 3);
      expect(await resolveScanRoute(), ScanRoute.paywall);
    });

    test('free scans never grant a backend upload', () async {
      final rec = _recordingClient();
      expect(await resolveScanRoute(), ScanRoute.freeLocal);
      await expectLater(
        _upload(rec.client),
        throwsA(isA<UploadGateBlockedException>()),
      );
      await FreeLocalScans.setUsed(3);
      await expectLater(
        _upload(rec.client),
        throwsA(isA<UploadGateBlockedException>()),
      );
      expect(rec.requests, isEmpty);
    });

    testWidgets('From your logs hides once the cap is reached', (tester) async {
      final block = find.byKey(const ValueKey('recommendations_context_notes'));

      Future<RecommendationContextInputs> productInputs() async =>
          RecommendationContextInputs(
            productJournals: {
              'Glow Serum': [
                JournalEntry(
                  date: DateTime(2026, 10, 5),
                  title: 'Day 2',
                  content: 'Some stinging',
                ),
              ],
            },
          );
      Widget productSection() => MaterialApp(
        home: Scaffold(
          body: FromYourLogsSection(
            key: UniqueKey(),
            relevantTo: const ['Glow Serum'],
            loadInputs: productInputs,
          ),
        ),
      );
      await tester.pumpWidget(productSection());
      await tester.pumpAndSettle();
      expect(block, findsOneWidget);

      await FreeLocalScans.setUsed(3);
      await tester.pumpWidget(productSection());
      await tester.pumpAndSettle();
      expect(block, findsNothing);
    });
  });

  group('no local cap with upload access', () {
    setUp(() => UploadGate.debugBypassOverride = false);

    test('subscribed user: backend route and upload, no cap', () async {
      await PremiumAccess.setTestingPremium(true);
      await FreeLocalScans.setUsed(10);
      expect(await FreeLocalScans.capReached(), isFalse);
      expect(await resolveScanRoute(), ScanRoute.backend);
      final rec = _recordingClient();
      await _upload(rec.client);
      expect(rec.requests, hasLength(1));
    });

    test('credited user: backend route and upload, no cap', () async {
      await UploadGate.setScanCredits(2);
      await FreeLocalScans.setUsed(10);
      expect(await FreeLocalScans.capReached(), isFalse);
      expect(await resolveScanRoute(), ScanRoute.backend);
      final rec = _recordingClient();
      await _upload(rec.client);
      expect(rec.requests, hasLength(1));
    });
  });

  test(
    'bypass on: uploads proceed without credits or the free count',
    () async {
      UploadGate.debugBypassOverride = true;
      await FreeLocalScans.setUsed(10);
      expect(await resolveScanRoute(), ScanRoute.backend);
      expect(await FreeLocalScans.capReached(), isFalse);
      final rec = _recordingClient();
      await _upload(rec.client);
      expect(rec.requests, hasLength(1));
      await UploadGate.recordCompletedBackendScan();
      expect(await UploadGate.remainingScanCredits(), 0);
      expect(await FreeLocalScans.used(), 10);
    },
  );

  testWidgets('limited results show only local checks, no metrics', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: FreeLocalScanResultsScreen(summary: _summary())),
    );
    expect(
      find.text(
        'Face found and cropped · full-frame coverage 42% · L/R symmetry 91%',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Not locked: lighting matches your baseline.'),
      findsOneWidget,
    );
    expect(find.text('2 frames · ISO 64–80 · Bv 3.05–3.20'), findsOneWidget);
    expect(find.textContaining('Checked during full analysis'), findsOneWidget);
    expect(find.text(FreeLocalScanResultsScreen.premiumNote), findsOneWidget);
    expect(find.text('Free scans left: 2 of 3'), findsOneWidget);
    for (final word in [
      'Redness',
      'Texture',
      'Pigment',
      'Improved',
      'Worsened',
      'Stable',
    ]) {
      expect(find.textContaining(word), findsNothing, reason: word);
    }
  });

  testWidgets('home card hides From your logs when told to', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Widget card(bool show) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ScanBasedRecommendationsCard(
            latest: const SkinMetrics(redness: 7.5, darkSpots: 7.0),
            baseline: const SkinMetrics(redness: 6.0, darkSpots: 7.0),
            journalEntries: [
              JournalEntry(
                date: DateTime(2026, 10, 5),
                title: 'Reaction',
                content: 'Cheeks hot',
              ),
            ],
            showContextNotes: show,
          ),
        ),
      ),
    );
    final block = find.byKey(const ValueKey('recommendations_context_notes'));
    await tester.pumpWidget(card(true));
    expect(block, findsOneWidget);
    await tester.pumpWidget(card(false));
    expect(block, findsNothing);
  });

  test('every AI scan entry point checks the free cap first', () {
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
        source.substring(start, start + 300),
        contains('if (await openPaywallIfFreeScanCapReached(context)) return;'),
        reason: entry,
      );
    }
    final route = source.indexOf('final scanRoute = await resolveScanRoute();');
    final freeBranch = source.substring(
      route,
      source.indexOf('analyzeBackendFrames(', route),
    );
    expect(freeBranch, contains('await FreeLocalScans.recordLocalScan();'));
    expect(
      freeBranch,
      contains('FreeLocalScanResultsScreen(summary: summary)'),
    );
    expect(freeBranch, isNot(contains('AppPrefs.addScan')));
  });
}

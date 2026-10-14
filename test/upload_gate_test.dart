import 'dart:io';
import 'dart:typed_data';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:aesthetic_skin_tracker/screens/product_photo_routine_screen.dart';
import 'package:aesthetic_skin_tracker/utils/premium_access.dart';
import 'package:aesthetic_skin_tracker/utils/skin_analysis_service.dart';
import 'package:aesthetic_skin_tracker/utils/upload_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

XFile _photo() =>
    XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'scan.jpg');

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
      image: _photo(),
      uri: Uri.parse('https://example.test/api/skin/analyze-single'),
      allowBackend: true,
      httpClient: client,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => UploadGate.debugBypassOverride = null);

  test('bypass is on by default for testing', () {
    expect(kUploadGateBypass, isTrue);
    expect(UploadGate.bypassEnabled, isTrue);
  });

  group('bypass off', () {
    setUp(() => UploadGate.debugBypassOverride = false);

    test('free user with no credit cannot upload', () async {
      expect(await UploadGate.canUpload(), isFalse);
      final rec = _recordingClient();
      await expectLater(
        _upload(rec.client),
        throwsA(isA<UploadGateBlockedException>()),
      );
      await expectLater(
        SkinAnalysisService.analyzeImageFromBytes(
          Uint8List.fromList([1, 2, 3]),
          allowBackend: true,
        ),
        throwsA(isA<UploadGateBlockedException>()),
      );
      expect(
        await SkinAnalysisService.analyzeBodySilhouette(
          bytes: Uint8List.fromList([1, 2, 3]),
          allowBackend: true,
          httpClient: rec.client,
        ),
        isNull,
      );
      expect(rec.requests, isEmpty);
    });

    test('subscription allows upload and uses no credit', () async {
      await PremiumAccess.setTestingPremium(true);
      final rec = _recordingClient();
      await _upload(rec.client);
      expect(rec.requests, hasLength(1));
      await UploadGate.recordCompletedBackendScan();
      expect(await UploadGate.remainingScanCredits(), 0);
    });

    test(
      'a scan credit allows upload and one completed scan uses it',
      () async {
        await UploadGate.setScanCredits(1);
        final rec = _recordingClient();
        await _upload(rec.client);
        expect(rec.requests, hasLength(1));
        await UploadGate.recordCompletedBackendScan();
        expect(await UploadGate.remainingScanCredits(), 0);
        await expectLater(
          _upload(rec.client),
          throwsA(isA<UploadGateBlockedException>()),
        );
        expect(rec.requests, hasLength(1));
      },
    );

    testWidgets('product photo is not sent; typed list still works', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: ProductPhotoRoutineScreen(pickPhoto: (_) async => _photo()),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('product_photo_pick_button')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Reading product photos needs Premium or a scan credit. Type your '
          'products below instead.',
        ),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('product_list_field')),
        'Gentle Cleanser',
      );
      await tester.tap(find.byKey(const ValueKey('product_list_build_button')));
      await tester.pumpAndSettle();
      expect(find.text('1. Gentle Cleanser'), findsOneWidget);
    });
  });

  group('bypass on', () {
    setUp(() => UploadGate.debugBypassOverride = true);

    test('free user upload proceeds and uses no credit', () async {
      final rec = _recordingClient();
      await _upload(rec.client);
      expect(rec.requests, hasLength(1));
      await UploadGate.recordCompletedBackendScan();
      expect(await UploadGate.remainingScanCredits(), 0);
    });
  });

  group('local calibrated path works either way', () {
    for (final bypass in [true, false]) {
      test('pre-upload light check is unaffected (bypass=$bypass)', () {
        UploadGate.debugBypassOverride = bypass;
        final check = aiScanPreUploadLightingCheck(
          frameExposure: const [],
          baselinePayload: null,
        );
        expect(check.wouldLock, isFalse);
      });
    }

    test('AI scan gates only after the on-device steps, before upload', () {
      final source = File(
        'lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart',
      ).readAsStringSync();
      final run = source.indexOf('Future<void> _runAnalysis()');
      int at(String needle) => source.indexOf(needle, run);
      final gate = at('final scanRoute = await resolveScanRoute();');
      expect(gate, greaterThan(run));
      expect(at('SkinAnalysisRunner.augment('), lessThan(gate));
      expect(at('AcneRosaceaPhotoAnalyzer.analyze('), lessThan(gate));
      expect(at('aiScanPreUploadLightingCheck('), lessThan(gate));
      expect(at('analyzeBackendFrames('), greaterThan(gate));
      final blocked = source.substring(gate, at('analyzeBackendFrames('));
      expect(blocked, contains('const PaywallScreen()'));
      expect(blocked, contains('FreeLocalScanResultsScreen('));
      expect(blocked, contains('return;'));
      expect(blocked, isNot(contains('SkinAnalysisService')));
    });

    test('on-device analysis and log notes never call the upload check', () {
      for (final path in [
        'lib/services/skin_analysis_service.dart',
        'lib/utils/recommendation_context.dart',
        'lib/widgets/from_your_logs.dart',
      ]) {
        expect(
          File(path).readAsStringSync(),
          isNot(contains('ensureCanUpload')),
          reason: path,
        );
      }
    });
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:aesthetic_skin_tracker/utils/backend_config.dart';
import 'package:aesthetic_skin_tracker/utils/skin_analysis_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('Track Procedure backend privacy gate', () {
    test('face analysis denies backend access by default', () async {
      await expectLater(
        SkinAnalysisService.analyzeImageFromBytes(
          Uint8List.fromList([10, 20, 30]),
        ),
        throwsA(
          predicate(
            (error) => error.toString().contains(
              'Backend access is disabled for this flow',
            ),
          ),
        ),
      );
    });
  });

  group('SkinAnalysisService.analyzeBodySilhouette request construction', () {
    test(
      'Track Procedure body analysis is blocked by default and makes zero HTTP requests',
      () async {
        var requestCount = 0;
        final mockClient = MockClient((request) async {
          requestCount += 1;
          return http.Response(jsonEncode({'status': 'success'}), 200);
        });

        final result = await SkinAnalysisService.analyzeBodySilhouette(
          bytes: Uint8List.fromList([10, 20, 30]),
          httpClient: mockClient,
        );

        expect(result, isNull);
        expect(requestCount, 0);
      },
    );

    test(
      'posts to the body-silhouette endpoint with a correctly base64-encoded '
      'image only when the consent-based AI flow explicitly allows backend access',
      () async {
        http.Request? captured;
        final mockClient = MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'status': 'success',
              'result': {'normalized_area_index': 1.0},
              'trend_deltas': {},
              'trend_status': {},
            }),
            200,
          );
        });

        final bytes = Uint8List.fromList([10, 20, 30, 40, 250]);
        final result = await SkinAnalysisService.analyzeBodySilhouette(
          bytes: bytes,
          captureMode: 'mirror',
          captureQuality: 'normal',
          baselineResult: {
            'normalized_area_index': 5.5,
            'scale_reference_pixels': 100.0,
          },
          baselineCaptureMode: 'assisted',
          currentConsistentScanCount: 2,
          baselineConsistentScanCount: 1,
          sourceImageWidth: 1600,
          sourceImageHeight: 1200,
          baselineSourceImageWidth: 1000,
          baselineSourceImageHeight: 750,
          allowBackend: true,
          httpClient: mockClient,
        );

        expect(result, isNotNull);
        expect(result!['status'], 'success');

        expect(captured, isNotNull);
        expect(captured!.method, 'POST');
        expect(captured!.url, BackendConfig.analyzeBodySilhouetteUri);
        expect(captured!.url.path, '/api/body/analyze-silhouette');
        expect(
          captured!.headers['Content-Type'],
          'application/json',
        );

        final decodedBody =
            jsonDecode(captured!.body) as Map<String, dynamic>;
        expect(decodedBody['imageBytes'], base64Encode(bytes));
        // Round-trip check: the base64 field actually decodes back to the
        // original bytes, not just some non-empty string.
        expect(base64Decode(decodedBody['imageBytes']), bytes);
        expect(decodedBody['captureMode'], 'mirror');
        expect(decodedBody['captureQuality'], 'normal');
        expect(decodedBody['baselineCaptureMode'], 'assisted');
        expect(decodedBody['currentConsistentScanCount'], 2);
        expect(decodedBody['baselineConsistentScanCount'], 1);
        expect(decodedBody['sourceImageWidth'], 1600);
        expect(decodedBody['sourceImageHeight'], 1200);
        expect(decodedBody['baselineSourceImageWidth'], 1000);
        expect(decodedBody['baselineSourceImageHeight'], 750);
        expect(decodedBody['baselineResult'], {
          'normalized_area_index': 5.5,
          'scale_reference_pixels': 100.0,
        });
      },
    );

    test(
      'omits optional fields from the JSON body entirely when not provided, '
      'rather than sending them as null',
      () async {
        http.Request? captured;
        final mockClient = MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode({'status': 'success'}), 200);
        });

        await SkinAnalysisService.analyzeBodySilhouette(
          bytes: Uint8List.fromList([1, 2, 3]),
          allowBackend: true,
          httpClient: mockClient,
        );

        final decodedBody =
            jsonDecode(captured!.body) as Map<String, dynamic>;
        expect(decodedBody.containsKey('imageBytes'), isTrue);
        expect(decodedBody.containsKey('captureMode'), isFalse);
        expect(decodedBody.containsKey('captureQuality'), isFalse);
        expect(decodedBody.containsKey('baselineResult'), isFalse);
        expect(decodedBody.containsKey('baselineCaptureMode'), isFalse);
      },
    );

    test('a non-200 response is treated as failure and returns null', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal error', 500);
      });

      final result = await SkinAnalysisService.analyzeBodySilhouette(
        bytes: Uint8List.fromList([1, 2, 3]),
        allowBackend: true,
        httpClient: mockClient,
      );

      expect(result, isNull);
    });

    test(
      'a thrown exception from the client (e.g. connection refused) is '
      'caught and returns null rather than propagating',
      () async {
        final mockClient = MockClient((request) async {
          throw Exception('Connection refused');
        });

        final result = await SkinAnalysisService.analyzeBodySilhouette(
          bytes: Uint8List.fromList([1, 2, 3]),
          allowBackend: true,
          httpClient: mockClient,
        );

        expect(result, isNull);
      },
    );
  });
}

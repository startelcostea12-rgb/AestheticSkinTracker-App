import 'dart:typed_data';

import 'package:aesthetic_skin_tracker/utils/backend_config.dart';
import 'package:aesthetic_skin_tracker/utils/skin_analysis_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Covers the fix for backend requests silently missing the X-API-Key
/// header: BackendConfig never read AI_BACKEND_API_KEY at all, so every
/// call site sent no auth header regardless of what was configured,
/// causing the deployed (authenticated) backend to 401 every app request
/// while curl with the same key worked fine.
///
/// apiKeyHeadersFor is a pure extraction of BackendConfig.apiKeyHeaders'
/// logic that takes the key as a parameter instead of reading the
/// compile-time BackendConfig.apiKey constant -- apiKey's real value is
/// fixed for the whole test process by whatever --dart-define was passed
/// (none, in a normal `flutter test` run, so it's always empty here), so
/// this is the only way to exercise both the present-key and absent-key
/// cases directly.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('apiKeyHeadersFor (pure logic shared by every backend call site)', () {
    test('a non-empty key produces a present X-API-Key header', () {
      final headers = apiKeyHeadersFor('super-secret-key');
      expect(headers, {'X-API-Key': 'super-secret-key'});
      expect(headers.containsKey('X-API-Key'), isTrue);
    });

    test(
      'an empty key omits the header entirely, not an empty-valued one',
      () {
        final headers = apiKeyHeadersFor('');
        expect(headers, isEmpty);
        expect(headers.containsKey('X-API-Key'), isFalse);
      },
    );
  });

  group('BackendConfig.apiKeyHeaders', () {
    test(
      'matches apiKeyHeadersFor(apiKey) -- the getter is not a separate, '
      'independently-drifting implementation',
      () {
        expect(
          BackendConfig.apiKeyHeaders,
          apiKeyHeadersFor(BackendConfig.apiKey),
        );
      },
    );

    test(
      'in a normal test run (no --dart-define=AI_BACKEND_API_KEY), the key '
      'is empty and the header map is empty',
      () {
        expect(BackendConfig.apiKey, isEmpty);
        expect(BackendConfig.apiKeyHeaders, isEmpty);
      },
    );
  });

  group(
    'a real call site (SkinAnalysisService.analyzeBodySilhouette) is wired '
    'to send whatever BackendConfig.apiKeyHeaders currently resolves to',
    () {
      test(
        'the constructed request carries exactly the headers '
        'apiKeyHeaders declares -- present when set, absent when not',
        () async {
          http.Request? captured;
          final mockClient = MockClient((request) async {
            captured = request;
            return http.Response('{"status":"success"}', 200);
          });

          await SkinAnalysisService.analyzeBodySilhouette(
            bytes: Uint8List.fromList([1, 2, 3]),
            allowBackend: true,
            httpClient: mockClient,
          );

          expect(captured, isNotNull);
          for (final entry in BackendConfig.apiKeyHeaders.entries) {
            expect(captured!.headers[entry.key], entry.value);
          }
          // In a normal test run BackendConfig.apiKey is empty, so this
          // is the concrete assertion that exercises today: no X-API-Key
          // header was attached at all.
          if (BackendConfig.apiKey.isEmpty) {
            expect(captured!.headers.containsKey('X-API-Key'), isFalse);
          } else {
            expect(
              captured!.headers['X-API-Key'],
              BackendConfig.apiKey,
            );
          }
        },
      );
    },
  );

  test('multipart request sends only stored baseline formula versions', () async {
    http.Request? captured;
    final mockClient = MockClient((request) async {
      captured = request;
      return http.Response('{"status":"success"}', 200);
    });

    await SkinAnalysisService.uploadSingleImageFile(
      image: XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'scan.jpg'),
      uri: Uri.parse('https://example.test/api/skin/analyze-single'),
      baselineFormulaVersions: const {'glabellar_wrinkle_depth': 2},
      allowBackend: true,
      httpClient: mockClient,
    );

    expect(captured, isNotNull);
    expect(captured!.body, contains('name="baseline_formula_versions"'));
    expect(captured!.body, contains('{"glabellar_wrinkle_depth":2}'));
    expect(captured!.body, isNot(contains('texture_smoothness')));
  });
}

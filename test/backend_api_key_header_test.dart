import 'dart:typed_data';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:aesthetic_skin_tracker/services/skin_history_repository.dart';
import 'package:aesthetic_skin_tracker/utils/ai_scan_data_csv_exporter.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('original source dimensions match multipart, saved scan and CSV', () async {
    final fields = buildAiSkinAnalysisBackendFields(
      focusArea: 'Full face',
      sourceImageWidth: 4032,
      sourceImageHeight: 3024,
      baselineSourceImageWidth: 4000,
      baselineSourceImageHeight: 3000,
    );
    final metadata = aiScanSourceResolutionMetadata(fields);
    http.Request? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response('{"status":"success"}', 200);
    });
    await SkinAnalysisService.uploadSingleImageFile(
      image: XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'crop.jpg'),
      uri: Uri.parse('https://example.test/api/skin/analyze-single'),
      fields: fields,
      allowBackend: true,
      httpClient: client,
    );
    for (final entry in metadata.entries) {
      expect(captured!.body,
          contains('name="${entry.key}"\r\n\r\n${entry.value}\r\n'));
    }
    final saved = await SkinHistoryRepository.instance.saveScan(
      metrics: const {'localized_redness': 20},
      sourceImageWidth: metadata['source_image_width'],
      sourceImageHeight: metadata['source_image_height'],
      rawPayload: metadata,
    );
    final scans = await SkinHistoryRepository.instance.getAllScans();
    final reloaded = scans.singleWhere((scan) => scan.id == saved.id);
    expect(reloaded.sourceImageWidth, 4032);
    expect(reloaded.sourceImageHeight, 3024);
    for (final entry in metadata.entries) {
      expect(reloaded.rawPayload![entry.key], entry.value);
    }
    final csv = AiScanDataCsvExporter.format(
      [reloaded], registryBaselineScanIds: const {},
    ).split('\r\n');
    final headers = csv.first.split(',');
    final cells = csv[1].split(',');
    final row = {for (var index = 0; index < headers.length; index++)
      headers[index]: cells[index]};
    for (final entry in metadata.entries) {
      final column = switch (entry.key) {
        'source_image_width' => 'image_width',
        'source_image_height' => 'image_height',
        _ => entry.key,
      };
      expect(row[column], fields[entry.key]);
    }
    final nextFields = buildAiSkinAnalysisBackendFields(
      focusArea: 'Full face',
      baselineSourceImageWidth: reloaded.sourceImageWidth,
      baselineSourceImageHeight: reloaded.sourceImageHeight,
    );
    expect(nextFields['baseline_source_image_width'], '4032');
    expect(nextFields['baseline_source_image_height'], '3024');
  });

  test('missing source dimensions stay absent in upload, storage and CSV', () async {
    final fields = buildAiSkinAnalysisBackendFields(focusArea: 'Full face');
    final metadata = aiScanSourceResolutionMetadata(fields);
    expect(metadata, isEmpty);
    expect(fields.keys.where((key) => key.contains('image_width') || key.contains('image_height')), isEmpty);
    final saved = await SkinHistoryRepository.instance.saveScan(
      metrics: const {'localized_redness': 20}, rawPayload: metadata,
    );
    final scans = await SkinHistoryRepository.instance.getAllScans();
    final reloaded = scans.singleWhere((scan) => scan.id == saved.id);
    expect(reloaded.sourceImageWidth, isNull);
    expect(reloaded.sourceImageHeight, isNull);
    final csv = AiScanDataCsvExporter.format(
      [reloaded], registryBaselineScanIds: const {},
    ).split('\r\n');
    final headers = csv.first.split(',');
    final cells = csv[1].split(',');
    for (final column in ['image_width', 'image_height', 'baseline_source_image_width', 'baseline_source_image_height']) {
      expect(cells[headers.indexOf(column)], isEmpty);
    }
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

import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'backend_config.dart';
import 'app_prefs.dart';
import '../models/skin_profile.dart';

class ImageCaptureStateWarning implements Exception {
  ImageCaptureStateWarning(this.message);

  final String message;

  @override
  String toString() => message;
}

class BeforeAfterCaptureState extends ChangeNotifier {
  XFile? imageFile;

  void setImageFile(XFile file) {
    imageFile = file;
    notifyListeners();
  }

  void clear() {
    imageFile = null;
    notifyListeners();
  }

  void validateReadyForUpload() {
    final image = imageFile;

    if (image == null) {
      throw ImageCaptureStateWarning(
        'Upload blocked: imageFile is required before upload.',
      );
    }
  }
}

class SkinAnalysisService {
  // Backend host is centralized in BackendConfig.
  static const Duration _requestTimeout = Duration(seconds: 60);

  static const String _backendUnavailableMessage =
      'Please start the AestheticSkin backend to enable AI analysis.';

  static void _ensureBackendAllowed(bool allowBackend) {
    if (!allowBackend) {
      throw Exception(
        'Backend access is disabled for this flow. '
        'Only the AI Skin Analysis screen may send photos to the backend.',
      );
    }
  }

  static Map<String, dynamic> _normalizeResponsePayload(
    Map<String, dynamic> responseData,
  ) {
    final safeProductsRaw = responseData['recommended_products'];
    final safetyProfileRaw = responseData['safety_profile'];

    final safeProducts = safeProductsRaw is List
        ? List<dynamic>.from(safeProductsRaw)
        : <dynamic>[];

    final safetyProfile = safetyProfileRaw is Map
        ? Map<String, dynamic>.from(safetyProfileRaw)
        : <String, dynamic>{};

    final normalized = Map<String, dynamic>.from(responseData)
      ..['recommended_products'] = safeProducts
      ..['safety_profile'] = safetyProfile;

    debugPrint('Active Safety Profile: $safetyProfile');
    debugPrint('Safe Product Suggestions Count: ${safeProducts.length}');

    return normalized;
  }

  static Future<dynamic> analyzeImageFromBytes(
    Uint8List bytes, {
    String? filename,
    Map<String, dynamic>? baselineMetricMatrix,
    Map<String, String>? baselineExtractionPaths,
    bool allowBackend = false,
  }) async {
    _ensureBackendAllowed(allowBackend);
    final uri = BackendConfig.analyzeSkinUri;

    debugPrint('[SkinAnalysisService] POST $uri');

    try {
      final response = await http.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'imageBytes': base64Encode(bytes),
          if (filename != null) 'filename': filename,
          if (baselineMetricMatrix != null && baselineMetricMatrix.isNotEmpty)
            'baselineMetricMatrix': baselineMetricMatrix,
          if (baselineExtractionPaths != null && baselineExtractionPaths.isNotEmpty)
            'baselineExtractionPaths': baselineExtractionPaths,
        }),
      ).timeout(_requestTimeout);

      debugPrint(
        '[SkinAnalysisService] Backend status: ${response.statusCode}',
      );

      final responseText = response.body;
      if (response.statusCode != 200) {
        throw Exception(
          'Backend returned HTTP ${response.statusCode}: $responseText',
        );
      }

      if (responseText.trim().isEmpty) return null;
      final decoded = jsonDecode(responseText);
      if (decoded is Map<String, dynamic>) {
        return _normalizeResponsePayload(decoded);
      }
      if (decoded is Map) {
        return _normalizeResponsePayload(Map<String, dynamic>.from(decoded));
      }
      return decoded;
    } on TimeoutException {
      throw Exception(
        'Skin analysis timed out after 60 seconds. Please check your connection and try again.',
      );
    } catch (e) {
      debugPrint('❌ [SkinAnalysisService] Request failed: $e');
      final lower = e.toString().toLowerCase();
      if (lower.contains('failed to fetch') ||
          lower.contains('clientexception') ||
          lower.contains('socketexception') ||
          lower.contains('connection refused')) {
        throw Exception(_backendUnavailableMessage);
      }
      rethrow;
    }
  }

  /// Submits a body-procedure capture to `/api/body/analyze-silhouette`.
  ///
  /// Unlike [analyzeImageFromBytes]/[uploadSingleImageFile] (user-initiated
  /// "Deep Analysis" actions that should surface a failure), this runs as
  /// part of the automatic post-capture save for body-region scans — a
  /// network hiccup here shouldn't block saving the scan itself, so this
  /// returns null on any failure (bad status, timeout, no connection)
  /// instead of throwing. Not gated by [_ensureBackendAllowed]: that gate
  /// protects the user-initiated face "Deep Analysis" flow specifically;
  /// this is a distinct, deliberate submission path with no equivalent
  /// consent-gated screen of its own.
  /// [httpClient] is injectable purely for tests — production callers omit
  /// it and get the default top-level [http.post]. This lets a test supply
  /// a `package:http/testing.dart` `MockClient` to capture and assert on
  /// the exact request built (headers, URL, JSON body) without reaching a
  /// real backend.
  static Future<Map<String, dynamic>?> analyzeBodySilhouette({
    required Uint8List bytes,
    String? captureMode,
    String? captureQuality,
    Map<String, dynamic>? baselineResult,
    String? baselineCaptureMode,
    String? baselineCaptureQuality,
    int? currentConsistentScanCount,
    int? baselineConsistentScanCount,
    int? sourceImageWidth,
    int? sourceImageHeight,
    int? baselineSourceImageWidth,
    int? baselineSourceImageHeight,
    http.Client? httpClient,
  }) async {
    final uri = BackendConfig.analyzeBodySilhouetteUri;
    debugPrint('[SkinAnalysisService] POST $uri (body silhouette)');
    try {
      final poster = httpClient?.post ?? http.post;
      final response = await poster(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'imageBytes': base64Encode(bytes),
          if (captureMode != null) 'captureMode': captureMode,
          if (captureQuality != null) 'captureQuality': captureQuality,
          if (baselineResult != null && baselineResult.isNotEmpty)
            'baselineResult': baselineResult,
          if (baselineCaptureMode != null)
            'baselineCaptureMode': baselineCaptureMode,
          if (baselineCaptureQuality != null)
            'baselineCaptureQuality': baselineCaptureQuality,
          if (currentConsistentScanCount != null)
            'currentConsistentScanCount': currentConsistentScanCount,
          if (baselineConsistentScanCount != null)
            'baselineConsistentScanCount': baselineConsistentScanCount,
          if (sourceImageWidth != null) 'sourceImageWidth': sourceImageWidth,
          if (sourceImageHeight != null) 'sourceImageHeight': sourceImageHeight,
          if (baselineSourceImageWidth != null)
            'baselineSourceImageWidth': baselineSourceImageWidth,
          if (baselineSourceImageHeight != null)
            'baselineSourceImageHeight': baselineSourceImageHeight,
        }),
      ).timeout(_requestTimeout);

      if (response.statusCode != 200) {
        debugPrint(
          '[SkinAnalysisService] Body silhouette backend HTTP ${response.statusCode}: ${response.body}',
        );
        return null;
      }
      if (response.body.trim().isEmpty) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } catch (e) {
      debugPrint('[SkinAnalysisService] Body silhouette request failed: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>> uploadSingleImageFile({
    required XFile? image,
    Uri? uri,
    Map<String, String> fields = const {},
    Map<String, dynamic>? baselineMetricMatrix,
    Map<String, String>? baselineExtractionPaths,
    bool allowBackend = false,
  }) async {
    _ensureBackendAllowed(allowBackend);
    if (image == null) {
      throw ImageCaptureStateWarning(
        'Upload blocked: image cannot be null.',
      );
    }

    final targetUri = uri ?? BackendConfig.analyzeSingleSkinUri;
    debugPrint('[SkinAnalysisService] POST $targetUri (multipart)');

    final mergedFields = Map<String, String>.from(fields);
    final inferredSafety = await _inferSafetySignalFields();
    if (!_hasNonEmptyField(mergedFields, 'rosacea_score')) {
      mergedFields['rosacea_score'] = inferredSafety['rosacea_score']!;
    }
    if (!_hasNonEmptyField(mergedFields, 'sensitivity_score')) {
      mergedFields['sensitivity_score'] = inferredSafety['sensitivity_score']!;
    }
    if (!_hasNonEmptyField(mergedFields, 'compromised_barrier')) {
      mergedFields['compromised_barrier'] = inferredSafety['compromised_barrier']!;
    }
    if (baselineMetricMatrix != null &&
        baselineMetricMatrix.isNotEmpty &&
        !_hasNonEmptyField(mergedFields, 'baseline_metric_matrix')) {
      mergedFields['baseline_metric_matrix'] = jsonEncode(baselineMetricMatrix);
    }
    if (baselineExtractionPaths != null &&
        baselineExtractionPaths.isNotEmpty &&
        !_hasNonEmptyField(mergedFields, 'baseline_extraction_paths')) {
      mergedFields['baseline_extraction_paths'] = jsonEncode(
        baselineExtractionPaths,
      );
    }

    final request = http.MultipartRequest('POST', targetUri)
      ..fields.addAll(mergedFields);

    request.files.add(
      http.MultipartFile.fromBytes(
        'image',
        await image.readAsBytes(),
        filename: _filenameFromPath(image.path),
      ),
    );

    try {
      final streamed = await request.send().timeout(_requestTimeout);
      final response = await http.Response.fromStream(streamed);

      debugPrint('[SkinAnalysisService] Multipart status: ${response.statusCode}');

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Single-image upload failed with HTTP ${response.statusCode}: ${response.body}',
        );
      }

      final body = response.body.trim();
      if (body.isEmpty) {
        return <String, dynamic>{};
      }

      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return _normalizeResponsePayload(decoded);
      }
      if (decoded is Map) {
        return _normalizeResponsePayload(Map<String, dynamic>.from(decoded));
      }

      throw Exception('Unexpected response format from single-image analysis.');
    } on TimeoutException {
      throw Exception(
        'Skin analysis upload timed out after 60 seconds. Please check your connection and try again.',
      );
    } catch (e) {
      debugPrint('❌ [SkinAnalysisService] Multipart request failed: $e');
      final lower = e.toString().toLowerCase();
      if (lower.contains('failed to fetch') ||
          lower.contains('clientexception') ||
          lower.contains('socketexception') ||
          lower.contains('connection refused')) {
        throw Exception(_backendUnavailableMessage);
      }
      rethrow;
    }
  }

  static String _filenameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    if (index == -1 || index == normalized.length - 1) {
      return 'upload.jpg';
    }
    return normalized.substring(index + 1);
  }

  static bool _hasNonEmptyField(Map<String, String> fields, String key) {
    final value = fields[key];
    return value != null && value.trim().isNotEmpty;
  }

  static Future<double?> _latestTrackerMetric(String metricKey) async {
    final logs = await AppPrefs.getAcneRosaceaLogsForMetric(metricKey);
    if (logs.isEmpty) return null;
    return logs.first.value.toDouble().clamp(0.0, 10.0);
  }

  static double _sensitivityFromProfile(SensitivityLevel level) {
    switch (level) {
      case SensitivityLevel.low:
        return 2.5;
      case SensitivityLevel.moderate:
        return 4.5;
      case SensitivityLevel.high:
        return 7.0;
      case SensitivityLevel.veryHigh:
        return 8.5;
    }
  }

  static bool _containsAnyToken(String text, List<String> tokens) {
    final lower = text.toLowerCase();
    for (final token in tokens) {
      if (lower.contains(token)) return true;
    }
    return false;
  }

  static Future<Map<String, String>> _inferSafetySignalFields() async {
    const defaultRosacea = 2.5;
    const defaultSensitivity = 4.5;

    final profile = await AppPrefs.getSkinProfileOrNull();
    final recentRosacea = await _latestTrackerMetric('rosaceaSeverity');
    final recentSensitivity = await _latestTrackerMetric('skinSensitivity');

    final concernText = [
      ...?profile?.mainConcerns,
      ...?profile?.goals,
      profile?.notes ?? '',
    ].join(' ').toLowerCase();

    final rosaceaConcern = _containsAnyToken(concernText, const [
      'rosacea',
      'flushing',
      'persistent redness',
      'redness',
      'vascular',
    ]);
    final barrierConcern = _containsAnyToken(concernText, const [
      'barrier',
      'compromised',
      'irritation',
      'reactive',
      'stinging',
      'burning',
      'sensitive',
    ]);

    final profileSensitivity = profile == null
        ? null
        : _sensitivityFromProfile(profile.sensitivityLevel);

    final rosacea = (recentRosacea ?? (rosaceaConcern ? 6.0 : null) ??
            defaultRosacea)
        .clamp(0.0, 10.0);
    final sensitivity =
        (recentSensitivity ?? profileSensitivity ?? defaultSensitivity)
            .clamp(0.0, 10.0);

    final compromisedBarrier =
        barrierConcern || sensitivity >= 7.0 || (profile?.skinType == SkinType.sensitive);

    return {
      'rosacea_score': rosacea.toStringAsFixed(1),
      'sensitivity_score': sensitivity.toStringAsFixed(1),
      'compromised_barrier': compromisedBarrier ? 'true' : 'false',
    };
  }
}

/// Central defaults for backend services used by AI Coach and skin analysis.
///
/// Override at runtime with:
/// --dart-define=AI_BACKEND_BASE_URL=http://127.0.0.1:8000
/// --dart-define=AI_BACKEND_API_KEY=<the same value as the deployed
/// backend's BACKEND_API_KEY env var>
class BackendConfig {
  const BackendConfig._();

  static const String _configuredBaseUrl = String.fromEnvironment(
    'AI_BACKEND_BASE_URL',
  );
  static const String _defaultBaseUrl = 'http://127.0.0.1:8000';

  /// The shared-secret key the deployed backend's X-API-Key auth
  /// middleware requires on every /api/ request (see main.py's
  /// _require_api_key). Empty when not supplied via --dart-define, which
  /// is the normal case for local development against an unauthenticated
  /// backend -- callers must omit the X-API-Key header entirely in that
  /// case rather than sending an empty one, since the backend's own
  /// hmac.compare_digest check treats a present-but-empty header the same
  /// as any other wrong key.
  static const String apiKey = String.fromEnvironment('AI_BACKEND_API_KEY');

  /// {'X-API-Key': apiKey} when [apiKey] is non-empty, otherwise an empty
  /// map -- spread this into a request's headers (or, for a multipart
  /// request, addAll it to `request.headers`) so local development against
  /// an unauthenticated backend never sends an empty header.
  static Map<String, String> get apiKeyHeaders => apiKeyHeadersFor(apiKey);

  static const String aiCoachEndpoint = '/api/coach';
  static const String analyzeSkinEndpoint = '/api/analyze-skin';
  static const String analyzeSingleSkinEndpoint = '/api/skin/analyze-single';
  static const String analyzeBodySilhouetteEndpoint =
      '/api/body/analyze-silhouette';

  static String get baseUrl {
    final configured = _configuredBaseUrl.trim();
    final active = configured.isEmpty ? _defaultBaseUrl : configured;
    return _withoutTrailingSlash(active);
  }

  static Uri buildUri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalizedPath');
  }

  static Uri get aiCoachUri => buildUri(aiCoachEndpoint);

  static Uri get analyzeSkinUri => buildUri(analyzeSkinEndpoint);

  static Uri get analyzeSingleSkinUri => buildUri(analyzeSingleSkinEndpoint);

  static Uri get analyzeBodySilhouetteUri =>
      buildUri(analyzeBodySilhouetteEndpoint);

  static String _withoutTrailingSlash(String value) {
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }
}

/// Pure extraction of [BackendConfig.apiKeyHeaders]'s logic, taking the key
/// as a plain parameter instead of reading the compile-time
/// [BackendConfig.apiKey] constant, so both the present-key and absent-key
/// cases are directly unit-testable in the same test run (apiKey's actual
/// value is fixed for the whole process by whatever --dart-define was
/// passed, if any, when the test binary was built).
Map<String, String> apiKeyHeadersFor(String key) =>
    key.isEmpty ? const {} : {'X-API-Key': key};

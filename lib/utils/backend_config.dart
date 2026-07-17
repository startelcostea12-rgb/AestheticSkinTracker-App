/// Central defaults for backend services used by AI Coach and skin analysis.
///
/// Override at runtime with:
/// --dart-define=AI_BACKEND_BASE_URL=http://127.0.0.1:8000
class BackendConfig {
  const BackendConfig._();

  static const String _configuredBaseUrl = String.fromEnvironment(
    'AI_BACKEND_BASE_URL',
  );
  static const String _defaultBaseUrl = 'http://127.0.0.1:8000';

  static const String aiCoachEndpoint = '/api/coach';
  static const String analyzeSkinEndpoint = '/api/analyze-skin';
  static const String analyzeSingleSkinEndpoint = '/api/skin/analyze-single';

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

  static String _withoutTrailingSlash(String value) {
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }
}

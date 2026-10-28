import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';

import '../utils/backend_config.dart';
import '../utils/upload_gate.dart';

/// Small LLM gateway for AI coaching features.
///
/// The app does not call Gemini directly or bundle API keys. It calls the local
/// Node backend, which owns provider keys, retries, fallback, and logging.
class AiService {
  const AiService({http.Client? client}) : _client = client;

  final http.Client? _client;

  static const String _backendUnavailableMessage =
      'Please start the AestheticSkin backend to enable AI analysis.';

  bool get isConfigured => BackendConfig.baseUrl.trim().isNotEmpty;

  /// Keeps the existing streaming UI contract, but returns the backend response
  /// as one buffered chunk because the backend endpoint is non-streaming.
  Future<Stream<String>> streamCoachResponse({
    required String systemPrompt,
    required String userPrompt,
    AiRetryCallback? onRetry,
    bool allowBackend = false,
  }) async {
    final text = await completeCoachResponse(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      allowBackend: allowBackend,
    );
    return Stream<String>.value(text);
  }

  Future<String> completeCoachResponse({
    required String systemPrompt,
    required String userPrompt,
    bool allowBackend = false,
  }) async {
    if (!allowBackend) {
      throw AiLlmException(
        'Backend access is disabled for this flow. Only the AI Skincare Coach may use the backend.',
      );
    }

    final client = _client ?? http.Client();
    final shouldCloseClient = _client == null;

    try {
      final uri = BackendConfig.aiCoachUri;
      debugPrint('[AiService] POST $uri');

      final response = await client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              ...BackendConfig.apiKeyHeaders,
            },
            body: jsonEncode({
              'systemPrompt': systemPrompt,
              'userPrompt': userPrompt,
            }),
          )
          .timeout(const Duration(seconds: 60));

      final body = _decodeJsonObject(response.body);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message =
            BackendConfig.errorMessageFromBody(body) ??
            'Backend AI coach request failed with HTTP ${response.statusCode}.';
        throw AiLlmException(message);
      }

      final text = _stringField(body, 'text');
      if (text == null || text.trim().isEmpty) {
        throw const AiLlmException(
          'Backend AI coach returned an empty response.',
        );
      }

      _log(
        'Backend AI coach completed. '
        'modelUsed=${_stringField(body, 'modelUsed') ?? 'unknown'}, '
        'attempts=${body['attempts'] ?? 'unknown'}.',
      );

      return text.trim();
    } on TimeoutException catch (_) {
      throw const AiLlmException(
        'Backend AI coach timed out. Confirm the local backend is running on port 8000.',
      );
    } on AiLlmException {
      rethrow;
    } catch (error) {
      final errorText = error.toString().toLowerCase();
      if (errorText.contains('failed to fetch') ||
          errorText.contains('clientexception') ||
          errorText.contains('socketexception') ||
          errorText.contains('connection refused')) {
        throw const AiLlmException(_backendUnavailableMessage);
      }
      throw AiLlmException(
        'Could not reach backend AI coach at ${BackendConfig.aiCoachUri}. '
        'Use ${BackendConfig.baseUrl} or override AI_BACKEND_BASE_URL as needed. '
        'Details: $error',
      );
    } finally {
      if (shouldCloseClient) client.close();
    }
  }

  /// Analyze skin photo using Google Gemini Vision with multimodal input.
  ///
  /// Uses Gemini 3.8 Flash with vision capabilities for skin analysis.
  /// Requires GEMINI_API_KEY environment variable.
  Future<String> analyzeSkinWithImage({
    required File imageFile,
    required String systemPrompt,
    required String userPrompt,
  }) async {
    // Sends a photo off the device: paid gate first.
    await UploadGate.ensureCanUpload();
    const apiKey = String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

    if (apiKey.isEmpty) {
      throw const AiLlmConfigurationException(
        'GEMINI_API_KEY not configured. Add --dart-define=GEMINI_API_KEY=your_key',
      );
    }

    try {
      _log('Analyzing skin photo with Gemini Vision...');

      final model = GenerativeModel(
        model: 'gemini-3.8-flash',
        apiKey: apiKey,
        systemInstruction: Content.text(systemPrompt),
      );

      // Read image bytes
      final imageBytes = await imageFile.readAsBytes();

      // Create multimodal content (text + image)
      final prompt = [
        Content.multi([
          TextPart(userPrompt),
          DataPart('image/jpeg', imageBytes),
        ]),
      ];

      final response = await model.generateContent(prompt);
      final text = response.text;

      if (text == null || text.trim().isEmpty) {
        throw const AiLlmException('Gemini Vision returned an empty response.');
      }

      _log('Gemini Vision analysis completed successfully.');

      // Clean up any JSON blocks, code fences, or structured data
      final cleanedText = _cleanupVisionResponse(text.trim());
      return cleanedText;
    } on GenerativeAIException catch (e) {
      _log('Gemini Vision error: ${e.message}');
      throw AiLlmException('Gemini Vision analysis failed: ${e.message}');
    } catch (error) {
      _log('Unexpected error during vision analysis: $error');
      throw AiLlmException('Failed to analyze image: $error');
    }
  }

  /// Removes JSON blocks, code fences, and structured data from vision responses.
  /// Uses greedy multi-line patterns to catch large nested objects.
  String _cleanupVisionResponse(String text) {
    // 1. Remove fenced JSON / code blocks (greedy to catch large blocks)
    text = text.replaceAll(
      RegExp(r'```json[\s\S]*?```', caseSensitive: false),
      '',
    );
    text = text.replaceAll(RegExp(r'```[\s\S]*?```', caseSensitive: false), '');

    // 2. Remove skinMetricScores key and everything after it (greedy)
    text = text.replaceAll(
      RegExp(r'"?skinMetricScores"?\s*[:{][\s\S]*', caseSensitive: false),
      '',
    );

    // 3. Remove entire JSON objects iteratively (handles nesting)
    for (int i = 0; i < 4; i++) {
      text = text.replaceAll(RegExp(r'\{[^{}]*\}', caseSensitive: false), '');
    }

    // 4. Remove stray quoted-key: value lines (JSON field remnants)
    text = text.replaceAll(
      RegExp(r'^\s*"[\w]+"\s*:\s*.*$', caseSensitive: false, multiLine: true),
      '',
    );

    // 5. Remove backtick remnants
    text = text.replaceAll('`', '');

    // 6. Clean up excess blank lines
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  Map<String, Object?> _decodeJsonObject(String rawBody) {
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, Object?>) return decoded;
      if (decoded is Map) return decoded.cast<String, Object?>();
    } catch (_) {
      // Fall through to return a body-shaped error object.
    }
    return {'error': rawBody};
  }

  String? _stringField(Map<String, Object?> body, String key) {
    final value = body[key];
    return value is String ? value : null;
  }

  void _log(String message) {
    print('[AiService] $message');
    developer.log(message, name: 'AiService');
  }
}

typedef AiRetryCallback = void Function(AiRetryInfo info);

class AiRetryInfo {
  final String modelName;
  final int attempt;
  final Duration delay;
  final String reason;
  final bool isFallback;

  const AiRetryInfo({
    required this.modelName,
    required this.attempt,
    required this.delay,
    required this.reason,
    required this.isFallback,
  });
}

/// Backward-compatible alias for earlier AI coach integrations.
class AiLlmService extends AiService {
  const AiLlmService() : super();
}

class AiLlmConfigurationException implements Exception {
  final String message;
  const AiLlmConfigurationException(this.message);

  @override
  String toString() => 'AiLlmConfigurationException: $message';
}

class AiLlmException implements Exception {
  final String message;
  const AiLlmException(this.message);

  @override
  String toString() => 'AiLlmException: $message';
}

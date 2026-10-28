import 'dart:convert';
import 'dart:io';

import 'package:aesthetic_skin_tracker/services/ai_llm_service.dart';
import 'package:aesthetic_skin_tracker/utils/backend_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Call the coach endpoint that exists": the backend only serves
/// POST /api/ai-coach. Every coach client must use it (no /api/coach
/// fallback), must read the server's FastAPI `detail` error field as well as
/// `error`, and must never send a geminiApiKey in the request body.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('coach endpoint constant', () {
    test('aiCoachEndpoint is /api/ai-coach', () {
      expect(BackendConfig.aiCoachEndpoint, '/api/ai-coach');
    });

    test('aiCoachUri path is /api/ai-coach', () {
      expect(BackendConfig.aiCoachUri.path, endsWith('/api/ai-coach'));
      expect(BackendConfig.aiCoachUri.path, isNot(endsWith('/api/coach')));
    });
  });

  group('repo-wide: no /api/coach fallback or client Gemini key remains', () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    test('lib/ has dart files to scan', () {
      expect(dartFiles, isNotEmpty);
    });

    test("no lib/ file references the '/api/coach' path", () {
      final offenders = <String>[
        for (final file in dartFiles)
          if (RegExp(r'/api/coach\b').hasMatch(file.readAsStringSync()))
            file.path,
      ];
      expect(offenders, isEmpty);
    });

    test('no lib/ file sends a geminiApiKey request field', () {
      final offenders = <String>[
        for (final file in dartFiles)
          if (file.readAsStringSync().contains('geminiApiKey')) file.path,
      ];
      expect(offenders, isEmpty);
    });

    test('premium_recovery_service tries only the single coach endpoint', () {
      final source = File('lib/utils/premium_recovery_service.dart')
          .readAsStringSync();
      expect(source, contains('<Uri>[BackendConfig.aiCoachUri]'));
      expect(source, isNot(contains("buildUri('/api/ai-coach')")));
    });
  });

  group('BackendConfig.errorMessageFromBody', () {
    test('reads the app error field', () {
      expect(BackendConfig.errorMessageFromBody({'error': 'boom'}), 'boom');
    });

    test('reads the FastAPI detail string', () {
      expect(
        BackendConfig.errorMessageFromBody({'detail': 'Empty request body.'}),
        'Empty request body.',
      );
    });

    test('error wins over detail when both are present', () {
      expect(
        BackendConfig.errorMessageFromBody({'error': 'a', 'detail': 'b'}),
        'a',
      );
    });

    test('joins FastAPI validation entries from a detail list', () {
      expect(
        BackendConfig.errorMessageFromBody({
          'detail': [
            {'msg': 'field required'},
            {'msg': 'bad value'},
          ],
        }),
        'field required; bad value',
      );
    });

    test('returns null when neither field is usable', () {
      expect(BackendConfig.errorMessageFromBody(null), isNull);
      expect(BackendConfig.errorMessageFromBody(<String, dynamic>{}), isNull);
      expect(BackendConfig.errorMessageFromBody({'detail': ''}), isNull);
    });
  });

  group('AiService coach request', () {
    test('posts to /api/ai-coach without any geminiApiKey', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'text': 'hello', 'modelUsed': 'm', 'attempts': 1}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final text = await AiService(client: client).completeCoachResponse(
        systemPrompt: 'sys',
        userPrompt: 'user',
        allowBackend: true,
      );

      expect(text, 'hello');
      expect(captured, isNotNull);
      expect(captured!.url.path, endsWith('/api/ai-coach'));
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['systemPrompt'], 'sys');
      expect(body['userPrompt'], 'user');
      expect(body.containsKey('geminiApiKey'), isFalse);
      expect(captured!.body, isNot(contains('geminiApiKey')));
    });

    test('surfaces the server detail message on an HTTP error', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': 'Either systemPrompt or userPrompt data is required.',
          }),
          400,
          headers: {'content-type': 'application/json'},
        );
      });

      expect(
        () => AiService(client: client).completeCoachResponse(
          systemPrompt: '',
          userPrompt: '',
          allowBackend: true,
        ),
        throwsA(
          isA<AiLlmException>().having(
            (e) => e.message,
            'message',
            'Either systemPrompt or userPrompt data is required.',
          ),
        ),
      );
    });

    test('still surfaces an error field when the server sends one', () async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode({'error': 'upstream down'}), 502);
      });

      expect(
        () => AiService(client: client).completeCoachResponse(
          systemPrompt: 's',
          userPrompt: 'u',
          allowBackend: true,
        ),
        throwsA(
          isA<AiLlmException>().having(
            (e) => e.message,
            'message',
            'upstream down',
          ),
        ),
      );
    });
  });
}

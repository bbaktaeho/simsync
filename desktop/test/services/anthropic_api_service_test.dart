import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simsync/services/anthropic_api_service.dart';

http.Response _msg(String text, {String stopReason = 'end_turn'}) {
  return http.Response(
    jsonEncode({
      'content': [
        {'type': 'text', 'text': text},
      ],
      'stop_reason': stopReason,
    }),
    200,
  );
}

void main() {
  group('AnthropicApiService.summarizeWeek', () {
    test('posts to the messages endpoint with auth headers and parses text',
        () async {
      late http.Request captured;
      final service = AnthropicApiService(
        client: MockClient((request) async {
          captured = request;
          return _msg('  weekly summary  ');
        }),
      );

      final result = await service.summarizeWeek(
        apiKey: 'sk-ant-test',
        instruction: 'Summarize the week',
        notesContext: '# 2026-06-15\nDid stuff',
      );

      expect(result, 'weekly summary'); // trimmed
      expect(captured.url.toString(), AnthropicApiService.messagesEndpoint);
      expect(captured.headers['x-api-key'], 'sk-ant-test');
      expect(captured.headers['anthropic-version'], '2023-06-01');

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], 'claude-sonnet-4-6'); // default fallback
      expect(body['system'], 'Summarize the week');
      // No effort passed → no output_config in the request.
      expect(body.containsKey('output_config'), isFalse);
      expect((body['messages'] as List).first['content'], '# 2026-06-15\nDid stuff');
    });

    test('uses the configured model', () async {
      late http.Request captured;
      final service = AnthropicApiService(
        client: MockClient((request) async {
          captured = request;
          return _msg('ok');
        }),
      );

      await service.summarizeWeek(
        apiKey: 'sk-ant-test',
        instruction: 'go',
        notesContext: 'notes',
        model: 'claude-sonnet-4-6',
      );

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], 'claude-sonnet-4-6');
    });

    test('sends output_config.effort when an effort is given', () async {
      late http.Request captured;
      final service = AnthropicApiService(
        client: MockClient((request) async {
          captured = request;
          return _msg('ok');
        }),
      );

      await service.summarizeWeek(
        apiKey: 'sk-ant',
        instruction: 'go',
        notesContext: 'notes',
        model: 'claude-sonnet-4-6',
        effort: 'low',
      );

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['output_config'], {'effort': 'low'});
    });

    test('omits output_config when no effort is given (e.g. Haiku)', () async {
      late http.Request captured;
      final service = AnthropicApiService(
        client: MockClient((request) async {
          captured = request;
          return _msg('ok');
        }),
      );

      await service.summarizeWeek(
        apiKey: 'sk-ant',
        instruction: 'go',
        notesContext: 'notes',
        model: 'claude-haiku-4-5',
      );

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body.containsKey('output_config'), isFalse);
    });

    test('throws a friendly error on 401', () async {
      final service = AnthropicApiService(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'error': {'type': 'authentication_error', 'message': 'bad key'}
            }),
            401,
          );
        }),
      );

      await expectLater(
        service.summarizeWeek(
          apiKey: 'sk-ant-bad',
          instruction: 'x',
          notesContext: 'y',
        ),
        throwsA(isA<AnthropicApiException>()
            .having((e) => e.message, 'message', contains('401'))),
      );
    });

    test('throws when the api key is empty (no request made)', () async {
      final service = AnthropicApiService(
        client: MockClient((request) async {
          fail('no request should be made without an api key');
        }),
      );

      await expectLater(
        service.summarizeWeek(apiKey: '  ', instruction: 'x', notesContext: 'y'),
        throwsA(isA<AnthropicApiException>()),
      );
    });

    test('throws when there are no notes to summarize', () async {
      final service = AnthropicApiService(
        client: MockClient((request) async {
          fail('no request should be made without notes');
        }),
      );

      await expectLater(
        service.summarizeWeek(apiKey: 'sk-ant', instruction: 'x', notesContext: '  '),
        throwsA(isA<AnthropicApiException>()),
      );
    });

    test('throws on a refusal stop reason', () async {
      final service = AnthropicApiService(
        client: MockClient((request) async {
          return _msg('', stopReason: 'refusal');
        }),
      );

      await expectLater(
        service.summarizeWeek(apiKey: 'sk-ant', instruction: 'x', notesContext: 'y'),
        throwsA(isA<AnthropicApiException>()),
      );
    });

    test('throws on empty content', () async {
      final service = AnthropicApiService(
        client: MockClient((request) async {
          return http.Response(jsonEncode({'content': [], 'stop_reason': 'end_turn'}), 200);
        }),
      );

      await expectLater(
        service.summarizeWeek(apiKey: 'sk-ant', instruction: 'x', notesContext: 'y'),
        throwsA(isA<AnthropicApiException>()),
      );
    });

    test('retries with the default model when the configured model is unknown',
        () async {
      final models = <String>[];
      final service = AnthropicApiService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          models.add(body['model'] as String);
          if (models.length == 1) {
            return http.Response(
              jsonEncode({
                'type': 'error',
                'error': {
                  'type': 'not_found_error',
                  'message': 'model: bogus-model',
                },
              }),
              404,
            );
          }
          return _msg('ok after fallback');
        }),
      );

      final fallbacks = <List<String>>[];
      final result = await service.summarizeWeek(
        apiKey: 'sk-ant',
        instruction: 'go',
        notesContext: 'notes',
        model: 'bogus-model',
        onModelFallback: (requested, used) => fallbacks.add([requested, used]),
      );

      expect(result, 'ok after fallback');
      // First the configured (bad) model, then the default fallback.
      expect(models, ['bogus-model', AnthropicApiService.defaultModel]);
      // The caller is told exactly once which model was swapped in.
      expect(fallbacks, [
        ['bogus-model', AnthropicApiService.defaultModel]
      ]);
    });

    test('does not fire onModelFallback when the first attempt succeeds',
        () async {
      var fallbackCalls = 0;
      final service = AnthropicApiService(
        client: MockClient((request) async => _msg('ok')),
      );

      await service.summarizeWeek(
        apiKey: 'sk-ant',
        instruction: 'go',
        notesContext: 'notes',
        model: 'claude-opus-4-8',
        onModelFallback: (_, _) => fallbackCalls++,
      );

      expect(fallbackCalls, 0);
    });

    test('does not retry when the unknown model is already the default',
        () async {
      var calls = 0;
      final service = AnthropicApiService(
        client: MockClient((request) async {
          calls++;
          return http.Response(
            jsonEncode({
              'error': {'type': 'not_found_error', 'message': 'model: x'},
            }),
            404,
          );
        }),
      );

      await expectLater(
        service.summarizeWeek(
          apiKey: 'sk-ant',
          instruction: 'go',
          notesContext: 'notes',
          model: AnthropicApiService.defaultModel,
        ),
        throwsA(isA<AnthropicApiException>()),
      );
      expect(calls, 1); // no fallback loop
    });

    test('a non-model error (401) is not retried', () async {
      var calls = 0;
      final service = AnthropicApiService(
        client: MockClient((request) async {
          calls++;
          return http.Response(
            jsonEncode({
              'error': {'type': 'authentication_error', 'message': 'bad key'},
            }),
            401,
          );
        }),
      );

      await expectLater(
        service.summarizeWeek(
          apiKey: 'sk-ant',
          instruction: 'x',
          notesContext: 'y',
          model: 'claude-opus-4-8',
        ),
        throwsA(isA<AnthropicApiException>()),
      );
      expect(calls, 1);
    });
  });

  group('AnthropicApiService.validateKey', () {
    test('true when GET /v1/models returns 200', () async {
      final service = AnthropicApiService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.toString(), AnthropicApiService.modelsEndpoint);
          return http.Response(jsonEncode({'data': []}), 200);
        }),
      );
      expect(await service.validateKey(apiKey: 'sk-ant-test'), isTrue);
    });

    test('false on 401', () async {
      final service = AnthropicApiService(
        client: MockClient((request) async => http.Response('', 401)),
      );
      expect(await service.validateKey(apiKey: 'sk-ant-bad'), isFalse);
    });

    test('false when the key is empty', () async {
      final service = AnthropicApiService(
        client: MockClient((request) async {
          fail('no request for an empty key');
        }),
      );
      expect(await service.validateKey(apiKey: ''), isFalse);
    });
  });
}

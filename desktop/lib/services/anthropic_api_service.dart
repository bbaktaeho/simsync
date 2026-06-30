import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Raised when the Anthropic API call fails. [message] is safe to show the user.
class AnthropicApiException implements Exception {
  AnthropicApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Calls the Anthropic Messages API directly over HTTPS (the "integrate your own
/// app" path — an API key from console.anthropic.com, billed pay-as-you-go).
///
/// This avoids the Claude Code CLI entirely, so it works from a GUI app launched
/// by Finder where the shell PATH is unavailable. Flutter has no official
/// Anthropic SDK, so this uses raw HTTP per the documented Messages API shape.
class AnthropicApiService {
  AnthropicApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String messagesEndpoint = 'https://api.anthropic.com/v1/messages';
  static const String modelsEndpoint = 'https://api.anthropic.com/v1/models';
  static const String apiVersion = '2023-06-01';

  /// Default model when a caller passes none (a fallback — callers normally pass
  /// an explicit model). Sonnet is balanced; Opus is overkill for summarization.
  static const String defaultModel = 'claude-sonnet-4-6';

  static const Duration summaryTimeout = Duration(seconds: 120);
  static const Duration validateTimeout = Duration(seconds: 20);
  static const int maxContextChars = 200000;
  static const int maxOutputTokens = 4096;

  String _resolveModel(String? model) {
    final trimmed = model?.trim() ?? '';
    return trimmed.isEmpty ? defaultModel : trimmed;
  }

  Map<String, String> _headers(String apiKey) => {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': apiVersion,
      };

  /// Generates the weekly summary. The instruction becomes the system prompt and
  /// the week's notes become the user message. Throws [AnthropicApiException]
  /// with a user-facing message on any failure.
  Future<String> summarizeWeek({
    required String apiKey,
    required String instruction,
    required String notesContext,
    String? model,
    String? effort,
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw AnthropicApiException(
        'Anthropic API 키가 없습니다. 설정 > Weekly에서 API 키를 입력하세요.',
      );
    }
    final trimmedInstruction = instruction.trim();
    if (trimmedInstruction.isEmpty) {
      throw AnthropicApiException('위클리 지침이 비어 있습니다.');
    }
    if (notesContext.trim().isEmpty) {
      throw AnthropicApiException('이번 주에 요약할 노트가 없습니다.');
    }

    var context = notesContext;
    if (context.length > maxContextChars) {
      context = context.substring(0, maxContextChars);
    }

    final body = jsonEncode({
      'model': _resolveModel(model),
      'max_tokens': maxOutputTokens,
      // Lower reasoning effort = faster/cheaper; summarization needs no deep
      // thinking. Sent only when provided — some models (e.g. Haiku) reject it.
      if (effort != null && effort.isNotEmpty)
        'output_config': {'effort': effort},
      'system': trimmedInstruction,
      'messages': [
        {'role': 'user', 'content': context},
      ],
    });

    final http.Response response;
    try {
      response = await _client
          .post(Uri.parse(messagesEndpoint), headers: _headers(key), body: body)
          .timeout(summaryTimeout);
    } on TimeoutException {
      throw AnthropicApiException(
        'Anthropic API 응답이 시간 초과되었습니다 (${summaryTimeout.inSeconds}s).',
      );
    } catch (e) {
      throw AnthropicApiException('Anthropic API에 연결하지 못했습니다.\n$e');
    }

    if (response.statusCode != 200) {
      throw AnthropicApiException(_friendlyError(response));
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw AnthropicApiException('Anthropic API 응답을 해석하지 못했습니다.');
    }

    if (json['stop_reason'] == 'refusal') {
      throw AnthropicApiException('Claude가 안전 정책상 요청을 거부했습니다.');
    }

    final content = json['content'];
    if (content is! List) {
      throw AnthropicApiException('Anthropic API 응답에 내용이 없습니다.');
    }

    final buffer = StringBuffer();
    for (final block in content) {
      if (block is Map && block['type'] == 'text' && block['text'] is String) {
        buffer.write(block['text']);
      }
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) {
      throw AnthropicApiException('Anthropic API가 빈 응답을 반환했습니다.');
    }
    return text;
  }

  /// Validates the API key with a free `GET /v1/models` call (no token cost).
  /// Returns true on 200, false on 401/403 or any error.
  Future<bool> validateKey({required String apiKey}) async {
    final key = apiKey.trim();
    if (key.isEmpty) return false;
    try {
      final response = await _client
          .get(Uri.parse(modelsEndpoint), headers: _headers(key))
          .timeout(validateTimeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  String _friendlyError(http.Response response) {
    var detail = response.body;
    try {
      final json = jsonDecode(response.body);
      if (json is Map &&
          json['error'] is Map &&
          json['error']['message'] is String) {
        detail = json['error']['message'] as String;
      }
    } catch (_) {
      // keep raw body
    }
    switch (response.statusCode) {
      case 401:
        return 'Anthropic API 인증 실패 (401). API 키가 올바른지 확인하세요.';
      case 403:
        return 'Anthropic API 권한 오류 (403). 키 권한 또는 결제 설정을 확인하세요.';
      case 429:
        return 'Anthropic API 사용량 한도 초과 (429). 잠시 후 다시 시도하세요.';
      case 400:
        return 'Anthropic API 요청 오류 (400).\n$detail';
      default:
        return 'Anthropic API 오류 (${response.statusCode}).\n$detail';
    }
  }
}

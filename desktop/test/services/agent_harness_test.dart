import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simsync/services/agent_harness.dart';
import 'package:simsync/storage/github/github_api_client.dart';

GitHubApiClient _client(MockClient mock) =>
    GitHubApiClient(token: 't', owner: 'o', repo: 'r', httpClient: mock);

http.Response _branchResponse() => http.Response(
      jsonEncode({
        'commit': {
          'sha': 'head',
          'commit': {
            'tree': {'sha': 'base-tree'},
          },
        },
      }),
      200,
    );

void main() {
  test('AGENTS.md가 이미 있으면 아무것도 만들지 않는다', () async {
    var writes = 0;
    final mock = MockClient((request) async {
      if (request.method != 'GET') writes++;
      return http.Response(
        jsonEncode({
          'name': 'AGENTS.md',
          'path': 'AGENTS.md',
          'sha': 's',
          'type': 'file',
        }),
        200,
      );
    });

    final created =
        await ensureAgentHarness(client: _client(mock), branch: 'main');

    expect(created, isFalse);
    expect(writes, 0);
  });

  test('AGENTS.md가 없으면 하네스 전체를 단일 커밋으로 만든다 (symlink 포함)',
      () async {
    Map<String, dynamic>? postedTree;
    final mock = MockClient((request) async {
      final url = request.url.toString();
      if (url.endsWith('/contents/AGENTS.md')) {
        return http.Response('Not Found', 404);
      }
      if (url.endsWith('/branches/main')) return _branchResponse();
      if (url.endsWith('/git/trees')) {
        postedTree = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'sha': 'tree'}), 201);
      }
      if (url.endsWith('/git/commits')) {
        return http.Response(jsonEncode({'sha': 'commit'}), 201);
      }
      if (url.endsWith('/git/refs/heads/main')) {
        return http.Response(jsonEncode({'ref': 'refs/heads/main'}), 200);
      }
      return http.Response('unexpected', 500);
    });

    final created =
        await ensureAgentHarness(client: _client(mock), branch: 'main');

    expect(created, isTrue);
    final entries = (postedTree!['tree'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final byPath = {for (final e in entries) e['path'] as String: e};

    // 라우팅 체인: symlink → AGENTS.md → .agents/README.md → 상세 지침.
    expect(byPath.keys, containsAll(agentHarnessFiles.map((f) => f.path)));
    expect(byPath['CLAUDE.md']!['mode'], '120000');
    expect(byPath['CLAUDE.md']!['content'], 'AGENTS.md');
    expect(byPath['GEMINI.md']!['mode'], '120000');
    expect(byPath['AGENTS.md']!['mode'], '100644');
    expect(byPath['AGENTS.md']!['content'], contains('.agents/README.md'));
    expect(byPath['.agents/README.md']!['content'],
        contains('note-format.md'));
    expect(byPath['.agents/README.md']!['content'],
        contains('guidelines.md'));
  });

  test('존재 확인이 네트워크 오류로 실패하면 생성하지 않는다', () async {
    var commits = 0;
    final mock = MockClient((request) async {
      if (request.url.toString().endsWith('/contents/AGENTS.md')) {
        return http.Response('rate limited', 403);
      }
      commits++;
      return http.Response('unexpected', 500);
    });

    final created =
        await ensureAgentHarness(client: _client(mock), branch: 'main');

    expect(created, isFalse);
    expect(commits, 0);
  });

  test('커밋이 실패해도 조용히 false를 돌려준다 (다음 시작에서 재시도)',
      () async {
    final mock = MockClient((request) async {
      if (request.url.toString().endsWith('/contents/AGENTS.md')) {
        return http.Response('Not Found', 404);
      }
      return http.Response('boom', 500);
    });

    final created =
        await ensureAgentHarness(client: _client(mock), branch: 'main');

    expect(created, isFalse);
  });
}

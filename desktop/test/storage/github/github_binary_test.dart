import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simsync/storage/github/github_api_client.dart';

void main() {
  final bytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 255, 128, 7]);

  GitHubApiClient clientWith(MockClient mock) =>
      GitHubApiClient(token: 't', owner: 'o', repo: 'r', httpClient: mock);

  test('putBinaryFile은 raw bytes를 base64로 보낸다 (utf8 왕복 없음)', () async {
    late Map<String, dynamic> sentBody;
    final mock = MockClient((request) async {
      sentBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
          jsonEncode({'content': {'sha': 'newsha'}}), 201);
    });
    final sha = await clientWith(mock).putBinaryFile(
      path: 'notes/2026-07/19/assets/img.png',
      bytes: bytes,
      message: 'Add image',
    );
    expect(sha, 'newsha');
    expect(sentBody['content'], base64.encode(bytes));
  });

  test('getRawFile은 raw accept 헤더로 bodyBytes를 돌려준다', () async {
    late http.Request captured;
    final mock = MockClient((request) async {
      captured = request;
      return http.Response.bytes(bytes, 200);
    });
    final result =
        await clientWith(mock).getRawFile('notes/2026-07/19/assets/img.png');
    expect(result, bytes);
    expect(captured.headers['Accept'], contains('raw'));
  });

  test('getRawFile 404는 GitHubNotFoundException', () async {
    final mock = MockClient((request) async => http.Response('nf', 404));
    expect(
      () => clientWith(mock).getRawFile('x.png'),
      throwsA(isA<GitHubNotFoundException>()),
    );
  });

  test('putFile(텍스트)은 기존과 동일하게 utf8 base64를 보낸다 (회귀)', () async {
    late Map<String, dynamic> sentBody;
    final mock = MockClient((request) async {
      sentBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'content': {'sha': 's'}}), 200);
    });
    await clientWith(mock)
        .putFile(path: 'a.md', content: '한글 content', message: 'm', sha: 'old');
    expect(sentBody['content'], base64.encode(utf8.encode('한글 content')));
    expect(sentBody['sha'], 'old');
  });
}

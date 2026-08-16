import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simsync_mobile/storage/github/github_sync_engine.dart';

/// 5초 폴링은 모바일에서 데이터·배터리 비용이 그대로 나간다. 조건부 요청이
/// 실제로 나가는지, 304를 "변경 없음"으로 다루는지 못 박는다.
void main() {
  test('두 번째 폴링부터 If-None-Match를 보내고 304면 변경 없음으로 본다', () async {
    var calls = 0;
    final sent = <Map<String, String>>[];
    var changed = 0;

    final client = MockClient((request) async {
      calls++;
      sent.add(request.headers);
      if (calls == 1) {
        return http.Response('[{"sha": "abc"}]', 200,
            headers: {'etag': 'W/"tag1"'});
      }
      return http.Response('', 304);
    });

    final engine = GitHubSyncEngine(
      token: 't',
      owner: 'o',
      repo: 'r',
      httpClient: client,
      onRemoteChanged: () async => changed++,
    );

    await engine.syncNow();
    await engine.syncNow();
    engine.dispose();

    expect(sent[0].containsKey('If-None-Match'), isFalse);
    expect(sent[1]['If-None-Match'], 'W/"tag1"');
    expect(engine.lastCommitSha, 'abc');
    expect(changed, 1, reason: '304에서 변경 콜백이 다시 울리면 안 된다');
  });
}

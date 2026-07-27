import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simsync/services/update_checker.dart';

String _releasesJson(List<Map<String, dynamic>> entries) => jsonEncode(entries);

Map<String, dynamic> _release(String tag,
        {bool draft = false, bool prerelease = true}) =>
    {
      'tag_name': tag,
      'draft': draft,
      'prerelease': prerelease,
      'html_url': 'https://github.com/bbaktaeho/simsync/releases/tag/$tag',
    };

void main() {
  group('isNewerVersion', () {
    test('숫자 자리별로 비교하고 v 접두사를 무시한다', () {
      expect(isNewerVersion('v0.3.2', '0.3.1'), isTrue);
      expect(isNewerVersion('0.4.0', '0.3.9'), isTrue);
      expect(isNewerVersion('1.0.0', '0.9.9'), isTrue);
      expect(isNewerVersion('v0.3.1', '0.3.1'), isFalse);
      expect(isNewerVersion('v0.3.0', '0.3.1'), isFalse);
      // 10 > 9 — 문자열 비교였다면 틀렸을 케이스.
      expect(isNewerVersion('v0.3.10', '0.3.9'), isTrue);
    });

    test('자리수가 달라도 없는 자리는 0으로 본다', () {
      expect(isNewerVersion('v0.4', '0.3.1'), isTrue);
      expect(isNewerVersion('v0.3', '0.3.1'), isFalse);
      expect(isNewerVersion('v0.3.1.1', '0.3.1'), isTrue);
    });

    test('파싱 불가한 값은 업데이트로 보지 않는다', () {
      expect(isNewerVersion('nightly', '0.3.1'), isFalse);
      expect(isNewerVersion('', '0.3.1'), isFalse);
      expect(isNewerVersion('v0.3.2', 'unknown'), isFalse);
    });
  });

  group('latestReleaseFrom', () {
    test('draft를 건너뛰고 첫 유효 릴리즈를 고른다', () {
      final body = _releasesJson([
        _release('v0.9.9', draft: true),
        _release('v0.3.2'),
        _release('v0.3.1'),
      ]);
      final latest = latestReleaseFrom(body);
      expect(latest?.tag, 'v0.3.2');
      expect(latest?.url, contains('releases/tag/v0.3.2'));
    });

    test('빈 목록/잘못된 형식이면 null', () {
      expect(latestReleaseFrom('[]'), isNull);
      expect(latestReleaseFrom('{"message":"Not Found"}'), isNull);
    });
  });

  group('UpdateChecker', () {
    test('더 높은 릴리즈가 있으면 hasUpdate가 켜지고 리스너에 알린다', () async {
      final mock = MockClient((request) async {
        // 모든 릴리즈가 prerelease라 /releases/latest가 아닌 목록을 쓴다.
        expect(request.url.path, contains('/releases'));
        expect(request.url.path, isNot(endsWith('/latest')));
        return http.Response(_releasesJson([_release('v0.3.2')]), 200);
      });
      final checker =
          UpdateChecker(httpClient: mock, currentVersion: '0.3.1');
      var notifications = 0;
      checker.addListener(() => notifications++);

      await checker.checkNow();

      expect(checker.hasUpdate, isTrue);
      expect(checker.availableTag, 'v0.3.2');
      expect(checker.releaseUrl, contains('v0.3.2'));
      expect(notifications, 1);

      // 같은 결과를 다시 받아도 중복 알림은 없다.
      await checker.checkNow();
      expect(notifications, 1);
      checker.dispose();
    });

    test('같은 버전이면 알리지 않는다', () async {
      final mock = MockClient(
          (_) async => http.Response(_releasesJson([_release('v0.3.1')]), 200));
      final checker =
          UpdateChecker(httpClient: mock, currentVersion: '0.3.1');

      await checker.checkNow();

      expect(checker.hasUpdate, isFalse);
      expect(checker.availableTag, isNull);
      checker.dispose();
    });

    test('dismiss하면 같은 버전은 숨고, 더 높은 버전은 다시 뜬다', () async {
      var tag = 'v0.3.2';
      final mock = MockClient(
          (_) async => http.Response(_releasesJson([_release(tag)]), 200));
      final checker =
          UpdateChecker(httpClient: mock, currentVersion: '0.3.1');

      await checker.checkNow();
      expect(checker.hasUpdate, isTrue);

      checker.dismiss();
      expect(checker.hasUpdate, isFalse);
      await checker.checkNow(); // 같은 태그를 다시 받아도 숨은 상태 유지
      expect(checker.hasUpdate, isFalse);

      tag = 'v0.4.0';
      await checker.checkNow();
      expect(checker.hasUpdate, isTrue);
      expect(checker.availableTag, 'v0.4.0');
      checker.dispose();
    });

    test('네트워크/API 실패는 조용히 넘긴다', () async {
      final failing = MockClient((_) async => http.Response('rate limit', 403));
      final checker =
          UpdateChecker(httpClient: failing, currentVersion: '0.3.1');

      await checker.checkNow();

      expect(checker.hasUpdate, isFalse);
      checker.dispose();

      final throwing =
          MockClient((_) async => throw const SocketException('offline'));
      final offline =
          UpdateChecker(httpClient: throwing, currentVersion: '0.3.1');
      await offline.checkNow();
      expect(offline.hasUpdate, isFalse);
      offline.dispose();
    });
  });

  // 앱 버전은 릴리즈 태그와 같아야 한다 (업데이트 감지의 기준값).
  // pubspec과 어긋나면 여기서 잡는다.
  test('appVersion이 pubspec.yaml의 version과 일치한다', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*([0-9.]+)', multiLine: true).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml에서 version을 찾지 못했다');
    expect(appVersion, match!.group(1));
  });
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 이 앱의 버전. **릴리즈 태그(`vX.Y.Z`)의 숫자 부분과 항상 같게 유지한다** —
/// 업데이트 감지가 이 값과 최신 태그를 비교하기 때문이다.
/// `pubspec.yaml`의 version과 일치해야 하며, 어긋나면
/// `test/services/update_checker_test.dart`가 실패한다.
const String appVersion = '0.3.3';

/// 릴리즈 목록 조회 URL. 모든 릴리즈가 prerelease라 `/releases/latest`는 404를
/// 낸다 — 목록에서 최신(생성 역순 첫 항목)을 직접 고른다.
const String _releasesUrl =
    'https://api.github.com/repos/bbaktaeho/simsync/releases?per_page=5';

/// `v0.3.1` / `0.3.1` 을 [0,3,1] 로 파싱한다. 숫자가 아닌 접미사(`-beta` 등)는
/// 버린다. 파싱 실패 시 null.
List<int>? parseVersion(String raw) {
  final trimmed = raw.trim().replaceFirst(RegExp(r'^[vV]'), '');
  if (trimmed.isEmpty) return null;
  final parts = trimmed.split('.');
  final numbers = <int>[];
  for (final part in parts) {
    final digits = RegExp(r'^\d+').firstMatch(part)?.group(0);
    if (digits == null) break;
    numbers.add(int.parse(digits));
  }
  return numbers.isEmpty ? null : numbers;
}

/// [candidate]가 [current]보다 높은 버전이면 true. 자리수가 달라도
/// (`0.4` vs `0.3.1`) 없는 자리는 0으로 보고 비교한다. 파싱 불가면 false —
/// 알 수 없는 형식 때문에 업데이트 배너를 잘못 띄우지 않는다.
bool isNewerVersion(String candidate, String current) {
  final a = parseVersion(candidate);
  final b = parseVersion(current);
  if (a == null || b == null) return false;
  final length = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// GitHub 릴리즈 목록 JSON에서 최신 릴리즈(draft 제외)의 태그와 페이지 URL을
/// 고른다. 없으면 null. 응답은 생성 역순이라 첫 유효 항목이 최신이다.
({String tag, String url})? latestReleaseFrom(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! List) return null;
  for (final entry in decoded) {
    if (entry is! Map) continue;
    if (entry['draft'] == true) continue;
    final tag = entry['tag_name'];
    if (tag is! String || tag.isEmpty) continue;
    final url = entry['html_url'];
    return (tag: tag, url: url is String ? url : '');
  }
  return null;
}

/// GitHub 릴리즈를 주기적으로 확인해 새 버전이 있으면 알린다.
///
/// 공개 저장소라 인증 없이 조회한다 (미인증 한도 60회/시간, 10분 주기면
/// 6회/시간이라 여유롭다). 실패는 조용히 넘기고 다음 주기에 재시도한다 —
/// 업데이트 확인은 부가 기능이라 앱 동작을 방해하면 안 된다.
class UpdateChecker extends ChangeNotifier {
  UpdateChecker({
    http.Client? httpClient,
    this.currentVersion = appVersion,
    this.interval = const Duration(minutes: 10),
  }) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  final String currentVersion;
  final Duration interval;

  Timer? _timer;
  bool _checking = false;

  /// 현재 버전보다 높은 릴리즈의 태그 (`v0.3.2`). 없으면 null.
  String? _availableTag;

  /// 해당 릴리즈 페이지 URL.
  String? _releaseUrl;

  /// 사용자가 X로 닫은 태그. 같은 버전은 다시 띄우지 않는다 (더 높은 버전이
  /// 나오면 다시 뜬다). 앱을 재시작하면 초기화된다 — 설정 파일까지 쓸 만큼
  /// 중요한 상태가 아니다.
  String? _dismissedTag;

  String? get availableTag => _availableTag;
  String? get releaseUrl => _releaseUrl;

  /// 배너를 보여줘야 하는지.
  bool get hasUpdate => _availableTag != null && _availableTag != _dismissedTag;

  /// 즉시 한 번 확인하고, 이후 [interval] 주기로 반복한다.
  void start() {
    if (_timer != null) return;
    unawaited(checkNow());
    _timer = Timer.periodic(interval, (_) => unawaited(checkNow()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 릴리즈를 한 번 확인한다. 새 버전이면 [hasUpdate]가 true가 되고 리스너에
  /// 알린다.
  Future<void> checkNow() async {
    if (_checking) return;
    _checking = true;
    try {
      final response = await _httpClient.get(
        Uri.parse(_releasesUrl),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      );
      if (response.statusCode != 200) return;
      final latest = latestReleaseFrom(response.body);
      if (latest == null) return;
      if (!isNewerVersion(latest.tag, currentVersion)) return;
      if (_availableTag == latest.tag) return;
      _availableTag = latest.tag;
      _releaseUrl = latest.url;
      notifyListeners();
    } catch (_) {
      // 오프라인/rate limit/파싱 실패: 다음 주기에 다시 시도한다.
    } finally {
      _checking = false;
    }
  }

  /// 현재 알림을 닫는다. 더 높은 버전이 나오면 다시 뜬다.
  void dismiss() {
    if (_availableTag == null) return;
    _dismissedTag = _availableTag;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    _httpClient.close();
    super.dispose();
  }
}

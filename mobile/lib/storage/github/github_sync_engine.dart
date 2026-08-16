import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../sync_engine.dart';

/// Polling-based sync engine that detects remote changes by comparing commit SHAs.
class GitHubSyncEngine implements SyncEngine {
  static const String _baseUrl = 'https://api.github.com';

  final String _token;
  final String _owner;
  final String _repo;
  final String _branch;
  Duration _interval;
  final http.Client _httpClient;
  final Future<void> Function()? _onRemoteChanged;

  Timer? _timer;
  String? _lastCommitSha;

  /// 직전 폴링 응답의 ETag. If-None-Match로 실어 보내면 변경이 없을 때 304가
  /// 오고 GitHub은 304를 rate limit에서 차감하지 않는다. 모바일은 데이터/배터리
  /// 비용도 걸려 있어 이득이 더 크다.
  String? _lastEtag;
  int _consecutiveErrors = 0;
  static const _maxBackoff = Duration(minutes: 5);
  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();

  GitHubSyncEngine({
    required String token,
    required String owner,
    required String repo,
    String branch = 'main',
    Duration interval = const Duration(seconds: 5),
    http.Client? httpClient,
    Future<void> Function()? onRemoteChanged,
    String? initialCommitSha,
  }) : _token = token,
       _owner = owner,
       _repo = repo,
       _branch = branch,
       _interval = interval,
       _httpClient = httpClient ?? http.Client(),
       _onRemoteChanged = onRemoteChanged,
       _lastCommitSha = initialCommitSha;

  /// Latest commit SHA observed on the tracked branch. Exposed so callers can
  /// persist it across app launches (see `GitHubNoteCache.lastCommitSha`).
  String? get lastCommitSha => _lastCommitSha;

  Duration get _currentInterval {
    if (_consecutiveErrors == 0) return _interval;
    final backoff = _interval * (1 << _consecutiveErrors.clamp(0, 10));
    return backoff > _maxBackoff ? _maxBackoff : backoff;
  }

  void updateInterval(Duration interval) {
    _interval = interval;
    if (_timer != null) {
      _restartTimer();
    }
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_currentInterval, (_) => syncNow());
  }

  @override
  void start() {
    _restartTimer();
    syncNow();
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<void> syncNow() async {
    _statusController.add(SyncStatus.syncing);
    try {
      final sha = await _fetchLatestCommitSha();
      if (sha != null && sha != _lastCommitSha) {
        _lastCommitSha = sha;
        await _onRemoteChanged?.call();
      }
      _statusController.add(SyncStatus.idle);
      if (_consecutiveErrors > 0) {
        _consecutiveErrors = 0;
        _restartTimer();
      }
    } catch (e) {
      _consecutiveErrors++;
      _restartTimer();
      _statusController.add(SyncStatus.error);
    }
  }

  @override
  Stream<SyncStatus> get statusStream => _statusController.stream;

  @override
  void dispose() {
    stop();
    _statusController.close();
    _httpClient.close();
  }

  Future<String?> _fetchLatestCommitSha() async {
    final uri = Uri.parse(
      '$_baseUrl/repos/$_owner/$_repo/commits?sha=$_branch&per_page=1',
    );
    final response = await _httpClient.get(
      uri,
      headers: {
        'Authorization': 'Bearer $_token',
        'Accept': 'application/vnd.github.v3+json',
        'X-GitHub-Api-Version': '2022-11-28',
        // ignore: use_null_aware_elements
        if (_lastEtag != null) 'If-None-Match': _lastEtag!,
      },
    );

    // Check rate limit header and throw if exhausted.
    final remaining = response.headers['x-ratelimit-remaining'];
    if (remaining != null) {
      final value = int.tryParse(remaining);
      if (value != null && value <= 0) {
        throw Exception('GitHub rate limit exhausted');
      }
    }

    // 304: 마지막 폴링 이후 변경 없음. 본문이 없으므로 알던 sha를 그대로 쓴다.
    if (response.statusCode == 304) return _lastCommitSha;

    if (response.statusCode != 200) {
      throw Exception('GitHub API error: ${response.statusCode}');
    }

    // 다음 폴링을 조건부 요청으로 만들기 위해 ETag를 기억한다.
    _lastEtag = response.headers['etag'];

    final json = jsonDecode(response.body) as List<dynamic>;
    if (json.isEmpty) return null;
    return (json[0] as Map<String, dynamic>)['sha'] as String?;
  }
}

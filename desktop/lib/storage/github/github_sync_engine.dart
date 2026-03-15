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
  final Duration _interval;
  final http.Client _httpClient;
  final Future<void> Function()? _onRemoteChanged;

  Timer? _timer;
  String? _lastCommitSha;
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
  })  : _token = token,
        _owner = owner,
        _repo = repo,
        _branch = branch,
        _interval = interval,
        _httpClient = httpClient ?? http.Client(),
        _onRemoteChanged = onRemoteChanged;

  Duration get _currentInterval {
    if (_consecutiveErrors == 0) return _interval;
    final backoff = _interval * (1 << _consecutiveErrors.clamp(0, 10));
    return backoff > _maxBackoff ? _maxBackoff : backoff;
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
    final response = await _httpClient.get(uri, headers: {
      'Authorization': 'Bearer $_token',
      'Accept': 'application/vnd.github.v3+json',
      'X-GitHub-Api-Version': '2022-11-28',
    });

    // Check rate limit header and throw if exhausted.
    final remaining = response.headers['x-ratelimit-remaining'];
    if (remaining != null) {
      final value = int.tryParse(remaining);
      if (value != null && value <= 0) {
        throw Exception('GitHub rate limit exhausted');
      }
    }

    if (response.statusCode != 200) {
      throw Exception('GitHub API error: ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as List<dynamic>;
    if (json.isEmpty) return null;
    return (json[0] as Map<String, dynamic>)['sha'] as String?;
  }
}

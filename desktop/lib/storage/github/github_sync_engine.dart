import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../sync_engine.dart';

/// Polling-based sync engine that detects remote changes by comparing commit SHAs.
class GitHubSyncEngine implements SyncEngine {
  static const String _baseUrl = 'https://api.github.com';

  final String token;
  final String owner;
  final String repo;
  final String branch;
  final Duration interval;
  final http.Client _httpClient;
  final Future<void> Function()? onRemoteChanged;

  Timer? _timer;
  String? _lastCommitSha;
  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();

  GitHubSyncEngine({
    required this.token,
    required this.owner,
    required this.repo,
    this.branch = 'main',
    this.interval = const Duration(seconds: 5),
    http.Client? httpClient,
    this.onRemoteChanged,
  }) : _httpClient = httpClient ?? http.Client();

  @override
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => syncNow());
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
        await onRemoteChanged?.call();
      }
      _statusController.add(SyncStatus.idle);
    } catch (e) {
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
      '$_baseUrl/repos/$owner/$repo/commits?sha=$branch&per_page=1',
    );
    final response = await _httpClient.get(uri, headers: {
      'Authorization': 'Bearer $token',
      'Accept': 'application/vnd.github.v3+json',
      'X-GitHub-Api-Version': '2022-11-28',
    });

    if (response.statusCode != 200) {
      throw Exception('GitHub API error: ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as List<dynamic>;
    if (json.isEmpty) return null;
    return (json[0] as Map<String, dynamic>)['sha'] as String?;
  }
}

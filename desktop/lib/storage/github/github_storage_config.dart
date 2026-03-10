import 'dart:convert';
import 'dart:io';

class GitHubStorageConfig {
  final String owner;
  final String repo;
  final String branch;
  final Duration syncInterval;

  const GitHubStorageConfig({
    required this.owner,
    required this.repo,
    this.branch = 'main',
    this.syncInterval = const Duration(seconds: 5),
  });

  factory GitHubStorageConfig.fromJson(Map<String, dynamic> json) {
    return GitHubStorageConfig(
      owner: json['owner'] as String,
      repo: json['repo'] as String,
      branch: (json['branch'] as String?) ?? 'main',
      syncInterval:
          Duration(seconds: (json['syncIntervalSeconds'] as int?) ?? 5),
    );
  }

  Map<String, dynamic> toJson() => {
        'owner': owner,
        'repo': repo,
        'branch': branch,
        'syncIntervalSeconds': syncInterval.inSeconds,
      };

  /// ~/.simsync/github_config.json
  static Future<GitHubStorageConfig?> load() async {
    final home = Platform.environment['HOME'] ?? '.';
    final file = File('$home/.simsync/github_config.json');
    if (!await file.exists()) return null;
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return GitHubStorageConfig.fromJson(json);
  }

  Future<void> save() async {
    final home = Platform.environment['HOME'] ?? '.';
    final dir = Directory('$home/.simsync');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}/github_config.json');
    await file.writeAsString(jsonEncode(toJson()));
  }
}

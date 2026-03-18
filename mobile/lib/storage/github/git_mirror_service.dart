import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'github_api_client.dart';

class GitMirrorService {
  final GitHubApiClient apiClient;
  final String token;
  final String owner;
  final String repo;
  final String branch;
  final http.Client _httpClient;
  late String localPath;

  bool _pathResolved = false;

  GitMirrorService({
    required this.apiClient,
    required this.token,
    required this.owner,
    required this.repo,
    this.branch = 'main',
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  Future<String> resolvePath() async {
    if (!_pathResolved) {
      final dir = await getApplicationDocumentsDirectory();
      localPath = '${dir.path}/git/$owner/$repo';
      _pathResolved = true;
    }
    return localPath;
  }

  String get mirrorPath => _pathResolved ? localPath : '';

  bool isMirrored() {
    if (!_pathResolved) return false;
    return File('$localPath/.mirror').existsSync();
  }

  Future<bool> mirrorIfNeeded() async {
    try {
      final path = await resolvePath();
      if (File('$path/.mirror').existsSync()) return true;
      return _fullDownload();
    } catch (_) {
      return false;
    }
  }

  Future<bool> pull() async {
    try {
      final path = await resolvePath();
      final shaFile = File('$path/.mirror_sha');
      final markerFile = File('$path/.mirror');

      if (!markerFile.existsSync()) {
        return _fullDownload();
      }

      final oldSha = shaFile.existsSync() ? shaFile.readAsStringSync() : '';
      final latestSha = await _fetchLatestCommitSha();
      if (latestSha == oldSha && oldSha.isNotEmpty) return true;

      final entries = await _fetchTree();
      if (entries == null) return false;

      for (final entry in entries) {
        final filePath = entry['path'] as String;
        final type = entry['type'] as String;
        if (type != 'blob') continue;

        final localFile = File('$path/$filePath');
        final remoteSha = entry['sha'] as String;

        if (localFile.existsSync()) {
          final localShaFile = File('$path/.shas/$filePath');
          if (localShaFile.existsSync() &&
              localShaFile.readAsStringSync() == remoteSha) {
            continue;
          }
        }

        final ok = await _downloadFile(filePath, localFile);
        if (ok) await _writeShaRecord(path, filePath, remoteSha);
      }

      await _cleanDeletedFiles(path, entries);

      if (latestSha.isNotEmpty) {
        await shaFile.writeAsString(latestSha);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _fullDownload() async {
    try {
      final path = await resolvePath();
      final dir = Directory(path);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final entries = await _fetchTree();
      if (entries == null) return false;

      for (final entry in entries) {
        final filePath = entry['path'] as String;
        final type = entry['type'] as String;
        final remoteSha = entry['sha'] as String;
        if (type != 'blob') continue;

        final localFile = File('$path/$filePath');
        final ok = await _downloadFile(filePath, localFile);
        if (ok) await _writeShaRecord(path, filePath, remoteSha);
      }

      await File('$path/.mirror').writeAsString(
        DateTime.now().toIso8601String(),
      );

      final latestSha = await _fetchLatestCommitSha();
      if (latestSha.isNotEmpty) {
        await File('$path/.mirror_sha').writeAsString(latestSha);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github.v3+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  Future<List<Map<String, dynamic>>?> _fetchTree() async {
    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/$owner/$repo/git/trees/$branch?recursive=1',
      );
      final response = await _httpClient.get(uri, headers: _headers);
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final tree = json['tree'] as List<dynamic>;
      return tree.cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  Future<String> _fetchLatestCommitSha() async {
    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/$owner/$repo/commits?sha=$branch&per_page=1',
      );
      final response = await _httpClient.get(uri, headers: _headers);
      if (response.statusCode != 200) return '';

      final json = jsonDecode(response.body) as List<dynamic>;
      if (json.isEmpty) return '';
      return (json[0] as Map<String, dynamic>)['sha'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<bool> _downloadFile(String repoPath, File localFile) async {
    try {
      final file = await apiClient.getFile(repoPath);
      final content = file.decodedContent;
      if (content == null) return false;

      if (!localFile.parent.existsSync()) {
        localFile.parent.createSync(recursive: true);
      }
      await localFile.writeAsString(content);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _writeShaRecord(
    String basePath,
    String filePath,
    String sha,
  ) async {
    final shaFile = File('$basePath/.shas/$filePath');
    if (!shaFile.parent.existsSync()) {
      shaFile.parent.createSync(recursive: true);
    }
    await shaFile.writeAsString(sha);
  }

  Future<void> _cleanDeletedFiles(
    String basePath,
    List<Map<String, dynamic>> entries,
  ) async {
    final remotePaths = <String>{};
    for (final entry in entries) {
      if (entry['type'] == 'blob') {
        remotePaths.add(entry['path'] as String);
      }
    }

    final shaDir = Directory('$basePath/.shas');
    if (!shaDir.existsSync()) return;

    final shaEntities = shaDir.listSync(recursive: true);
    for (final entity in shaEntities) {
      if (entity is! File) continue;
      final relative = entity.path.substring('$basePath/.shas/'.length);
      if (!remotePaths.contains(relative)) {
        final dataFile = File('$basePath/$relative');
        if (dataFile.existsSync()) {
          dataFile.deleteSync();
        }
        entity.deleteSync();
      }
    }
  }
}

import 'dart:convert';
import 'dart:io';

/// A single repository connection entry.
class RepoEntry {
  final String owner;
  final String repo;
  final String branch;
  final DateTime connectedAt;

  RepoEntry({
    required this.owner,
    required this.repo,
    this.branch = 'main',
    DateTime? connectedAt,
  }) : connectedAt = connectedAt ?? DateTime.now();

  String get fullName => '$owner/$repo';

  factory RepoEntry.fromJson(Map<String, dynamic> json) {
    return RepoEntry(
      owner: json['owner'] as String,
      repo: json['repo'] as String,
      branch: (json['branch'] as String?) ?? 'main',
      connectedAt: DateTime.parse(json['connectedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'owner': owner,
        'repo': repo,
        'branch': branch,
        'connectedAt': connectedAt.toIso8601String(),
      };
}

/// Stores and loads repository connection history from a local JSON file.
///
/// Default path: `~/.simsync/repos.json`
class RepoCache {
  final String _path;

  /// Creates a [RepoCache] that reads from `~/.simsync/repos.json`.
  RepoCache()
      : _path = '${Platform.environment['HOME']}/.simsync/repos.json';

  /// Creates a [RepoCache] with a custom file path (useful for testing).
  RepoCache.withPath(this._path);

  /// Loads all cached repo entries. Returns an empty list if the file is
  /// missing or contains corrupt data.
  Future<List<RepoEntry>> load() async {
    final file = File(_path);
    if (!await file.exists()) {
      return [];
    }
    try {
      final content = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(content) as List<dynamic>;
      return jsonList
          .map((e) => RepoEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Adds an entry to the cache. If an entry with the same owner/repo already
  /// exists it is replaced. The list is kept newest-first.
  Future<void> add(RepoEntry entry) async {
    final entries = await load();
    entries.removeWhere(
        (e) => e.owner == entry.owner && e.repo == entry.repo);
    entries.insert(0, entry);
    await _save(entries);
  }

  /// Removes an entry by owner and repo name.
  Future<void> remove(String owner, String repo) async {
    final entries = await load();
    entries.removeWhere((e) => e.owner == owner && e.repo == repo);
    await _save(entries);
  }

  Future<void> _save(List<RepoEntry> entries) async {
    final file = File(_path);
    await file.parent.create(recursive: true);
    final json = jsonEncode(entries.map((e) => e.toJson()).toList());
    await file.writeAsString(json);
  }
}

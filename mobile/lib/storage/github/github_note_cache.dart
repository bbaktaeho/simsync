import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One persisted note entry: blob SHA + raw markdown.
class GitHubNoteCacheEntry {
  final String sha;
  final String markdown;

  const GitHubNoteCacheEntry({required this.sha, required this.markdown});

  Map<String, dynamic> toJson() => {'sha': sha, 'markdown': markdown};

  factory GitHubNoteCacheEntry.fromJson(Map<String, dynamic> json) =>
      GitHubNoteCacheEntry(
        sha: json['sha'] as String,
        markdown: json['markdown'] as String,
      );
}

/// On-disk snapshot of the GitHub-backed note storage. The cache lets the app
/// skip the `branches → trees → contents × N` round-trip on cold start: when
/// the recorded `lastCommitSha` still matches GitHub's current HEAD, listing
/// can be served entirely from this snapshot with **zero** API calls.
///
/// Persistence policy:
///  - Reads: [load] is called once after construction.
///  - Writes: [scheduleSave] uses a 1-second debounce so bursts of mutations
///    (a search-index rebuild, a multi-file delete) collapse into one disk
///    write. [flush] forces an immediate write (used in tests / shutdown).
class GitHubNoteCache {
  GitHubNoteCache({required this.path});

  /// Absolute path of the JSON file that backs this cache.
  final String path;

  String? lastCommitSha;
  final Map<String, GitHubNoteCacheEntry> files = {};

  Timer? _saveDebounce;
  Future<void> _saveInFlight = Future.value();

  /// Loads the cache from disk if the file exists. Missing or malformed files
  /// are treated as empty (caller still gets a usable instance).
  Future<void> load() async {
    final file = File(path);
    if (!await file.exists()) return;
    try {
      final raw = await file.readAsString();
      if (raw.isEmpty) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      lastCommitSha = json['lastCommitSha'] as String?;
      final filesJson = json['files'] as Map<String, dynamic>? ?? const {};
      files.clear();
      filesJson.forEach((p, v) {
        files[p] = GitHubNoteCacheEntry.fromJson(v as Map<String, dynamic>);
      });
    } catch (_) {
      // Corrupt file: drop in-memory state, keep going. Next save overwrites.
      lastCommitSha = null;
      files.clear();
    }
  }

  /// Schedules a debounced disk write. Multiple calls within 1s coalesce.
  void scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 1), () {
      _saveDebounce = null;
      // Chain after any in-flight write so disk order matches schedule order.
      _saveInFlight = _saveInFlight.then((_) => _writeNow());
    });
  }

  /// Cancels pending debounce and writes immediately. Awaits the underlying
  /// in-flight write too. Used for deterministic teardown / tests.
  Future<void> flush() async {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    _saveInFlight = _saveInFlight.then((_) => _writeNow());
    await _saveInFlight;
  }

  Future<void> _writeNow() async {
    final json = <String, dynamic>{
      'version': 1,
      'lastCommitSha': lastCommitSha,
      'files': {
        for (final e in files.entries) e.key: e.value.toJson(),
      },
    };
    final encoded = jsonEncode(json);
    final file = File(path);
    await file.parent.create(recursive: true);
    // Atomic write: stage to a sibling tmp file, then rename. Avoids partial
    // files if the process is killed mid-write. The tmp name is unique per
    // cache INSTANCE: re-selecting a repo rebuilds the storage bundle, so an
    // old instance's debounced write can overlap the new instance on the same
    // path — a shared tmp name would let one rename the other's staging file
    // away mid-write.
    final tmp = File('$path.${identityHashCode(this)}.tmp');
    try {
      await tmp.writeAsString(encoded);
      await tmp.rename(path);
    } on FileSystemException {
      // Lost a write race with another instance (or the disk refused). This is
      // a cache: dropping one snapshot is fine, but the failure must not
      // poison [_saveInFlight] — a failed future in the chain would silently
      // kill every future save for this instance's lifetime.
    }
  }
}

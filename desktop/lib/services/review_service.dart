import '../storage/note_storage.dart';
import 'review_paths.dart';

/// Persists and loads AI review markdown files (weekly + monthly).
///
/// Reviews are plain markdown (no frontmatter) written to review paths under
/// `notes/` (see [review_paths]); they are kept out of the note list by the
/// note loaders. Writes go to the synced store and, when present, a local
/// mirror; reads prefer the synced store and fall back to the local mirror.
class ReviewService {
  ReviewService({required this.storage, this.localStorage});

  /// Synced store (e.g. GitHub). Required — reviews always sync.
  final NoteStorage storage;

  /// Optional local mirror written alongside the synced store.
  final NoteStorage? localStorage;

  /// Writes the local mirror first (fast, offline-safe) then the synced store,
  /// so a synced-write failure still leaves the review recoverable locally.
  Future<void> _save(String path, String content) async {
    await localStorage?.writeTextFile(path, content);
    await storage.writeTextFile(path, content);
  }

  /// Prefers the synced store (multi-device source of truth); falls back to the
  /// local mirror if the synced read is empty or fails (offline/permission).
  Future<String?> _load(String path) async {
    try {
      final remote = await storage.readTextFile(path);
      if (remote != null) return remote;
    } catch (_) {
      // Network / permission error — fall back to the local mirror below.
    }
    return localStorage?.readTextFile(path);
  }

  // ── Stage 1: outline (checkbox list of key items) ──

  Future<void> saveWeeklyOutline(DateTime weekStart, String content) =>
      _save(weeklyOutlinePath(weekStart), content);

  Future<String?> loadWeeklyOutline(DateTime weekStart) =>
      _load(weeklyOutlinePath(weekStart));

  Future<void> saveMonthlyOutline(DateTime month, String content) =>
      _save(monthlyOutlinePath(month), content);

  Future<String?> loadMonthlyOutline(DateTime month) =>
      _load(monthlyOutlinePath(month));

  // ── Stage 2: review (final write-up) ──

  /// Weekly review for the week beginning [weekStart] (a Monday).
  Future<void> saveWeekly(DateTime weekStart, String content) =>
      _save(weeklyReviewPath(weekStart), content);

  Future<String?> loadWeekly(DateTime weekStart) =>
      _load(weeklyReviewPath(weekStart));

  /// Monthly review for [month] (only year+month are used).
  Future<void> saveMonthly(DateTime month, String content) =>
      _save(monthlyReviewPath(month), content);

  Future<String?> loadMonthly(DateTime month) =>
      _load(monthlyReviewPath(month));
}

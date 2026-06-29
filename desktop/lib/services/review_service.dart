import '../storage/note_storage.dart';
import 'review_paths.dart';

/// Persists and loads AI review markdown files.
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

  /// Saves the weekly review for the week beginning [weekStart] (a Monday).
  ///
  /// Writes the local mirror first (fast, offline-safe) then the synced store,
  /// so a synced-write failure still leaves the review recoverable locally.
  Future<void> saveWeekly(DateTime weekStart, String content) async {
    final path = weeklyReviewPath(weekStart);
    await localStorage?.writeTextFile(path, content);
    await storage.writeTextFile(path, content);
  }

  /// Loads the saved weekly review for [weekStart], or null if none exists.
  ///
  /// Prefers the synced store (multi-device source of truth); falls back to the
  /// local mirror if the synced read is empty or fails (offline/permission).
  Future<String?> loadWeekly(DateTime weekStart) async {
    final path = weeklyReviewPath(weekStart);
    try {
      final remote = await storage.readTextFile(path);
      if (remote != null) return remote;
    } catch (_) {
      // Network / permission error — fall back to the local mirror below.
    }
    return localStorage?.readTextFile(path);
  }
}

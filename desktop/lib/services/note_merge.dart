import '../models/note.dart';

/// Merges freshly loaded notes with in-memory dirty ones so a reload racing a
/// debounced save never discards an unsaved edit (Last-Write-Wins protection):
/// a loaded copy is replaced by its dirty in-memory version, and dirty notes
/// storage doesn't know yet (just created) are re-appended.
///
/// Mutates and returns [loaded]. Shared by the document screen and the menu
/// bar popover so the two surfaces can't drift on this correctness-critical
/// rule. Callers re-sort afterwards (each surface has its own ordering).
List<Note> mergeDirtyNotes({
  required List<Note> loaded,
  required List<Note> current,
}) {
  final dirtyById = <String, Note>{
    for (final n in current)
      if (n.isDirty) n.id: n,
  };
  if (dirtyById.isEmpty) return loaded;
  for (var i = 0; i < loaded.length; i++) {
    final dirty = dirtyById.remove(loaded[i].id);
    if (dirty != null) loaded[i] = dirty;
  }
  loaded.addAll(dirtyById.values);
  return loaded;
}

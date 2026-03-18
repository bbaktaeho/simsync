/// Whether a note is synced to remote or stored locally.
enum StorageType { synced, local }

/// Represents a single markdown note.
class Note {
  final String id;
  final DateTime noteDate;
  String title;
  String content;
  final bool isDefault;
  bool isMemo;
  List<String> tags;
  final DateTime createdAt;
  DateTime updatedAt;

  /// Runtime-only flag indicating unsaved local edits.
  /// Not serialized — defaults to false.
  bool isDirty;

  /// Whether this note is synced to remote or stored locally.
  final StorageType storageType;

  Note({
    required this.id,
    required this.noteDate,
    required this.title,
    required this.content,
    required this.isDefault,
    this.isMemo = false,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
    this.isDirty = false,
    this.storageType = StorageType.synced,
  });

  Note copyWith({
    String? title,
    String? content,
    bool? isMemo,
    List<String>? tags,
    DateTime? updatedAt,
    bool? isDirty,
  }) {
    return Note(
      id: id,
      noteDate: noteDate,
      title: title ?? this.title,
      content: content ?? this.content,
      isDefault: isDefault,
      isMemo: isMemo ?? this.isMemo,
      tags: tags ?? List.from(this.tags),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDirty: isDirty ?? this.isDirty,
      storageType: storageType,
    );
  }
}

/// Represents a single markdown note.
class Note {
  final String id;
  final DateTime noteDate;
  String title;
  String content;
  final bool isDefault;
  List<String> tags;
  final DateTime createdAt;
  DateTime updatedAt;

  /// Runtime-only flag indicating unsaved local edits.
  /// Not serialized — defaults to false.
  bool isDirty;

  Note({
    required this.id,
    required this.noteDate,
    required this.title,
    required this.content,
    required this.isDefault,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
    this.isDirty = false,
  });

  Note copyWith({
    String? title,
    String? content,
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
      tags: tags ?? List.from(this.tags),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDirty: isDirty ?? this.isDirty,
    );
  }
}

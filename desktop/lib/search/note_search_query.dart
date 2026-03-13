class NoteSearchQuery {
  final String text;
  final String tag;
  final DateTime? startDate;
  final DateTime? endDate;

  const NoteSearchQuery({
    this.text = '',
    this.tag = '',
    this.startDate,
    this.endDate,
  });

  bool get isEmpty =>
      text.trim().isEmpty &&
      tag.trim().isEmpty &&
      startDate == null &&
      endDate == null;

  NoteSearchQuery copyWith({
    String? text,
    String? tag,
    Object? startDate = _sentinel,
    Object? endDate = _sentinel,
  }) {
    return NoteSearchQuery(
      text: text ?? this.text,
      tag: tag ?? this.tag,
      startDate: startDate == _sentinel
          ? this.startDate
          : startDate as DateTime?,
      endDate: endDate == _sentinel ? this.endDate : endDate as DateTime?,
    );
  }

  static const Object _sentinel = Object();
}

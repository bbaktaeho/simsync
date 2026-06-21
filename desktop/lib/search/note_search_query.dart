import 'package:flutter/foundation.dart';

/// An immutable note search query: free text, zero or more tag filters (AND),
/// and an inclusive note-date range.
@immutable
class NoteSearchQuery {
  final String text;
  final List<String> tags;
  final DateTime? startDate;
  final DateTime? endDate;

  const NoteSearchQuery({
    this.text = '',
    this.tags = const [],
    this.startDate,
    this.endDate,
  });

  bool get isEmpty =>
      text.trim().isEmpty &&
      tags.isEmpty &&
      startDate == null &&
      endDate == null;

  bool get hasFilters =>
      tags.isNotEmpty || startDate != null || endDate != null;

  NoteSearchQuery copyWith({
    String? text,
    List<String>? tags,
    Object? startDate = _sentinel,
    Object? endDate = _sentinel,
  }) {
    return NoteSearchQuery(
      text: text ?? this.text,
      tags: tags ?? this.tags,
      startDate:
          startDate == _sentinel ? this.startDate : startDate as DateTime?,
      endDate: endDate == _sentinel ? this.endDate : endDate as DateTime?,
    );
  }

  /// Toggles [tag] in the filter set (case-insensitive), returning a new query.
  NoteSearchQuery toggleTag(String tag) {
    final lower = tag.toLowerCase();
    final next = [...tags];
    final existing = next.indexWhere((t) => t.toLowerCase() == lower);
    if (existing >= 0) {
      next.removeAt(existing);
    } else {
      next.add(tag);
    }
    return copyWith(tags: next);
  }

  bool hasTag(String tag) {
    final lower = tag.toLowerCase();
    return tags.any((t) => t.toLowerCase() == lower);
  }

  static const Object _sentinel = Object();
}

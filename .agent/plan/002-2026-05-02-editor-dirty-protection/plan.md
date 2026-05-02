---
title: Editor Dirty Protection
description: 노트 전환/화면 종료 시 미저장 변경이 유실되는 버그 수정
type: plan
created: 2026-05-02
status: active
related:
  - .agent/plan/002-2026-05-02-editor-dirty-protection/01-root-cause.md
---

# Editor Dirty Protection

## Problem

사용자가 노트를 편집하던 중 다른 노트로 이동하면 (또는 화면이 닫히면) 작성 중이던 변경이 유실되고 이전 GitHub 상태로 되돌아간다.

상세 시나리오와 root cause는 [01-root-cause.md](01-root-cause.md) 참고.

## Confirmed Decisions

| 항목 | 결정 |
|------|------|
| 영향 범위 | desktop `EditorPanel`, mobile `EditorScreen` |
| 우선순위 | 데이터 손실 위험 → 즉시 수정 |
| 검증 | 새 widget test (회귀 방지) + 기존 test 회귀 없음 |
| 호환성 | UI/외부 API 동일, 동작만 보강 |

## Root Cause (요약)

### Desktop `editor_panel.dart`
1. **L69-74 `didUpdateWidget`**: `widget.note?.id != _loadedNoteId` 시 `_syncControllers()`만 호출. pending debounce timer 미취소, 이전 노트의 dirty 텍스트 미저장.
2. **L94-99 `_onContentChanged`**: 1초 debounce 등록. 이 1초 사이에 노트 텍스트 변경은 **컨트롤러에만** 존재 (note 객체 미변경).
3. **L101-111 `_save`**: `widget.note`를 직접 참조 → 노트 전환 후 만료되면 잘못된 노트로 save 호출.
4. **L86-92 `dispose`**: timer cancel만, dirty 텍스트 flush 없음.

### Mobile `editor_screen.dart`
- **L73-85 `dispose`**: `_saveImmediately()` 가 async fire-and-forget이고, 그 안에서 setState 호출 → unmounted 후 setState 에러 가능. Catch silent → 사용자가 유실 인지 못함.

## Fix Strategy

### Desktop `editor_panel.dart`
1. **`didUpdateWidget`**: 노트 ID 변경 시 이전 노트의 dirty 텍스트를 동기적으로 flush 후 컨트롤러 교체.
2. **`dispose`**: 위와 동일하게 dirty이면 마지막 한 번 flush.
3. **`_save`** (방어): note id가 `_loadedNoteId`와 일치하지 않으면 stale로 간주하고 무시.

```dart
void _flushPending(Note note) {
  if (widget.isReadOnly || !note.isDirty) return;
  _autoSaveTimer?.cancel();
  _autoSaveTimer = null;
  final updated = note.copyWith(
    title: _titleController.text,
    content: _contentController.text,
    updatedAt: DateTime.now(),
  );
  widget.onNoteChanged?.call(updated);
}

@override
void didUpdateWidget(EditorPanel oldWidget) {
  super.didUpdateWidget(oldWidget);
  if (widget.note?.id != _loadedNoteId) {
    final previousNote = oldWidget.note;
    if (previousNote != null) _flushPending(previousNote);
    _syncControllers();
  }
}

@override
void dispose() {
  _autoSaveTimer?.cancel();
  final note = widget.note;
  if (note != null && note.isDirty && !widget.isReadOnly) {
    final updated = note.copyWith(
      title: _titleController.text,
      content: _contentController.text,
      updatedAt: DateTime.now(),
    );
    widget.onNoteChanged?.call(updated);
  }
  _titleController.dispose();
  _contentController.dispose();
  _tagController.dispose();
  super.dispose();
}

void _save() {
  final note = widget.note;
  if (note == null || widget.isReadOnly) return;
  if (note.id != _loadedNoteId) return; // stale timer
  final now = DateTime.now();
  final updated = note.copyWith(
    title: _titleController.text,
    content: _contentController.text,
    updatedAt: now,
  );
  widget.onNoteChanged?.call(updated);
  setState(() => _lastSaved = now);
}
```

### Mobile `editor_screen.dart`
- `dispose`에서 `_saveImmediately()` 호출 대신 setState 없는 dispose-safe flush 사용. callback chain (`.then`)으로 storage save와 onNoteChanged 호출.

```dart
@override
void dispose() {
  widget.refreshSignal?.removeListener(_handleRefreshSignal);
  _saveDebounce?.cancel();
  // dispose 시 dirty이면 동기적으로 flush 호출 (await 불가능, fire-and-forget)
  if (_isDirty) {
    final note = _note;
    final cb = widget.onNoteChanged;
    widget.storage
        .saveNote(note)
        .then((_) => cb(note))
        .catchError((_) {/* unmounted; silent */});
  }
  _tabController.dispose();
  _titleController.dispose();
  _contentController.dispose();
  _tagsController.dispose();
  super.dispose();
}
```

## Test Strategy

### Failing test (회귀 방지)
1. **Desktop widget test** (`test/screens/document_screen_dirty_test.dart` 또는 `test/widget_test.dart` 보강):
   - In-memory storage 두 노트(A, B) 준비
   - DocumentScreen 마운트, 노트 A 선택
   - 컨트롤러에 텍스트 입력 (A의 변경 시뮬레이션)
   - debounce 만료 전에 B로 전환
   - DocumentScreen unmount 후 storage에서 A를 다시 읽어 변경이 영속화됐는지 검증

2. **Mobile widget test**: EditorScreen에 dirty 상태 만들고 dispose 트리거, storage saveNote가 호출됐는지 검증.

### 회귀 방지
- 기존 desktop/mobile 테스트 모두 통과
- `flutter analyze` clean

## Out of Scope

- sync engine 변경 (현재 dirty 보호 로직 충분)
- 새 노트 생성 시 임시 ID 처리 (별개 이슈)
- 충돌 해결 UX 개선 (last-write-wins 유지)

## Checklist

- [ ] failing test 작성 → 현재 코드에서 실패 확인
- [ ] desktop `editor_panel.dart` fix 구현
- [ ] mobile `editor_screen.dart` fix 구현
- [ ] failing test pass 확인
- [ ] desktop/mobile `flutter analyze` clean
- [ ] desktop/mobile `flutter test` 회귀 없음
- [ ] PR 작성 및 push

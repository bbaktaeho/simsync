---
title: Root Cause — Editor Dirty Protection
description: 노트 전환 시 미저장 변경 유실의 정확한 원인 분석
type: plan
created: 2026-05-02
status: active
related:
  - .agent/plan/002-2026-05-02-editor-dirty-protection/plan.md
---

# Root Cause Analysis

## 시나리오 재현 (Desktop)

1. 사용자가 노트 A를 클릭하여 편집기에 로드
2. 본문 일부 수정 → `_titleController` / `_contentController` 의 텍스트가 변경됨
3. `_onContentChanged` 호출 → `widget.note.isDirty = true` 설정 + 1초 debounce timer 등록
4. **debounce 만료 (1초) 전**에 사용자가 노트 B를 클릭
5. `EditorPanel`은 부모로부터 새로운 `widget.note=B` 를 받음
6. `didUpdateWidget` 호출 → `widget.note.id != _loadedNoteId` 이므로 `_syncControllers()` 호출
7. `_syncControllers()` 가 `_titleController.text = B.title`, `_contentController.text = B.content` 로 컨트롤러 텍스트를 **B의 내용으로 덮어씀**
8. **이 시점에서 노트 A의 변경된 텍스트는 어디에도 남아 있지 않음**
   - 노트 A 객체 자체: title/content 미변경 (debounce 안 만료됐으니 `_save`가 copyWith 호출 안 함)
   - 컨트롤러: 이미 B의 내용으로 덮어씌움
9. 1초 timer 만료 → `_save()` 실행
10. `_save()` 는 `widget.note` (= B) 와 컨트롤러 텍스트 (= B의 텍스트)로 `copyWith` → B를 B로 덮어쓰는 no-op
11. **결과**: 노트 A는 변경 전 상태 그대로, 사용자 변경 영구 유실

## 핵심 문제 코드

### 1. `didUpdateWidget` (desktop/lib/widgets/editor_panel.dart:69-74)

```dart
@override
void didUpdateWidget(EditorPanel oldWidget) {
  super.didUpdateWidget(oldWidget);
  if (widget.note?.id != _loadedNoteId) {
    _syncControllers();  // 컨트롤러를 새 노트 내용으로 즉시 덮어씀
  }
}
```

**누락**: pending debounce timer 미취소, 이전 노트의 dirty 텍스트 미flush.

### 2. `_save` (desktop/lib/widgets/editor_panel.dart:101-111)

```dart
void _save() {
  if (widget.note == null || widget.isReadOnly) return;
  final now = DateTime.now();
  final updated = widget.note!.copyWith(  // <-- widget.note는 시점 무관하게 평가됨
    title: _titleController.text,
    content: _contentController.text,
    updatedAt: now,
  );
  widget.onNoteChanged?.call(updated);
  setState(() => _lastSaved = now);
}
```

**문제**: timer 등록 시점의 `widget.note`가 아니라 **콜백 실행 시점의** `widget.note`를 사용. 노트 전환 후 timer가 만료되면 잘못된 노트에 대해 호출.

### 3. `dispose` (desktop/lib/widgets/editor_panel.dart:86-92)

```dart
@override
void dispose() {
  _autoSaveTimer?.cancel();
  _titleController.dispose();
  _contentController.dispose();
  _tagController.dispose();
  super.dispose();
}
```

**누락**: dirty 텍스트 flush 없음. 화면이 닫힐 때 변경 유실 가능.

## Mobile 부수 이슈

### `dispose` (mobile/lib/screens/editor_screen.dart:73-85)

```dart
@override
void dispose() {
  widget.refreshSignal?.removeListener(_handleRefreshSignal);
  _saveDebounce?.cancel();
  _tabController.dispose();
  _titleController.dispose();
  _contentController.dispose();
  _tagsController.dispose();
  // Save any pending changes on exit.
  if (_isDirty) {
    _saveImmediately();  // async, fire-and-forget
  }
  super.dispose();
}
```

**문제**:
1. `_saveImmediately`는 `async`이지만 await 불가 (dispose는 sync). fire-and-forget.
2. `_saveImmediately` 내부에서 `setState(() => _isSaving = true)` 호출 → dispose 후 setState → 에러 가능.
3. catch가 silent → 실패해도 사용자 인지 못함.

Mobile은 화면 인스턴스가 분리되기 때문에 노트 전환 시 desktop 같은 race는 없지만, 화면이 빠르게 닫힐 때 (뒤로가기 직후 다른 노트로 이동) dispose의 fire-and-forget save가 실패하거나 setState 에러로 중단될 가능성.

## Sync Engine과의 관계

`GitHubSyncEngine`이 5초마다 commit SHA를 polling. 변경 감지 시 `onRemoteChanged` → `_refreshSignal.value++` → `DocumentScreen._loadNotes`. 이 흐름은 `_allNotes` 의 dirty 노트를 보호하는 merge logic이 있어 **이 부분 자체는 안전**.

다만 위 문제로 인해 dirty 텍스트가 **컨트롤러에만** 있고 노트 객체에 반영 안 된 1초 사이에 sync가 트리거되면, 컨트롤러는 사용자 텍스트를 유지 (`_loadedNoteId` 동일하므로 `_syncControllers` 미호출) → 안전. 즉 sync 자체는 buggy하지 않다.

문제는 오직 **노트 전환** + **컨트롤러 강제 교체** 시점에서만 발생.

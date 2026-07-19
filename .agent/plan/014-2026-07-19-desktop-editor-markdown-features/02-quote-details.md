---
title: 인용문 | + details 접기 구현 (Task 3-7)
description: 극소 스트럿 전환, | 인용문, details 파싱/렌더링/토글/입력 트리거
type: plan
created: 2026-07-19
---

# 인용문 `|` + details 접기 (Task 3-7)

## 결정 기록: 에디터 내 높이 접기는 이번 범위에서 제외 (2026-07-19)

에디터의 TextField는 `StrutStyle.fromTextStyle(bodyStyle)`을 쓰고(`editor_panel.dart:616`) 모든 줄에 본문 높이 floor가 걸린다. details 본문을 실제 높이 0으로 접으려면 이 floor를 없애야 하는데, 스파이크 실측 결과 **폐기했다**:

1. `StrutStyle.disabled`: EditableText가 strut에 `inheritFromTextStyle(widget.style)`을 적용해 fontSize가 본문 폰트로 채워지고, height 0은 "폰트 자연 높이"로 해석돼 줄당 16px floor가 남는다.
2. 극소 명시 스트럿(`fontSize: 0.1`): TextField 단독 실측으로는 완전 접힘(+0px)이지만, **미러 TextPainter(데코 페인터/오버레이 측정)가 실제 RenderEditable 배치와 ~2.3px 발산**한다. 동일 span/strut/scaler/폭으로도 재현 불가 — 원인이 RenderEditable 내부에 있고, 균일 body 스트럿이 지금까지 0.5px 정렬을 보장해 온 장치였다. 긴 문서에서의 증폭을 보장할 수 없어 오버레이 아키텍처 전체를 걸 수 없다. (커밋 8f6ba90 → 2ca5b9a revert)

**재조정된 범위**: 접힘 상태는 `<details open>` 속성으로 파일에 유지되어 GitHub 웹/다른 디바이스에서 접힌다. 에디터에서는 chevron이 속성만 토글하고 본문은 항상 표시한다. 에디터 내 시각 접힘은 후속 과제 — 측정을 RenderEditable 직접 조회로 바꾸는 아키텍처 변경이 선행되어야 한다.

이미지 높이 예약(04 문서)은 스트럿과 무관하다: 스트럿은 최소값(floor)일 뿐이고, 큰 첫 글자는 줄을 그 이상으로 키운다. body 스트럿 그대로 동작한다.

## Task 3: 취소됨 (극소 스트럿 전환)

위 결정 기록 참조. 구현 시도(8f6ba90)는 2ca5b9a로 revert됨. 아래 Task 4부터 진행한다.


## Task 4: `|` 인용문

**Files:**
- Modify: `desktop/lib/widgets/markdown_editing_controller.dart:44` (`_blockquote`)
- Modify: `desktop/lib/widgets/editor_block_decorations.dart:42` (`_quote`) + `filterEditorRegions` 신설
- Modify: `desktop/lib/widgets/editor_panel.dart` (`_blockPrefixes:776`, 데코 필터 교체)
- Test: `desktop/test/widgets/markdown_editing_controller_test.dart`, `desktop/test/widgets/editor_block_decorations_test.dart` (추가)

**Interfaces:**
- Produces: `filterEditorRegions(List<EditorBlockRegion> regions, List<TableRegion> tables, List<DetailsRegion> details) → List<EditorBlockRegion>` (editor_block_decorations.dart). details 파라미터는 Task 5의 타입 — **Task 4 시점에는 details 없이 2-인자로 만들고, Task 6에서 3-인자로 확장한다.**

- [ ] **Step 1: 실패하는 테스트 작성**

`markdown_editing_controller_test.dart`에 추가. 기존 헬퍼를 그대로 쓴다 — `_build(tester, text)`는 async(WidgetTester 필요), `_flatten`은 `(text, style)` 쌍 리스트를 반환한다(`markdown_editing_controller_test.dart:7-47`):

```dart
  group('pipe blockquote', () {
    testWidgets('| 인용문 줄도 문자 보존 invariant를 지킨다', (tester) async {
      const text = '| quoted line\nplain';
      final span = await _build(tester, text);
      expect(_flatten(span).map((e) => e.$1).join(), text);
    });

    testWidgets('레거시 > 인용문도 여전히 매칭된다', (tester) async {
      const text = '> old quote';
      final span = await _build(tester, text);
      expect(_flatten(span).map((e) => e.$1).join(), text);
    });
  });
```

`editor_block_decorations_test.dart`에 추가:

```dart
  group('pipe quote regions', () {
    test('| 줄이 quote 영역으로 잡힌다', () {
      const text = '| a\n| b\nplain';
      final regions = parseEditorBlockRegions(text);
      expect(regions, [
        const EditorBlockRegion(start: 0, end: 7, kind: EditorBlockKind.quote),
      ]);
    });

    test('filterEditorRegions는 테이블과 겹치는 quote 영역을 버린다', () {
      const text = '| h1 | h2 |\n| --- | --- |\n| a | b |';
      final regions = parseEditorBlockRegions(text);
      final tables = findTableRegions(text);
      final filtered = filterEditorRegions(regions, tables);
      expect(filtered.where((r) => r.kind == EditorBlockKind.quote), isEmpty);
    });

    test('filterEditorRegions는 테이블 구분선의 rule 영역도 버린다 (기존 동작 이전)', () {
      const text = 'x | y\n---\n| a | b |'; // 파이프 없는 구분선 케이스는 기존 로직 유지 확인용
      final regions = parseEditorBlockRegions(text);
      final tables = findTableRegions(text);
      final filtered = filterEditorRegions(regions, tables);
      for (final t in tables) {
        expect(
          filtered.any((r) => r.kind == EditorBlockKind.rule && r.start == t.separatorRange.start),
          isFalse,
        );
      }
    });
  });
```

(`findTableRegions`는 `package:simsync/services/markdown_editing.dart`에서 import)

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/widgets/editor_block_decorations_test.dart test/widgets/markdown_editing_controller_test.dart`
Expected: FAIL — `filterEditorRegions` 미정의, `|` 줄이 quote로 안 잡힘

- [ ] **Step 3: 구현**

`markdown_editing_controller.dart:44`:

```dart
  // 인용문: 새 문법은 `| `, 레거시 `> `도 하위 호환으로 계속 렌더링한다.
  // 테이블 줄은 buildTextSpan에서 먼저 걸러지므로 여기 도달하지 않는다.
  static final RegExp _blockquote = RegExp(r'^(\s*(?:[>|]\s?)+)(.*)$');
```

`editor_block_decorations.dart:42`:

```dart
final RegExp _quote = RegExp(r'^\s*[>|]');
```

`editor_block_decorations.dart` 파일 끝에 추가:

```dart
/// 데코레이션 영역 후처리: 테이블과 겹치는 quote 바(테이블 행도 `|`로 시작),
/// 테이블 구분선과 겹치는 rule 선을 제거한다.
List<EditorBlockRegion> filterEditorRegions(
  List<EditorBlockRegion> regions,
  List<TableRegion> tables,
) {
  if (regions.isEmpty) return regions;
  final sepStarts = {for (final t in tables) t.separatorRange.start};
  return regions.where((r) {
    if (r.kind == EditorBlockKind.rule && sepStarts.contains(r.start)) {
      return false;
    }
    if (r.kind == EditorBlockKind.quote &&
        tables.any((t) => r.start <= t.end && r.end >= t.start)) {
      return false;
    }
    return true;
  }).toList();
}
```

`editor_panel.dart` `_buildEditor`의 데코 빌더(`:655-666`)에서 기존 sepStarts 인라인 필터를 교체:

```dart
                final allRegions =
                    parseEditorBlockRegions(_contentController.text);
                final tables = findTableRegions(_contentController.text);
                final regions = filterEditorRegions(allRegions, tables);
```

`editor_panel.dart:776` `_blockPrefixes`의 quote 항목 교체 (레거시 `> `는 프리픽스 교체 인식용으로 유지):

```dart
    RegExp(r'^\| '), // quote (new)
    RegExp(r'^> '), // quote (legacy, 교체 인식용)
  ];
```

- [ ] **Step 4: 통과 확인**

Run: `flutter test test/widgets/` → 전체 PASS

- [ ] **Step 5: 커밋**

```bash
git add desktop/lib/widgets/markdown_editing_controller.dart desktop/lib/widgets/editor_block_decorations.dart desktop/lib/widgets/editor_panel.dart desktop/test/widgets/
git commit -m "feat: 인용문 | 문법 전환 (레거시 > 하위 호환, 테이블 충돌 필터)"
```

---

## Task 5: findDetailsRegions 파싱

**Files:**
- Modify: `desktop/lib/services/markdown_editing.dart` (파일 끝에 섹션 추가)
- Test: `desktop/test/services/markdown_editing_test.dart` (추가)

**Interfaces:**
- Produces:
  - `class DetailsRegion { int start; int end; bool open; ({int start, int end}) detailsLineRange; ({int start, int end}) summaryLineRange; List<({int start, int end})> bodyLineRanges; ({int start, int end}) closeLineRange; }`
  - `List<DetailsRegion> findDetailsRegions(String text)`
  - Task 6(렌더링), Task 7(토글 오버레이)이 사용

지원 형식 (각 요소는 자기 줄):

```
<details>            혹은 <details open>
<summary>제목</summary>
...본문 (빈 줄 포함)...
</details>
```

한계 (문서화된 MVP 제약): 중첩 미지원(첫 `</details>`에서 닫힘), summary 줄이 바로 다음 줄에 없으면 무시, 본문에 코드 fence가 있으면 블록 전체를 무시(접기 없이 원문 렌더링 — fence 상태 추적 단순화).

- [ ] **Step 1: 실패하는 테스트 작성**

`markdown_editing_test.dart`에 추가:

```dart
  group('findDetailsRegions', () {
    test('닫힌 블록을 파싱한다', () {
      const text = '<details>\n<summary>제목</summary>\n\n내용\n</details>';
      final regions = findDetailsRegions(text);
      expect(regions, hasLength(1));
      final d = regions.first;
      expect(d.open, isFalse);
      expect(d.start, 0);
      expect(d.end, text.length);
      expect(text.substring(d.summaryLineRange.start, d.summaryLineRange.end),
          '<summary>제목</summary>');
      expect(d.bodyLineRanges, hasLength(2)); // 빈 줄 + '내용'
    });

    test('open 속성을 읽는다', () {
      const text = '<details open>\n<summary>t</summary>\nbody\n</details>';
      expect(findDetailsRegions(text).single.open, isTrue);
    });

    test('summary 줄이 없으면 무시한다', () {
      const text = '<details>\nno summary\n</details>';
      expect(findDetailsRegions(text), isEmpty);
    });

    test('닫는 태그가 없으면 무시한다', () {
      const text = '<details>\n<summary>t</summary>\nbody';
      expect(findDetailsRegions(text), isEmpty);
    });

    test('코드 fence 안의 details는 무시한다', () {
      const text = '```\n<details>\n<summary>t</summary>\n</details>\n```';
      expect(findDetailsRegions(text), isEmpty);
    });

    test('본문에 fence가 있으면 그 블록은 무시한다', () {
      const text =
          '<details>\n<summary>t</summary>\n```\ncode\n```\n</details>';
      expect(findDetailsRegions(text), isEmpty);
    });
  });
```

- [ ] **Step 2: 실패 확인** → `flutter test test/services/markdown_editing_test.dart` FAIL (미정의)

- [ ] **Step 3: 구현**

`markdown_editing.dart` 파일 끝에 추가:

```dart
// ── <details> 접기 블록 ─────────────────────────────────────────────────────

final RegExp _detailsOpenRe = RegExp(r'^\s*<details( open)?>\s*$');
final RegExp _summaryLineRe = RegExp(r'^\s*<summary>.*</summary>\s*$');
final RegExp _detailsCloseRe = RegExp(r'^\s*</details>\s*$');

/// 에디터 텍스트에서 찾은 <details> 블록 하나. 형식(각 요소는 자기 줄):
///   <details> | <details open>
///   <summary>제목</summary>
///   ...본문...
///   </details>
/// 중첩은 지원하지 않고, 본문에 코드 fence가 있으면 블록을 무시한다.
class DetailsRegion {
  const DetailsRegion({
    required this.start,
    required this.end,
    required this.open,
    required this.detailsLineRange,
    required this.summaryLineRange,
    required this.bodyLineRanges,
    required this.closeLineRange,
  });

  /// <details> 줄 시작 오프셋 (inclusive).
  final int start;

  /// </details> 줄 끝 오프셋 (exclusive).
  final int end;

  /// `<details open>` 여부. 파일에 저장되는 펼침 상태다.
  final bool open;

  final ({int start, int end}) detailsLineRange;
  final ({int start, int end}) summaryLineRange;
  final List<({int start, int end})> bodyLineRanges;
  final ({int start, int end}) closeLineRange;
}

/// 모든 <details> 블록을 찾는다. fence 내부와 형식이 안 맞는 블록은 무시.
List<DetailsRegion> findDetailsRegions(String text) {
  if (text.isEmpty) return const [];
  final lines = text.split('\n');
  final starts = <int>[];
  var acc = 0;
  for (final l in lines) {
    starts.add(acc);
    acc += l.length + 1;
  }
  ({int start, int end}) rangeOf(int i) =>
      (start: starts[i], end: starts[i] + lines[i].length);

  final result = <DetailsRegion>[];
  var inFence = false;
  var i = 0;
  while (i < lines.length) {
    if (_fenceRe.hasMatch(lines[i])) {
      inFence = !inFence;
      i++;
      continue;
    }
    if (inFence) {
      i++;
      continue;
    }
    final openMatch = _detailsOpenRe.firstMatch(lines[i]);
    if (openMatch == null ||
        i + 1 >= lines.length ||
        !_summaryLineRe.hasMatch(lines[i + 1])) {
      i++;
      continue;
    }
    var close = -1;
    for (var j = i + 2; j < lines.length; j++) {
      if (_fenceRe.hasMatch(lines[j])) break; // 본문 fence → 블록 무효
      if (_detailsCloseRe.hasMatch(lines[j])) {
        close = j;
        break;
      }
    }
    if (close == -1) {
      i++;
      continue;
    }
    result.add(DetailsRegion(
      start: starts[i],
      end: starts[close] + lines[close].length,
      open: openMatch.group(1) != null,
      detailsLineRange: rangeOf(i),
      summaryLineRange: rangeOf(i + 1),
      bodyLineRanges: [for (var j = i + 2; j < close; j++) rangeOf(j)],
      closeLineRange: rangeOf(close),
    ));
    i = close + 1;
  }
  return result;
}
```

- [ ] **Step 4: 통과 확인** → `flutter test test/services/markdown_editing_test.dart` PASS

- [ ] **Step 5: 커밋**

```bash
git add desktop/lib/services/markdown_editing.dart desktop/test/services/markdown_editing_test.dart
git commit -m "feat: details 블록 파서 추가"
```

---

## Task 6: details 렌더링

> 재조정됨 (상단 결정 기록 참조): 에디터 내 높이 접기는 하지 않는다. 본문은 열림/닫힘과 무관하게 항상 표시하고, 태그 줄만 구조 마커로 숨긴다. `filterEditorRegions`는 Task 4의 2-인자 그대로 유지한다.

**Files:**
- Modify: `desktop/lib/widgets/markdown_editing_controller.dart` (`buildTextSpan` 분기 + 헬퍼)
- Test: `desktop/test/widgets/markdown_editing_controller_test.dart` (추가)

**Interfaces:**
- Consumes: Task 5 `findDetailsRegions`

렌더링 규칙:
- `<details>` / `<details open>` / `</details>` 태그 줄: 캐럿이 그 줄에 있으면 dim 노출(편집/삭제 가능), 아니면 `_hideKeepHeight`(투명, 높이 유지 — fence 줄과 동일한 처리)
- `<summary>제목</summary>` 줄: 태그는 `_marker`(inactive 시 폭 접힘), 제목은 semibold + 인라인 스타일
- 본문 줄: 일반 파이프라인(`_styleLine` 등)으로 렌더링 — 열림/닫힘 무관

- [ ] **Step 1: 실패하는 테스트 작성**

`markdown_editing_controller_test.dart`에 추가. 기존 헬퍼(`_build(tester, text, {focused, selection})` async, `_flatten` → `(text, style)` 쌍)를 쓰고, 조각의 스타일을 찾는 헬퍼를 하나 추가한다 (컨트롤러는 모든 leaf 스팬에 명시 스타일을 설정하므로 상속 추적이 필요 없다):

```dart
/// [fragment]를 포함하는 첫 스팬의 스타일 (Task 6/12 렌더링 검증용).
TextStyle? _styleOf(TextSpan root, String fragment) {
  for (final (text, style) in _flatten(root)) {
    if (text.contains(fragment)) return style;
  }
  return null;
}
```

```dart
  group('details rendering', () {
    const closed = '<details>\n<summary>제목</summary>\nbody line\n</details>';
    const opened = '<details open>\n<summary>제목</summary>\nbody line\n</details>';

    String joined(TextSpan span) => _flatten(span).map((e) => e.$1).join();

    testWidgets('invariant: 닫힘/펼침/활성 모두 문자 보존', (tester) async {
      expect(joined(await _build(tester, closed)), closed);
      expect(joined(await _build(tester, opened)), opened);
      expect(
        joined(await _build(tester, closed,
            focused: true,
            selection: const TextSelection.collapsed(offset: 12))),
        closed,
      ); // summary 줄 활성
    });

    testWidgets('태그 줄은 inactive에서 투명 처리된다 (높이 유지)', (tester) async {
      final span = await _build(tester, closed);
      final style = _styleOf(span, '<details>');
      expect(style!.color, Colors.transparent);
      // 폰트 크기는 유지 — 높이 접기가 아니라 fence 줄과 같은 숨김이다.
      expect(style.fontSize ?? 100, greaterThan(1));
    });

    testWidgets('본문 줄은 열림/닫힘 무관하게 일반 렌더링된다', (tester) async {
      for (final text in [closed, opened]) {
        final span = await _build(tester, text);
        final style = _styleOf(span, 'body line');
        expect(style?.color, isNot(Colors.transparent));
      }
    });

    testWidgets('summary 제목은 semibold, 태그는 마커 처리된다', (tester) async {
      final span = await _build(tester, closed);
      expect(_styleOf(span, '제목')!.fontWeight, FontWeight.w600);
      // inactive에서 <summary> 마커는 폭 접힘(극소 폰트 + 투명)
      final marker = _styleOf(span, '<summary>');
      expect(marker!.color, Colors.transparent);
    });
  });
```

- [ ] **Step 2: 실패 확인** → FAIL

- [ ] **Step 3: 컨트롤러 구현**

`markdown_editing_controller.dart`:

1. `buildTextSpan`의 테이블 precompute(`:106-113`) 아래에 추가:

```dart
    // <details> 블록: 태그 줄은 구조 노이즈로 숨기고(높이 유지), summary는
    // 제목으로 강조한다. 본문은 항상 표시한다 — 접힘 상태(open 속성)는 파일
    // 포맷/GitHub 웹 렌더링용이고 에디터 내 높이 접기는 하지 않는다
    // (스트럿 floor 제거가 미러 페인터 정렬을 깨는 것이 실측으로 확인됨).
    final detailsTagStarts = <int>{};
    final detailsSummaryStarts = <int>{};
    for (final d in findDetailsRegions(text)) {
      detailsTagStarts.add(d.detailsLineRange.start);
      detailsTagStarts.add(d.closeLineRange.start);
      detailsSummaryStarts.add(d.summaryLineRange.start);
    }
```

2. 메인 루프 분기(`:127-149`)의 `_styleLine` 폴백 앞에 두 분기 추가 (테이블 분기 다음):

```dart
      } else if (detailsTagStarts.contains(lineStart)) {
        spans.add(TextSpan(text: line, style: _hideKeepHeight(base, c, active)));
      } else if (detailsSummaryStarts.contains(lineStart)) {
        spans.addAll(_summarySpans(line, base, c, active));
      } else {
```

3. 헬퍼 추가 (`_hideKeepHeight` 아래):

```dart
  static final RegExp _summaryLine =
      RegExp(r'^(\s*<summary>)(.*)(</summary>\s*)$');

  /// <summary>제목</summary> 줄: 태그는 마커로 접고 제목은 강조한다.
  List<InlineSpan> _summarySpans(
      String line, TextStyle base, AppColorsExtension c, bool active) {
    final m = _summaryLine.firstMatch(line);
    if (m == null) return _styleLine(line, base, c, active);
    final titleStyle = base.copyWith(fontWeight: FontWeight.w600);
    return [
      TextSpan(text: m.group(1)!, style: _marker(base, c, active)),
      ..._styleInline(m.group(2)!, titleStyle, c, active),
      TextSpan(text: m.group(3)!, style: _marker(base, c, active)),
    ];
  }
```

`import '../services/markdown_editing.dart'`는 이미 있다 (`findDetailsRegions` 사용 가능).

- [ ] **Step 4: 통과 확인** → `flutter test test/widgets/ test/services/` 전체 PASS

- [ ] **Step 5: 커밋**

```bash
git add desktop/lib/widgets/ desktop/test/widgets/
git commit -m "feat: details 블록 인라인 렌더링 (태그 숨김 + summary 강조)"
```

---

## Task 7: `> ` 입력 트리거 + 토글 오버레이

**Files:**
- Modify: `desktop/lib/services/markdown_editing.dart` (`DetailsBlockInputFormatter` 추가)
- Modify: `desktop/lib/widgets/editor_block_decorations.dart` (`measureRanges` 추가)
- Modify: `desktop/lib/widgets/editor_panel.dart` (formatter 등록, chevron 오버레이, `_toggleDetailsOpen`)
- Test: `desktop/test/services/markdown_editing_test.dart`, `desktop/test/widgets/editor_panel_details_test.dart` (신규)

**Interfaces:**
- Produces:
  - `class DetailsBlockInputFormatter extends TextInputFormatter`
  - `measureRanges(InlineSpan span, List<({int start, int end})> ranges, StrutStyle strutStyle, TextScaler textScaler, double width) → List<({int index, double top, double bottom})>` — Task 13(이미지 오버레이)도 재사용

- [ ] **Step 1: 실패하는 테스트 작성**

`markdown_editing_test.dart`에 추가:

```dart
  group('DetailsBlockInputFormatter', () {
    TextEditingValue apply(String oldText, int cursor, String typed) {
      final oldValue = TextEditingValue(
        text: oldText,
        selection: TextSelection.collapsed(offset: cursor),
      );
      final newText = oldText.replaceRange(cursor, cursor, typed);
      final newValue = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: cursor + typed.length),
      );
      return DetailsBlockInputFormatter().formatEditUpdate(oldValue, newValue);
    }

    test('줄 시작 "> " 입력이 details 스켈레톤으로 바뀐다', () {
      final result = apply('>', 1, ' ');
      expect(result.text, '<details>\n<summary></summary>\n\n</details>');
      expect(result.selection.baseOffset, '<details>\n<summary>'.length);
    });

    test('앞 줄이 있어도 동작한다', () {
      final result = apply('line1\n>', 7, ' ');
      expect(result.text, 'line1\n<details>\n<summary></summary>\n\n</details>');
    });

    test('줄 중간의 "> "는 건드리지 않는다', () {
      final result = apply('a >', 3, ' ');
      expect(result.text, 'a > ');
    });

    test('붙여넣기(여러 글자 삽입)는 건드리지 않는다', () {
      final oldValue = const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
      const newValue = TextEditingValue(
        text: '> ',
        selection: TextSelection.collapsed(offset: 2),
      );
      final result = DetailsBlockInputFormatter().formatEditUpdate(oldValue, newValue);
      expect(result.text, '> ');
    });
  });
```

`editor_panel_details_test.dart` (신규):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/theme/app_theme.dart';
import 'package:simsync/widgets/editor_panel.dart';

void main() {
  Note note(String content) {
    final now = DateTime(2026, 7, 19);
    return Note(
      id: 'n1', noteDate: now, title: 't', content: content,
      isDefault: true, tags: [], createdAt: now, updatedAt: now,
    );
  }

  testWidgets('chevron 토글이 open 속성을 파일 텍스트에 쓴다', (tester) async {
    Note? saved;
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: EditorPanel(
          note: note('<details>\n<summary>t</summary>\nbody\n</details>'),
          onNoteChanged: (n) => saved = n,
        ),
      ),
    ));
    await tester.pump();
    // chevron 아이콘(접힘 상태 = 오른쪽 화살표)을 찾아 탭
    final chevron = find.byIcon(Icons.chevron_right_rounded);
    expect(chevron, findsOneWidget);
    await tester.tap(chevron);
    // 자동 저장 디바운스(1초) 경과
    await tester.pump(const Duration(seconds: 2));
    expect(saved, isNotNull);
    expect(saved!.content, contains('<details open>'));
  });
}
```

- [ ] **Step 2: 실패 확인** → FAIL

- [ ] **Step 3: DetailsBlockInputFormatter 구현**

`markdown_editing.dart`의 details 섹션에 추가:

```dart
/// 줄 시작에서 `> `를 입력하면 <details> 스켈레톤으로 바꾼다. 인용문의 새
/// 문법은 `| `이므로 `>`는 details 생성 트리거로만 쓰인다. 이미 저장된
/// `> ` 줄(레거시 인용문)은 건드리지 않는다 — 새로 타이핑되는 경우만 반응.
class DetailsBlockInputFormatter extends TextInputFormatter {
  static const skeleton = '<details>\n<summary></summary>\n\n</details>';
  static final int _caretOffset = '<details>\n<summary>'.length;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final sel = newValue.selection;
    if (!sel.isValid || !sel.isCollapsed) return newValue;
    // 한 글자 삽입만 반응 (붙여넣기/IME 조합 제외).
    if (newValue.text.length != oldValue.text.length + 1) return newValue;
    final cursor = sel.baseOffset;
    final lineStart = _lineStartOf(newValue.text, cursor);
    final lineEnd = _lineEndOf(newValue.text, cursor);
    if (cursor != lineEnd) return newValue;
    if (newValue.text.substring(lineStart, lineEnd) != '> ') return newValue;

    final text = newValue.text.replaceRange(lineStart, lineEnd, skeleton);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: lineStart + _caretOffset),
    );
  }
}
```

`editor_panel.dart:625-626` formatter 등록:

```dart
      inputFormatters: widget.isReadOnly
          ? null
          : [MarkdownListInputFormatter(), DetailsBlockInputFormatter()],
```

- [ ] **Step 4: measureRanges + chevron 오버레이 구현**

`editor_block_decorations.dart`의 `measureTableRegions` 아래에 추가:

```dart
/// 임의 문자 범위 목록의 세로 구간(top..bottom, 스크롤 전 텍스트 좌표)을
/// 측정한다. details chevron과 인라인 이미지 오버레이 배치에 쓰인다.
List<({int index, double top, double bottom})> measureRanges(
  InlineSpan span,
  List<({int start, int end})> ranges,
  StrutStyle strutStyle,
  TextScaler textScaler,
  double width,
) {
  if (ranges.isEmpty || width <= 0) return const [];
  final painter = TextPainter(
    text: span,
    textDirection: TextDirection.ltr,
    strutStyle: strutStyle,
    textScaler: textScaler,
  )..layout(maxWidth: math.max(0, width - 3.0)); // matches the field's caret gap
  final out = <({int index, double top, double bottom})>[];
  for (var i = 0; i < ranges.length; i++) {
    final ext = boxSpanForRange(painter, ranges[i].start, ranges[i].end);
    if (ext != null) {
      out.add((index: i, top: ext.top, bottom: ext.bottom));
    }
  }
  painter.dispose();
  return out;
}
```

`editor_panel.dart` `_buildEditor`의 Stack(테이블 오버레이 다음)에 추가:

```dart
        // details 접기/펼치기 chevron — summary 줄 오른쪽 끝에 겹친다.
        Positioned.fill(
          child: _buildDetailsToggles(c, bodyStyle, strut, textScaler),
        ),
```

메서드 추가 (`_buildTableOverlays` 아래):

```dart
  Widget _buildDetailsToggles(
    AppColorsExtension c,
    TextStyle bodyStyle,
    StrutStyle strut,
    TextScaler textScaler,
  ) {
    return ListenableBuilder(
      listenable:
          Listenable.merge([_contentController, _contentScrollController]),
      builder: (context, _) {
        final details = findDetailsRegions(_contentController.text);
        if (details.isEmpty) return const SizedBox.shrink();
        return LayoutBuilder(
          builder: (context, constraints) {
            final span = _contentController.buildTextSpan(
                context: context, style: bodyStyle, withComposing: false);
            final measured = measureRanges(
                span,
                [for (final d in details) d.summaryLineRange],
                strut,
                textScaler,
                constraints.maxWidth);
            final scrollY = _contentScrollController.hasClients
                ? _contentScrollController.offset
                : 0.0;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                for (final m in measured)
                  Positioned(
                    right: 0,
                    top: m.top - scrollY,
                    height: m.bottom - m.top,
                    child: _DetailsToggleButton(
                      open: details[m.index].open,
                      onTap: widget.isReadOnly
                          ? null
                          : () => _toggleDetailsOpen(details[m.index]),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  /// <details> ↔ <details open> 토글. 펼침 상태가 파일에 저장되어 GitHub
  /// 웹/다른 디바이스와 공유된다.
  void _toggleDetailsOpen(DetailsRegion d) {
    if (widget.isReadOnly || widget.note == null) return;
    final text = _contentController.text;
    final line =
        text.substring(d.detailsLineRange.start, d.detailsLineRange.end);
    final newLine = d.open
        ? line.replaceFirst('<details open>', '<details>')
        : line.replaceFirst('<details>', '<details open>');
    if (newLine == line) return;
    final selection = _contentController.selection;
    final newText = text.replaceRange(
        d.detailsLineRange.start, d.detailsLineRange.end, newLine);
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: (selection.isValid ? selection.baseOffset : d.start)
            .clamp(0, newText.length),
      ),
    );
    _onContentChanged();
  }
```

파일 하단에 위젯 추가 (`_ToolbarIconButton` 아래):

```dart
/// details 블록 summary 줄 오른쪽의 접기/펼치기 버튼.
class _DetailsToggleButton extends StatelessWidget {
  final bool open;
  final VoidCallback? onTap;

  const _DetailsToggleButton({required this.open, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(
            open ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
            size: 18,
            color: c.textMuted,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: 통과 확인**

Run: `flutter test test/services/markdown_editing_test.dart test/widgets/editor_panel_details_test.dart && flutter test`
Expected: 전체 PASS

- [ ] **Step 6: 커밋**

```bash
git add desktop/lib/ desktop/test/
git commit -m "feat: details 입력 트리거(> )와 접기 토글 오버레이"
```

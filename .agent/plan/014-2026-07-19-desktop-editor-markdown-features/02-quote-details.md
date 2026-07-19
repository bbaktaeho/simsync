---
title: 인용문 | + details 접기 구현 (Task 3-7)
description: 극소 스트럿 전환, | 인용문, details 파싱/렌더링/토글/입력 트리거
type: plan
created: 2026-07-19
---

# 인용문 `|` + details 접기 (Task 3-7)

## 핵심 제약: 줄 높이 접기와 스트럿

에디터의 TextField는 `StrutStyle.fromTextStyle(bodyStyle)`을 쓰고 있어(`editor_panel.dart:616`) 모든 줄에 본문 높이의 최소값(floor)이 걸린다. 극소 폰트(0.1)로 줄여도 줄 높이는 그대로다 — 테이블 구분선 줄이 여전히 한 줄 높이를 차지하고 InlineTableView가 "남는 공간을 나눠 흡수"하는 이유가 이것이다(`markdown_editing_controller.dart:101-105` 주석).

details 본문을 실제로 접으려면(높이 0), 그리고 이미지 줄 높이를 자유롭게 예약하려면(04 문서) 이 floor를 없애야 한다. **Task 3에서 field + painter + 측정 함수 전부를 극소 명시 스트럿 `StrutStyle(fontSize: 0.1, height: 1, leading: 0)`으로 통일한다.** 양쪽이 같은 값을 쓰는 한 정렬(파서/오버레이 좌표)은 유지된다.

> **왜 `StrutStyle.disabled`가 아닌가 (2026-07-19 스파이크 실측):** EditableText는 전달받은 strut에 `inheritFromTextStyle(widget.style)`을 적용해 null인 fontSize를 본문 폰트(16)로 채운다. `StrutStyle.disabled`(fontSize null, height 0)는 이 경로에서 fontSize 16 + height 0이 되고, 엔진은 height 0을 "폰트 자연 높이 사용"으로 해석해 줄당 16px floor가 남는다 (TextField 실측: 숨김 줄당 16px). 반면 fontSize를 0.1로 명시한 스트럿은 상속으로 덮이지 않아 floor가 ~0.1px이 된다 (실측: 숨김 2줄 추가 시 +0px, 일반/빈 줄 높이 불변). 순수 TextPainter에서는 disabled도 동작하지만 field와 painter가 서로 다른 유효 스트럿을 가지면 정렬이 깨지므로, 양쪽 다 극소 명시 스트럿을 쓴다.

- 기대 효과: 극소 폰트 줄이 ~0 높이로 접힘. 일반 줄은 자기 폰트 크기로 높이가 정해지므로 변화 없음. 빈 줄은 그 줄을 끝내는 `\n` 문자가 base 스타일이므로 변화 없음. 테이블 구분선 줄이 실제로 접혀 테이블 밴드가 오히려 정확해짐.
- 위험: 캐럿 높이/줄 정렬 회귀 가능성. Task 3에 TextField 실측 테스트를 두고, Task 15 수동 검증에 빈 노트 캐럿/테이블/코드 박스 확인 항목이 있다.
- **폴백**: 만약 실기기에서 캐럿/정렬 회귀가 발견되면 스트럿을 되돌리고, details 접기를 "본문 투명 처리(높이는 유지)"로 낮춘 뒤 소유자와 협의한다. 이 결정은 계획 변경이므로 반드시 보고한다.

---

## Task 3: 극소 스트럿 전환

**Files:**
- Modify: `desktop/lib/widgets/editor_panel.dart:616`
- Test: `desktop/test/widgets/editor_strut_test.dart` (신규)

**Interfaces:**
- Produces: 에디터 전역에서 극소 폰트 줄의 높이가 실제로 접히는 성질. Task 6(접기), Task 12(이미지 높이 예약)가 의존

- [ ] **Step 1: 검증 테스트 작성 (TextField 실측)**

`desktop/test/widgets/editor_strut_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 극소 명시 스트럿(fontSize 0.1) 정책 검증 — 에디터 접기(details)와 이미지
/// 높이 예약의 전제 조건이다. 실제 TextField(EditableText)로 측정한다:
/// EditableText는 strut에 inheritFromTextStyle을 적용하므로 순수 TextPainter
/// 측정만으로는 부족하다 (StrutStyle.disabled는 fontSize가 16으로 채워져
/// 줄당 16px floor가 남는 것이 실측으로 확인됨).
class _TinyLineController extends TextEditingController {
  _TinyLineController(String text) : super(text: text);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle(fontSize: 16, height: 1.5);
    final lines = text.split('\n');
    final spans = <TextSpan>[];
    for (var i = 0; i < lines.length; i++) {
      final tiny = lines[i].startsWith('HIDE');
      final lineStyle = tiny
          ? base.copyWith(fontSize: 0.1, height: 1.0, color: Colors.transparent)
          : base;
      spans.add(TextSpan(text: lines[i], style: lineStyle));
      if (i < lines.length - 1) {
        spans.add(TextSpan(text: '\n', style: lineStyle));
      }
    }
    return TextSpan(style: base, children: spans);
  }
}

/// 에디터가 쓰는 극소 스트럿과 같은 값 (editor_panel.dart와 일치해야 한다).
const _tinyStrut = StrutStyle(fontSize: 0.1, height: 1, leading: 0);

Future<double> _fieldHeight(WidgetTester tester, String text) async {
  const style = TextStyle(fontSize: 16, height: 1.5);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          child: TextField(
            controller: _TinyLineController(text),
            maxLines: null,
            style: style,
            strutStyle: _tinyStrut,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              isDense: true,
            ),
          ),
        ),
      ),
    ),
  ));
  return tester.getSize(find.byType(EditableText)).height;
}

void main() {
  testWidgets('극소 폰트 줄은 TextField에서 ~0 높이로 접힌다', (tester) async {
    final plain = await _fieldHeight(tester, 'one\ntwo');
    final withHidden = await _fieldHeight(tester, 'one\nHIDE a\nHIDE b\ntwo');
    expect(withHidden - plain, lessThan(1.5), reason: '숨김 줄 2개가 1px 미만');
  });

  testWidgets('일반 줄과 빈 줄 높이는 불변이다', (tester) async {
    final plain = await _fieldHeight(tester, 'one\ntwo');
    final withEmpty = await _fieldHeight(tester, 'one\n\ntwo');
    expect(plain, 48.0); // 16 * 1.5 * 2줄
    expect(withEmpty - plain, closeTo(24.0, 0.5), reason: '빈 줄은 정상 높이 유지');
  });

  testWidgets('큰 첫 글자는 그 줄 높이를 예약한다 (이미지 높이 예약의 원리)',
      (tester) async {
    // TextPainter 검증으로 충분 (스트럿은 min만 제공, 큰 글자는 위로 키운다).
    const base = TextStyle(fontSize: 16, height: 1.5);
    final span = TextSpan(style: base, children: [
      TextSpan(text: '<', style: base.copyWith(fontSize: 200, height: 1.0)),
      TextSpan(
          text: 'img>\n',
          style: base.copyWith(fontSize: 0.1, height: 1.0)),
      const TextSpan(text: 'after', style: base),
    ]);
    final painter = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      strutStyle: _tinyStrut,
    )..layout(maxWidth: 500);
    final metrics = painter.computeLineMetrics();
    expect(metrics.first.height, closeTo(200, 1));
    painter.dispose();
  });
}
```

- [ ] **Step 2: 테스트 실행 (성질 확인)**

Run: `cd desktop && flutter test test/widgets/editor_strut_test.dart`
Expected: PASS — Flutter 성질 검증이므로 바로 통과해야 정상 (2026-07-19 스파이크로 사전 확인됨). **FAIL이면 즉시 멈추고 BLOCKED 보고.**

- [ ] **Step 3: 에디터 스트럿 교체**

`editor_panel.dart` `_buildEditor`에서:

```dart
    // The decoration painter lays out an identical TextPainter, so the field and
    // the painter must share strut + text scaler + width for the boxes to align.
    // The strut mirrors the body style so the caret lines up with the text.
    final strut = StrutStyle.fromTextStyle(bodyStyle, forceStrutHeight: false);
```

를 다음으로 교체:

```dart
    // The decoration painter lays out an identical TextPainter, so the field and
    // the painter must share strut + text scaler + width for the boxes to align.
    // The strut is a near-zero explicit minimum (NOT StrutStyle.disabled:
    // EditableText inherits a null strut fontSize from the body style, which
    // resurrects a per-line floor). With no meaningful floor, collapsed lines
    // (details body, table separator) shrink to ~0 and image lines can reserve
    // their own height via a tall first glyph. Normal lines size from their font.
    const strut = StrutStyle(fontSize: 0.1, height: 1, leading: 0);
```

`strut`은 이후 코드에서 field/painter/measure에 그대로 전달되고 있으므로 다른 수정은 없다.

- [ ] **Step 4: 회귀 확인**

Run: `flutter test test/widgets/`
Expected: 전체 PASS. 특히 `editor_panel_inline_test.dart`, `editor_block_decorations_test.dart`, `markdown_editing_controller_test.dart`

- [ ] **Step 5: 커밋**

```bash
git add desktop/lib/widgets/editor_panel.dart desktop/test/widgets/editor_strut_test.dart
git commit -m "refactor: 에디터 스트럿을 극소 명시 스트럿으로 전환 — 줄 높이 접기/예약 기반"
```

---

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

## Task 6: details 렌더링 (접힘/펼침)

**Files:**
- Modify: `desktop/lib/widgets/markdown_editing_controller.dart` (`buildTextSpan` 분기 + 헬퍼)
- Modify: `desktop/lib/widgets/editor_block_decorations.dart` (`filterEditorRegions` 3-인자 확장)
- Modify: `desktop/lib/widgets/editor_panel.dart` (필터 호출부, 접힌 블록 안 테이블 오버레이 제외)
- Test: `desktop/test/widgets/markdown_editing_controller_test.dart` (추가)

**Interfaces:**
- Consumes: Task 5 `findDetailsRegions`, Task 3 스트럿 성질
- Produces: `filterEditorRegions(regions, tables, details)` 3-인자 시그니처 (Task 4의 2-인자를 대체)

렌더링 규칙:
- `<details>` / `</details>` 태그 줄: 캐럿이 그 줄에 있으면 dim 노출(편집/삭제 가능), 아니면 높이까지 접기
- `<summary>제목</summary>` 줄: 마커는 `_marker`(inactive 시 접힘), 제목은 semibold + 인라인 스타일
- 닫힌 블록의 본문 줄: 항상 높이까지 접기 (`fontSize 0.1` + 투명 — Task 3 덕에 실제 접힘). 해당 줄을 끝내는 `\n`도 같이 접는다
- 열린 블록의 본문 줄: 일반 파이프라인(`_styleLine` 등)으로 렌더링

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

    testWidgets('닫힌 본문 줄은 극소 폰트로 접힌다', (tester) async {
      final span = await _build(tester, closed);
      final style = _styleOf(span, 'body line');
      expect(style!.fontSize, lessThan(1));
      expect(style.color, Colors.transparent);
    });

    testWidgets('열린 본문 줄은 접히지 않는다', (tester) async {
      final span = await _build(tester, opened);
      final style = _styleOf(span, 'body line');
      expect(style?.fontSize ?? 100, isNot(lessThan(1)));
    });

    testWidgets('summary 제목은 semibold로 렌더링된다', (tester) async {
      final span = await _build(tester, closed);
      expect(_styleOf(span, '제목')!.fontWeight, FontWeight.w600);
    });
  });
```

- [ ] **Step 2: 실패 확인** → FAIL

- [ ] **Step 3: 컨트롤러 구현**

`markdown_editing_controller.dart`:

1. `buildTextSpan`의 테이블 precompute(`:106-113`) 아래에 추가:

```dart
    // <details> 블록: 태그 줄은 구조 노이즈로 접고, 닫힌 블록의 본문 줄은
    // 높이까지 접는다(스트럿 비활성이라 극소 폰트가 실제로 접힌다).
    final detailsTagStarts = <int>{};
    final detailsCollapsedStarts = <int>{};
    final detailsSummaryStarts = <int>{};
    for (final d in findDetailsRegions(text)) {
      detailsTagStarts.add(d.detailsLineRange.start);
      detailsTagStarts.add(d.closeLineRange.start);
      detailsSummaryStarts.add(d.summaryLineRange.start);
      if (!d.open) {
        for (final r in d.bodyLineRanges) {
          detailsCollapsedStarts.add(r.start);
        }
      }
    }
```

2. 메인 루프 분기(`:127-149`)를 다음 순서로 재구성 (fence 상태 추적은 그대로 유지; 본문에 fence가 있는 블록은 파서가 이미 무시하므로 collapsed 줄과 fence 줄은 겹치지 않는다):

```dart
      if (_fence.hasMatch(line)) {
        // (기존 그대로)
      } else if (inFence) {
        // (기존 그대로)
      } else if (detailsCollapsedStarts.contains(lineStart)) {
        spans.add(TextSpan(text: line, style: _collapsed(base)));
      } else if (tableSepStarts.contains(lineStart)) {
        // (기존 그대로)
      } else if (tableRowStarts.contains(lineStart)) {
        // (기존 그대로)
      } else if (detailsTagStarts.contains(lineStart)) {
        spans.add(TextSpan(
            text: line,
            style: active ? base.copyWith(color: c.textMuted) : _collapsed(base)));
      } else if (detailsSummaryStarts.contains(lineStart)) {
        spans.addAll(_summarySpans(line, base, c, active));
      } else {
        spans.addAll(_styleLine(line, base, c, active));
      }
```

3. 줄바꿈 스팬(`:151-153`)을 접힘 인지형으로 교체:

```dart
      if (i < lines.length - 1) {
        final collapseNewline = detailsCollapsedStarts.contains(lineStart) ||
            (detailsTagStarts.contains(lineStart) && !active);
        spans.add(
            TextSpan(text: '\n', style: collapseNewline ? _collapsed(base) : base));
      }
```

4. 헬퍼 추가 (`_hideKeepHeight` 아래):

```dart
  /// 줄을 높이까지 접는다(투명 + 극소 폰트). 스트럿이 비활성이라 라인 박스가
  /// 실제로 ~0 높이로 줄어든다. 문자는 남으므로 invariant는 유지된다.
  TextStyle _collapsed(TextStyle base) => base.copyWith(
      fontSize: 0.1, height: 1.0, letterSpacing: 0, color: Colors.transparent);

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

- [ ] **Step 4: 데코/오버레이 충돌 필터**

`editor_block_decorations.dart`의 `filterEditorRegions`를 3-인자로 확장 (Task 4 버전 대체). **Task 4에서 작성한 2-인자 호출 테스트들도 세 번째 인자로 `findDetailsRegions(text)` 혹은 `const []`를 넘기도록 함께 갱신한다.**

```dart
import '../services/markdown_editing.dart'; // 이미 있음 (TableRegion)

/// 데코레이션 영역 후처리: 테이블과 겹치는 quote 바, 테이블 구분선의 rule 선,
/// 닫힌 details 본문에 들어간 rule/quote 장식을 제거한다.
List<EditorBlockRegion> filterEditorRegions(
  List<EditorBlockRegion> regions,
  List<TableRegion> tables,
  List<DetailsRegion> details,
) {
  if (regions.isEmpty) return regions;
  final sepStarts = {for (final t in tables) t.separatorRange.start};
  bool inClosedDetails(EditorBlockRegion r) => details.any(
      (d) => !d.open && r.start >= d.start && r.end <= d.end);
  return regions.where((r) {
    if (r.kind == EditorBlockKind.rule && sepStarts.contains(r.start)) {
      return false;
    }
    if (r.kind == EditorBlockKind.quote &&
        tables.any((t) => r.start <= t.end && r.end >= t.start)) {
      return false;
    }
    if ((r.kind == EditorBlockKind.rule || r.kind == EditorBlockKind.quote) &&
        inClosedDetails(r)) {
      return false;
    }
    return true;
  }).toList();
}
```

`editor_panel.dart` 데코 빌더 호출부 갱신:

```dart
                final allRegions =
                    parseEditorBlockRegions(_contentController.text);
                final tables = findTableRegions(_contentController.text);
                final details = findDetailsRegions(_contentController.text);
                final regions = filterEditorRegions(allRegions, tables, details);
```

`_buildTableOverlays`(`editor_panel.dart:713`)에서 닫힌 details 안의 테이블은 오버레이를 만들지 않도록 필터 추가 (`final tables = findTableRegions(...)` 직후):

```dart
        final details = findDetailsRegions(_contentController.text);
        final visibleTables = tables
            .where((t) => !details.any(
                (d) => !d.open && t.start >= d.start && t.end <= d.end))
            .toList();
        if (visibleTables.isEmpty) return const SizedBox.shrink();
```

이후 루프는 `visibleTables` 사용. 단, 컨트롤러의 `tableRowStarts` 투명 처리보다 `detailsCollapsedStarts` 접기가 먼저 오도록 위 분기 순서가 이미 보장한다 (닫힌 본문 안 테이블 줄은 접힌다).

- [ ] **Step 5: 통과 확인** → `flutter test test/widgets/ test/services/` 전체 PASS

- [ ] **Step 6: 커밋**

```bash
git add desktop/lib/widgets/ desktop/test/widgets/
git commit -m "feat: details 블록 인라인 렌더링 (접힘/펼침, 충돌 필터)"
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

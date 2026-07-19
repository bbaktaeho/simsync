---
title: 코드 언어 자동 감지 구현 (Task 8)
description: 언어 미지정 fence 블록의 highlight auto-detection + 캐시
type: plan
created: 2026-07-19
---

# 코드 언어 자동 감지 (Task 8)

배경: fence 하이라이팅은 `markdown_editing_controller.dart`의 `_codeSpans`(`:344-391`)가 줄 단위로 수행하고 언어는 `_parseFenceLang`(`:393`)이 fence 여는 줄에서 읽는다. 언어 미지정 시 `'plaintext'`로 무채색이 된다.

전략: 언어가 없으면 블록 전체 내용으로 `highlight.parse(..., autoDetection: true)`를 1회 실행해 언어를 정한다. auto-detection은 등록된 모든 언어를 시도해서 비싸므로:

- 결과를 블록 내용 문자열 키로 캐시한다 (bounded).
- **캐럿이 블록 안에 있는 동안(타이핑 중)은 감지를 미루고** 직전 결과(sticky)를 유지한다. 캐럿이 블록을 벗어나는 순간 감지된다 (Obsidian류 UX).
- 신뢰도(`relevance`)가 5 미만이면 무채색을 유지한다 (오탐 방지).

주의: `highlight` 0.7의 `parse` API에 `autoDetection` 파라미터가 있는지 구현 시점에 시그니처를 확인한다 (`~/.pub-cache` 소스 확인). 없으면 이 task를 중단하고 보고한다 — 다른 방식(전 언어 순회)은 성능상 도입하지 않는다.

---

## Task 8: 자동 감지 + 캐시

**Files:**
- Modify: `desktop/lib/widgets/markdown_editing_controller.dart`
- Test: `desktop/test/widgets/markdown_editing_controller_test.dart` (추가)

**Interfaces:**
- Produces: `static String? MarkdownEditingController.detectFenceLanguage(String blockText)` (테스트 가능한 순수 함수)

- [ ] **Step 1: 실패하는 테스트 작성**

`markdown_editing_controller_test.dart`에 추가:

```dart
  group('detectFenceLanguage', () {
    test('명백한 JSON을 감지한다', () {
      const block = '{\n  "name": "simsync",\n  "count": 3,\n  "ok": true\n}';
      expect(MarkdownEditingController.detectFenceLanguage(block), isNotNull);
    });

    test('명백한 Dart/유사 코드를 감지한다', () {
      const block = '''
void main() {
  final list = <int>[1, 2, 3];
  for (final v in list) {
    print(v);
  }
}''';
      expect(MarkdownEditingController.detectFenceLanguage(block), isNotNull);
    });

    test('평범한 산문은 감지하지 않는다 (낮은 relevance)', () {
      const block = '오늘은 날씨가 좋았다 그래서 산책을 했다';
      expect(MarkdownEditingController.detectFenceLanguage(block), isNull);
    });
  });
```

- [ ] **Step 2: 실패 확인** → `flutter test test/widgets/markdown_editing_controller_test.dart` FAIL (미정의)

- [ ] **Step 3: 구현**

`markdown_editing_controller.dart`:

1. 필드 추가 (`_highlightCache` 아래):

```dart
  /// 언어 미지정 fence 블록의 자동 감지 캐시 (블록 내용 → 감지 언어 또는 null).
  final Map<String, String?> _autoLangCache = {};
  static const int _autoLangCacheLimit = 100;

  /// 블록 시작 오프셋 → 직전 감지 언어. 캐럿이 블록 안에 있는 동안(내용이
  /// 계속 바뀌어 캐시 미스가 나는 동안) 전체 재감지 대신 직전 결과를 유지한다.
  final Map<int, String?> _stickyAutoLang = {};
```

2. 순수 감지 함수 추가 (클래스 안, static):

```dart
  /// 블록 전체 텍스트로 언어를 자동 감지한다. 신뢰도가 낮으면 null
  /// (무채색 유지). highlight의 auto-detection은 비싸므로 호출부에서 캐시한다.
  static String? detectFenceLanguage(String blockText) {
    try {
      final result = highlight.parse(blockText, autoDetection: true);
      if ((result.relevance ?? 0) < 5) return null;
      return result.language;
    } catch (_) {
      return null;
    }
  }
```

3. `buildTextSpan`에서 `final lines = text.split('\n');`(`:115`) 직후에 prepass 호출 추가:

```dart
    final autoLangByFence =
        _computeAutoLangs(lines, selStart, selEnd, hasActive);
```

4. 메인 루프의 fence 여는 분기(`:136-137`)를 다음으로 교체:

```dart
          inFence = true;
          fenceLang = _parseFenceLang(line);
          if (fenceLang == 'plaintext') {
            fenceLang = autoLangByFence[lineStart] ?? 'plaintext';
          }
```

5. prepass 메서드 추가:

```dart
  /// 언어 미지정 fence 블록마다 자동 감지 언어를 정한다.
  /// 반환: fence 여는 줄 시작 오프셋 → 언어.
  Map<int, String> _computeAutoLangs(
      List<String> lines, int selStart, int selEnd, bool hasActive) {
    final result = <int, String>{};
    var offset = 0;
    var inFence = false;
    var fenceStart = -1;
    var explicitLang = false;
    final content = StringBuffer();

    for (final line in lines) {
      final lineStart = offset;
      final lineEnd = offset + line.length;
      if (_fence.hasMatch(line)) {
        if (inFence) {
          if (!explicitLang && content.isNotEmpty) {
            // 캐럿이 블록(여는 fence..닫는 fence) 안이면 감지를 미룬다.
            final caretInside =
                hasActive && selStart <= lineEnd && selEnd >= fenceStart;
            final lang =
                _autoLang(content.toString(), fenceStart, caretInside);
            if (lang != null) result[fenceStart] = lang;
          }
          inFence = false;
        } else {
          inFence = true;
          fenceStart = lineStart;
          explicitLang = _parseFenceLang(line) != 'plaintext';
          content.clear();
        }
      } else if (inFence && !explicitLang) {
        if (content.isNotEmpty) content.write('\n');
        content.write(line);
      }
      offset = lineEnd + 1;
    }
    return result;
  }

  String? _autoLang(String blockText, int blockStart, bool caretInside) {
    if (_autoLangCache.containsKey(blockText)) {
      final cached = _autoLangCache[blockText];
      _stickyAutoLang[blockStart] = cached;
      return cached;
    }
    if (caretInside) return _stickyAutoLang[blockStart];
    final lang = detectFenceLanguage(blockText);
    if (_autoLangCache.length >= _autoLangCacheLimit) _autoLangCache.clear();
    _autoLangCache[blockText] = lang;
    _stickyAutoLang[blockStart] = lang;
    return lang;
  }
```

주의: `result.relevance`가 non-nullable int라면 `(result.relevance ?? 0)`에서 불필요한 null 병합 경고가 난다 — analyze 결과에 맞춰 `result.relevance < 5`로 조정한다.

- [ ] **Step 4: 통과 확인**

Run: `flutter test test/widgets/markdown_editing_controller_test.dart && flutter analyze`
Expected: PASS, 0 issues

- [ ] **Step 5: 커밋**

```bash
git add desktop/lib/widgets/markdown_editing_controller.dart desktop/test/widgets/markdown_editing_controller_test.dart
git commit -m "feat: 언어 미지정 코드 블록 자동 감지 하이라이팅"
```

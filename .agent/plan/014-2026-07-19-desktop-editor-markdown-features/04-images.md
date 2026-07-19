---
title: 이미지 첨부/뷰어 구현 (Task 9-14)
description: 바이너리 스토리지 API, ImageAssetService, 인라인 이미지 렌더링/리사이즈, 붙여넣기/첨부
type: plan
created: 2026-07-19
---

# 이미지 첨부/뷰어 (Task 9-14)

저장 문법: `<img src="assets/img-{일시}-{난수4}.{ext}" width="300" height="200">` (한 줄, GitHub 웹에서 크기 그대로 렌더링). 이미지 파일은 노트의 날짜 디렉토리 하위 `assets/`에 저장한다. **파일명이 유일하므로 캐시 무효화가 필요 없다** (이미지는 불변).

렌더링: 테이블 오버레이 패턴. img 태그 줄은 항상 투명 처리하되 첫 글자에 큰 fontSize를 줘 줄 높이를 이미지 표시 높이만큼 예약한다(Task 3 스트럿 비활성이 전제). 태그가 편집으로 깨지면 정규식 매칭이 풀려 원문 텍스트가 그대로 드러난다(자가 복구). width와 height를 둘 다 저장하는 이유: 이미지 바이트를 받기 전에 줄 높이를 예약해야 하기 때문.

---

## Task 9: NoteStorage bytes API + 로컬 2종 구현

**Files:**
- Modify: `desktop/lib/storage/note_storage.dart`
- Modify: `desktop/lib/services/note_service.dart`
- Modify: `desktop/lib/storage/local/local_note_storage.dart`
- Test: `desktop/test/storage/note_storage_binary_test.dart` (신규)

**Interfaces:**
- Produces (인터페이스 — 이후 task 전부가 사용):
  - `Future<Uint8List?> readBinaryFile(String relativePath)` — 없으면 null
  - `Future<void> writeBinaryFile(String relativePath, Uint8List bytes)` — 부모 디렉토리 생성 포함
  - `String noteDirPath(DateTime noteDate)` — 해당 날짜 노트가 사는 스토리지-상대 디렉토리 (NoteService: `2026-07-19`, LocalNoteStorage/GitHubNoteStorage: `notes/2026-07/19`)

- [ ] **Step 1: 실패하는 테스트 작성**

`desktop/test/storage/note_storage_binary_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/services/note_service.dart';
import 'package:simsync/storage/local/local_note_storage.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('simsync_bin_test');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  final bytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 255, 128, 7]);

  test('LocalNoteStorage: 바이너리 왕복 + noteDirPath', () async {
    final storage = LocalNoteStorage(basePath: tmp.path);
    expect(storage.noteDirPath(DateTime(2026, 7, 19)), 'notes/2026-07/19');
    const rel = 'notes/2026-07/19/assets/img-x.png';
    expect(await storage.readBinaryFile(rel), isNull);
    await storage.writeBinaryFile(rel, bytes);
    expect(await storage.readBinaryFile(rel), bytes);
  });

  test('NoteService: 바이너리 왕복 + noteDirPath', () async {
    final storage = NoteService.forTesting(tmp.path);
    expect(storage.noteDirPath(DateTime(2026, 7, 19)), '2026-07-19');
    const rel = '2026-07-19/assets/img-x.png';
    await storage.writeBinaryFile(rel, bytes);
    expect(await storage.readBinaryFile(rel), bytes);
  });
}
```

주의: `NoteService`는 현재 `~/.simsync/documents` 고정 factory뿐이다(`note_service.dart:35-39`). 테스트용 생성자 `NoteService.forTesting(String basePath)`를 추가한다 (기존 private `NoteService._` 위임).

- [ ] **Step 2: 실패 확인** → `flutter test test/storage/note_storage_binary_test.dart` FAIL

- [ ] **Step 3: 구현**

`note_storage.dart` — import와 메서드 3개 추가:

```dart
import 'dart:typed_data';

import '../models/note.dart';

abstract class NoteStorage {
  // ... 기존 메서드 유지 ...

  /// 저장소 루트 기준 [relativePath]의 바이너리 파일을 읽는다. 없으면 null.
  /// 노트 본문에 첨부된 이미지 자산 입출력용.
  Future<Uint8List?> readBinaryFile(String relativePath);

  /// 저장소 루트 기준 [relativePath]에 [bytes]를 쓴다(생성 또는 덮어쓰기).
  Future<void> writeBinaryFile(String relativePath, Uint8List bytes);

  /// [noteDate] 날짜의 노트 파일이 위치하는 스토리지-상대 디렉토리 경로.
  /// 노트 본문의 상대 src('assets/…')를 스토리지 경로로 해석할 때 쓴다.
  String noteDirPath(DateTime noteDate);
}
```

`note_service.dart` 추가:

```dart
  /// 테스트용: 임의 경로를 루트로 쓰는 NoteService.
  factory NoteService.forTesting(String basePath) => NoteService._(basePath);

  @override
  String noteDirPath(DateTime noteDate) => _dirDateFmt.format(noteDate);

  @override
  Future<Uint8List?> readBinaryFile(String relativePath) async {
    final file = File('$_basePath/$relativePath');
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> writeBinaryFile(String relativePath, Uint8List bytes) async {
    final file = File('$_basePath/$relativePath');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }
```

(`import 'dart:typed_data';` 추가)

`local_note_storage.dart` 추가:

```dart
  @override
  String noteDirPath(DateTime noteDate) {
    final yearMonth =
        '${noteDate.year}-${noteDate.month.toString().padLeft(2, '0')}';
    final day = noteDate.day.toString().padLeft(2, '0');
    return 'notes/$yearMonth/$day';
  }

  @override
  Future<Uint8List?> readBinaryFile(String relativePath) async {
    final file = File('$basePath/$relativePath');
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> writeBinaryFile(String relativePath, Uint8List bytes) async {
    final file = File('$basePath/$relativePath');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }
```

(`import 'dart:typed_data';` 추가)

이 시점에서 `GitHubNoteStorage`가 인터페이스 미구현으로 컴파일이 깨진다 — **Task 10과 같은 커밋으로 묶거나, Task 10을 바로 이어서 진행한 뒤 커밋한다.** (빌드 깨진 커밋 금지)

- [ ] **Step 4: Task 10 완료 후 함께 통과 확인/커밋** (아래)

---

## Task 10: GitHubApiClient + GitHubNoteStorage 바이너리

**Files:**
- Modify: `desktop/lib/storage/github/github_api_client.dart`
- Modify: `desktop/lib/storage/github/github_note_storage.dart`
- Test: `desktop/test/storage/github/github_binary_test.dart` (신규)

**Interfaces:**
- Consumes: Task 9 인터페이스
- Produces:
  - `GitHubApiClient.getRawFile(String path) → Future<Uint8List>` — raw media type으로 bodyBytes 반환 (1MB 초과 파일도 동작; base64 GET의 1MB 제한 회피)
  - `GitHubApiClient.putBinaryFile({required String path, required Uint8List bytes, required String message, String? sha}) → Future<String>` — bytes를 직접 base64 인코딩 (기존 putFile의 utf8 왕복 회피)

- [ ] **Step 1: 실패하는 테스트 작성**

`desktop/test/storage/github/github_binary_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simsync/storage/github/github_api_client.dart';

void main() {
  final bytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 255, 128, 7]);

  GitHubApiClient clientWith(MockClient mock) =>
      GitHubApiClient(token: 't', owner: 'o', repo: 'r', httpClient: mock);

  test('putBinaryFile은 raw bytes를 base64로 보낸다 (utf8 왕복 없음)', () async {
    late Map<String, dynamic> sentBody;
    final mock = MockClient((request) async {
      sentBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
          jsonEncode({'content': {'sha': 'newsha'}}), 201);
    });
    final sha = await clientWith(mock).putBinaryFile(
      path: 'notes/2026-07/19/assets/img.png',
      bytes: bytes,
      message: 'Add image',
    );
    expect(sha, 'newsha');
    expect(sentBody['content'], base64.encode(bytes));
  });

  test('getRawFile은 raw accept 헤더로 bodyBytes를 돌려준다', () async {
    late http.Request captured;
    final mock = MockClient((request) async {
      captured = request;
      return http.Response.bytes(bytes, 200);
    });
    final result =
        await clientWith(mock).getRawFile('notes/2026-07/19/assets/img.png');
    expect(result, bytes);
    expect(captured.headers['Accept'], contains('raw'));
  });

  test('getRawFile 404는 GitHubNotFoundException', () async {
    final mock = MockClient((request) async => http.Response('nf', 404));
    expect(
      () => clientWith(mock).getRawFile('x.png'),
      throwsA(isA<GitHubNotFoundException>()),
    );
  });

  test('putFile(텍스트)은 기존과 동일하게 utf8 base64를 보낸다 (회귀)', () async {
    late Map<String, dynamic> sentBody;
    final mock = MockClient((request) async {
      sentBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'content': {'sha': 's'}}), 200);
    });
    await clientWith(mock)
        .putFile(path: 'a.md', content: '한글 content', message: 'm', sha: 'old');
    expect(sentBody['content'], base64.encode(utf8.encode('한글 content')));
    expect(sentBody['sha'], 'old');
  });
}
```

- [ ] **Step 2: 실패 확인** → FAIL (메서드 미정의)

- [ ] **Step 3: GitHubApiClient 구현**

`github_api_client.dart`: import에 `dart:typed_data` 추가. `putFile`(`:167-201`)을 `putBinaryFile` 위임으로 교체:

```dart
  /// Creates or updates a file. Returns the new SHA.
  /// Pass [sha] to update an existing file; omit for creation.
  /// Throws [GitHubConflictException] on 409.
  Future<String> putFile({
    required String path,
    required String content,
    required String message,
    String? sha,
  }) {
    return putBinaryFile(
      path: path,
      bytes: Uint8List.fromList(utf8.encode(content)),
      message: message,
      sha: sha,
    );
  }

  /// Creates or updates a binary file (raw bytes, base64-encoded directly —
  /// no utf8 round-trip, so images survive intact). Returns the new SHA.
  Future<String> putBinaryFile({
    required String path,
    required Uint8List bytes,
    required String message,
    String? sha,
  }) async {
    final body = <String, dynamic>{
      'message': message,
      'content': base64.encode(bytes),
    };
    if (sha != null) {
      body['sha'] = sha;
    }

    final response = await _httpClient.put(
      _contentsUri(path),
      headers: {
        ..._headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 409) {
      throw GitHubConflictException(path);
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw GitHubApiException(response.statusCode, response.body);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final contentMap = json['content'] as Map<String, dynamic>;
    return contentMap['sha'] as String;
  }

  /// Fetches a file's raw bytes via the raw media type. Works past the 1MB
  /// base64 limit of the JSON contents response. Throws
  /// [GitHubNotFoundException] on 404.
  Future<Uint8List> getRawFile(String path) async {
    final response = await _httpClient.get(
      _contentsUri(path),
      headers: {
        ..._headers,
        'Accept': 'application/vnd.github.raw+json',
      },
    );

    if (response.statusCode == 404) {
      throw GitHubNotFoundException(path);
    }

    if (response.statusCode != 200) {
      throw GitHubApiException(response.statusCode, response.body);
    }

    return response.bodyBytes;
  }
```

- [ ] **Step 4: GitHubNoteStorage 구현**

`github_note_storage.dart`: import에 `dart:typed_data` 추가, NoteStorage 구현부에 추가:

```dart
  @override
  String noteDirPath(DateTime noteDate) => _dayDirPath(noteDate);

  @override
  Future<Uint8List?> readBinaryFile(String relativePath) async {
    try {
      return await _client.getRawFile(relativePath);
    } on GitHubNotFoundException {
      return null;
    }
  }

  @override
  Future<void> writeBinaryFile(String relativePath, Uint8List bytes) async {
    // 이미지 파일명은 유일해서 보통 신규 생성(sha 불필요)이다. 만약 같은
    // 경로가 이미 있으면 update를 위해 sha를 조회한다 (writeTextFile 패턴).
    String? sha;
    try {
      sha = (await _client.getFile(relativePath)).sha;
    } on GitHubNotFoundException {
      sha = null;
    }
    await _client.putBinaryFile(
      path: relativePath,
      bytes: bytes,
      message: 'Add asset: $relativePath',
      sha: sha,
    );
  }
```

- [ ] **Step 5: 통과 확인 + 커밋 (Task 9+10 묶음)**

Run: `flutter test test/storage/ && flutter analyze`
Expected: 신규 + 기존 storage 테스트 전체 PASS

```bash
git add desktop/lib/storage/ desktop/lib/services/note_service.dart desktop/test/storage/
git commit -m "feat: 스토리지 바이너리 API (로컬 파일/GitHub raw+base64)"
```

---

## Task 11: ImageAssetService

**Files:**
- Create: `desktop/lib/services/image_asset_service.dart`
- Test: `desktop/test/services/image_asset_service_test.dart` (신규)

**Interfaces:**
- Consumes: Task 9-10 `NoteStorage` bytes API
- Produces:
  - `ImageAssetService({required NoteStorage storage, bool useDiskCache = false})`
  - `Future<String> saveImage({required DateTime noteDate, required Uint8List bytes, required String extension})` — 반환값은 노트 파일 기준 상대 src (`assets/img-…`)
  - `Future<Uint8List?> loadImage({required DateTime noteDate, required String src})`

- [ ] **Step 1: 실패하는 테스트 작성**

`desktop/test/services/image_asset_service_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/services/image_asset_service.dart';
import 'package:simsync/storage/note_storage.dart';

/// 인메모리 NoteStorage — 바이너리 API만 실동작, 노트 API는 미사용.
class _FakeStorage implements NoteStorage {
  final Map<String, Uint8List> files = {};
  int reads = 0;

  @override
  String noteDirPath(DateTime noteDate) =>
      'notes/${noteDate.year}-${noteDate.month.toString().padLeft(2, '0')}/${noteDate.day.toString().padLeft(2, '0')}';

  @override
  Future<Uint8List?> readBinaryFile(String relativePath) async {
    reads++;
    return files[relativePath];
  }

  @override
  Future<void> writeBinaryFile(String relativePath, Uint8List bytes) async {
    files[relativePath] = bytes;
  }

  // 이하 미사용 멤버
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final bytes = Uint8List.fromList([1, 2, 3, 4]);
  final date = DateTime(2026, 7, 19);

  test('saveImage는 날짜 디렉토리 assets/에 쓰고 상대 src를 돌려준다', () async {
    final storage = _FakeStorage();
    final service = ImageAssetService(storage: storage);
    final src = await service.saveImage(
        noteDate: date, bytes: bytes, extension: 'png');
    expect(src, startsWith('assets/img-'));
    expect(src, endsWith('.png'));
    expect(storage.files.keys.single, 'notes/2026-07/19/$src');
  });

  test('loadImage는 메모리 캐시를 사용한다 (두번째 호출은 스토리지 미접근)', () async {
    final storage = _FakeStorage();
    storage.files['notes/2026-07/19/assets/a.png'] = bytes;
    final service = ImageAssetService(storage: storage);
    expect(await service.loadImage(noteDate: date, src: 'assets/a.png'), bytes);
    expect(await service.loadImage(noteDate: date, src: 'assets/a.png'), bytes);
    expect(storage.reads, 1);
  });

  test('경로 탈출 src는 거부한다', () async {
    final service = ImageAssetService(storage: _FakeStorage());
    expect(await service.loadImage(noteDate: date, src: '../../secret.png'),
        isNull);
  });

  test('없는 이미지는 null', () async {
    final service = ImageAssetService(storage: _FakeStorage());
    expect(await service.loadImage(noteDate: date, src: 'assets/nope.png'),
        isNull);
  });
}
```

주의: `_FakeStorage`가 `implements NoteStorage`에 `noSuchMethod`를 쓰므로 abstract 멤버 미구현 경고가 없어야 한다. analyze가 거부하면 미사용 멤버들을 `throw UnimplementedError()` 스텁으로 명시 구현한다.

- [ ] **Step 2: 실패 확인** → FAIL (파일 없음)

- [ ] **Step 3: 구현**

`desktop/lib/services/image_asset_service.dart`:

```dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../storage/note_storage.dart';

/// 노트 날짜 디렉토리 하위 assets/에 이미지를 저장하고 읽는다.
///
/// 파일명이 유일(타임스탬프 + 난수 4자리)해서 이미지는 불변이고, 캐시 무효화가
/// 필요 없다. [useDiskCache]는 원격(GitHub) 스토리지용 — 앱 재시작 후에도
/// 네트워크 재요청 없이 로드한다.
class ImageAssetService {
  ImageAssetService({required this.storage, this.useDiskCache = false});

  final NoteStorage storage;
  final bool useDiskCache;

  final Map<String, Uint8List> _memoryCache = {};
  static const int _memoryCacheLimit = 32;
  Directory? _diskCacheDir;
  static final DateFormat _stampFmt = DateFormat('yyyyMMdd-HHmmss');
  static final math.Random _random = math.Random();

  /// 이미지를 저장하고 노트 파일 기준 상대 src('assets/…')를 돌려준다.
  Future<String> saveImage({
    required DateTime noteDate,
    required Uint8List bytes,
    required String extension,
  }) async {
    final stamp = _stampFmt.format(DateTime.now());
    final rand =
        _random.nextInt(0x10000).toRadixString(16).padLeft(4, '0');
    final name = 'img-$stamp-$rand.$extension';
    final rel = '${storage.noteDirPath(noteDate)}/assets/$name';
    await storage.writeBinaryFile(rel, bytes);
    _cacheInMemory(rel, bytes);
    return 'assets/$name';
  }

  /// src('assets/…')의 이미지를 읽는다. 메모리 → 디스크 캐시 → 스토리지 순.
  Future<Uint8List?> loadImage({
    required DateTime noteDate,
    required String src,
  }) async {
    if (src.contains('..')) return null; // 경로 탈출 방지
    final rel = '${storage.noteDirPath(noteDate)}/$src';

    final memory = _memoryCache[rel];
    if (memory != null) return memory;

    final cacheFile = await _diskCacheFileFor(rel);
    if (cacheFile != null && await cacheFile.exists()) {
      final bytes = await cacheFile.readAsBytes();
      _cacheInMemory(rel, bytes);
      return bytes;
    }

    final bytes = await storage.readBinaryFile(rel);
    if (bytes == null) return null;
    _cacheInMemory(rel, bytes);
    if (cacheFile != null) {
      await cacheFile.parent.create(recursive: true);
      await cacheFile.writeAsBytes(bytes);
    }
    return bytes;
  }

  void _cacheInMemory(String rel, Uint8List bytes) {
    if (_memoryCache.length >= _memoryCacheLimit) _memoryCache.clear();
    _memoryCache[rel] = bytes;
  }

  Future<File?> _diskCacheFileFor(String rel) async {
    if (!useDiskCache) return null;
    final dir = _diskCacheDir ??= Directory(
        '${(await getApplicationSupportDirectory()).path}/image_cache');
    return File('${dir.path}/${rel.replaceAll('/', '_')}');
  }
}
```

- [ ] **Step 4: 통과 확인** → `flutter test test/services/image_asset_service_test.dart` PASS

- [ ] **Step 5: 커밋**

```bash
git add desktop/lib/services/image_asset_service.dart desktop/test/services/image_asset_service_test.dart
git commit -m "feat: 이미지 자산 저장/로드 서비스 (메모리+디스크 캐시)"
```

---

## Task 12: findImageRegions + 에디터 높이 예약

**Files:**
- Modify: `desktop/lib/services/markdown_editing.dart` (`ImageRegion`, `findImageRegions`, `serializeImageTag`)
- Modify: `desktop/lib/widgets/markdown_editing_controller.dart` (img 줄 스팬)
- Test: `desktop/test/services/markdown_editing_test.dart`, `desktop/test/widgets/markdown_editing_controller_test.dart` (추가)

**Interfaces:**
- Produces:
  - `class ImageRegion { int start; int end; String src; int width; int height; }`
  - `List<ImageRegion> findImageRegions(String text)`
  - `String serializeImageTag(String src, int width, int height)` — 파서와 왕복 대칭
  - Task 13-14가 사용

- [ ] **Step 1: 실패하는 테스트 작성**

`markdown_editing_test.dart`에 추가:

```dart
  group('findImageRegions', () {
    test('한 줄 img 태그를 파싱한다', () {
      const text = 'before\n<img src="assets/a.png" width="300" height="200">\nafter';
      final regions = findImageRegions(text);
      expect(regions, hasLength(1));
      final r = regions.first;
      expect(r.src, 'assets/a.png');
      expect(r.width, 300);
      expect(r.height, 200);
      expect(text.substring(r.start, r.end),
          '<img src="assets/a.png" width="300" height="200">');
    });

    test('serializeImageTag는 파서와 왕복 대칭이다', () {
      final tag = serializeImageTag('assets/a.png', 300, 200);
      final regions = findImageRegions(tag);
      expect(regions.single.src, 'assets/a.png');
      expect(regions.single.width, 300);
      expect(regions.single.height, 200);
    });

    test('fence 안의 img 태그는 무시한다', () {
      const text = '```\n<img src="a.png" width="1" height="1">\n```';
      expect(findImageRegions(text), isEmpty);
    });

    test('속성이 빠진 태그는 무시한다 (원문 노출 = 자가 복구)', () {
      const text = '<img src="a.png" width="300">';
      expect(findImageRegions(text), isEmpty);
    });
  });
```

`markdown_editing_controller_test.dart`에 추가 (기존 `_build`/`_flatten` 헬퍼와 Task 6에서 추가한 `_styleOf` 헬퍼 사용 — Task 6 미실행 상태면 02 문서의 `_styleOf` 정의를 함께 추가):

```dart
  group('image line rendering', () {
    const img = '<img src="assets/a.png" width="300" height="200">';

    testWidgets('invariant: img 줄도 문자 보존', (tester) async {
      final text = 'before\n$img\nafter';
      final span = await _build(tester, text);
      expect(_flatten(span).map((e) => e.$1).join(), text);
    });

    testWidgets('img 줄 첫 글자가 이미지 높이만큼 폰트를 갖는다 (높이 예약)',
        (tester) async {
      final span = await _build(tester, img);
      final style = _styleOf(span, '<');
      // 예약 높이 = (height 200 + 패딩 12) * scale(1.0)
      expect(style!.fontSize, greaterThan(200));
      expect(style.color, Colors.transparent);
    });
  });
```

- [ ] **Step 2: 실패 확인** → FAIL

- [ ] **Step 3: 파서 구현**

`markdown_editing.dart` 파일 끝에 추가:

```dart
// ── 인라인 이미지 (<img> 한 줄 태그) ────────────────────────────────────────

final RegExp _imgLineRe = RegExp(
    r'^\s*<img\s+src="([^"]+)"\s+width="(\d+)"\s+height="(\d+)"\s*/?>\s*$');

/// 에디터 텍스트에서 찾은 한 줄짜리 <img> 태그. width/height를 둘 다
/// 저장하는 이유: 이미지 바이트를 받기 전에 줄 높이를 예약해야 한다.
class ImageRegion {
  const ImageRegion({
    required this.start,
    required this.end,
    required this.src,
    required this.width,
    required this.height,
  });

  /// 줄 시작 오프셋 (inclusive).
  final int start;

  /// 줄 끝 오프셋 (exclusive).
  final int end;

  final String src;
  final int width;
  final int height;
}

/// 한 줄 <img src width height> 태그를 모두 찾는다. fence 내부는 무시.
/// 형식이 깨진 태그는 매칭되지 않아 원문 텍스트로 노출된다(자가 복구).
List<ImageRegion> findImageRegions(String text) {
  if (text.isEmpty) return const [];
  final lines = text.split('\n');
  final result = <ImageRegion>[];
  var offset = 0;
  var inFence = false;
  for (final line in lines) {
    if (_fenceRe.hasMatch(line)) {
      inFence = !inFence;
    } else if (!inFence) {
      final m = _imgLineRe.firstMatch(line);
      if (m != null) {
        result.add(ImageRegion(
          start: offset,
          end: offset + line.length,
          src: m.group(1)!,
          width: int.parse(m.group(2)!),
          height: int.parse(m.group(3)!),
        ));
      }
    }
    offset += line.length + 1;
  }
  return result;
}

/// 이미지 태그 직렬화. [_imgLineRe] 파서와 왕복 대칭.
String serializeImageTag(String src, int width, int height) =>
    '<img src="$src" width="$width" height="$height">';
```

- [ ] **Step 4: 컨트롤러 높이 예약 구현**

`markdown_editing_controller.dart`:

1. `buildTextSpan`의 details precompute 아래에 추가:

```dart
    // 인라인 이미지 줄: 태그 텍스트는 항상 숨기고 오버레이가 이미지를 그린다.
    final imageStarts = <int, ImageRegion>{};
    for (final r in findImageRegions(text)) {
      imageStarts[r.start] = r;
    }
```

2. 메인 루프에 분기 추가 (tableRowStarts 분기와 detailsTagStarts 분기 사이):

```dart
      } else if (imageStarts.containsKey(lineStart)) {
        spans.addAll(_imageLineSpans(line, imageStarts[lineStart]!, base));
```

3. 헬퍼 추가 (`_collapsed` 아래):

```dart
  /// 이미지 줄 상하 여백 (오버레이의 그림 여백과 일치해야 한다).
  static const double imagePadding = 6.0;

  /// 이미지 줄: 첫 글자에 (이미지 높이 + 여백) 크기 폰트를 줘 줄 높이를
  /// 예약하고, 전체를 투명 처리한다. 오버레이가 이 밴드 위에 이미지를 그린다.
  /// 캐럿이 줄에 있어도 원문을 노출하지 않는다(높이 요동 방지) — 수정/삭제는
  /// 오버레이 컨트롤로 한다.
  List<InlineSpan> _imageLineSpans(String line, ImageRegion r, TextStyle base) {
    final reserved = (r.height + imagePadding * 2) * scale;
    return [
      TextSpan(
        text: line.substring(0, 1),
        style: base.copyWith(
            fontSize: reserved, height: 1.0, color: Colors.transparent),
      ),
      if (line.length > 1)
        TextSpan(
          text: line.substring(1),
          style: base.copyWith(
              fontSize: 0.1,
              height: 1.0,
              letterSpacing: 0,
              color: Colors.transparent),
        ),
    ];
  }
```

- [ ] **Step 5: 통과 확인** → `flutter test test/services/ test/widgets/` 전체 PASS

- [ ] **Step 6: 커밋**

```bash
git add desktop/lib/services/markdown_editing.dart desktop/lib/widgets/markdown_editing_controller.dart desktop/test/
git commit -m "feat: 인라인 이미지 태그 파서와 에디터 줄 높이 예약"
```

---

## Task 13: InlineImageView + 오버레이/리사이즈/삭제

**Files:**
- Create: `desktop/lib/widgets/inline_image_view.dart`
- Modify: `desktop/lib/widgets/editor_panel.dart` (오버레이 빌더 + 조작 메서드 + props)
- Test: `desktop/test/widgets/editor_panel_image_test.dart` (신규)

**Interfaces:**
- Consumes: Task 7 `measureRanges`, Task 12 `ImageRegion`/`serializeImageTag`
- Produces:
  - `EditorPanel.onLoadImage: Future<Uint8List?> Function(String src)?` (신규 prop — Task 14에서 document_screen이 주입)
  - `class InlineImageView` (아래 시그니처)

- [ ] **Step 1: 실패하는 테스트 작성**

`desktop/test/widgets/editor_panel_image_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/theme/app_theme.dart';
import 'package:simsync/widgets/editor_panel.dart';
import 'package:simsync/widgets/inline_image_view.dart';

// 1x1 투명 PNG
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  Note note(String content) {
    final now = DateTime(2026, 7, 19);
    return Note(
      id: 'n1', noteDate: now, title: 't', content: content,
      isDefault: true, tags: [], createdAt: now, updatedAt: now,
    );
  }

  const img = '<img src="assets/a.png" width="120" height="80">';

  Future<void> pump(WidgetTester tester, Note n, {ValueChanged<Note>? onChanged}) {
    return tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: EditorPanel(
          note: n,
          onNoteChanged: onChanged ?? (_) {},
          onLoadImage: (src) async => _png,
        ),
      ),
    ));
  }

  testWidgets('img 태그 노트는 InlineImageView 오버레이를 그린다', (tester) async {
    await pump(tester, note('$img\ntext'));
    await tester.pumpAndSettle();
    expect(find.byType(InlineImageView), findsOneWidget);
  });

  testWidgets('onLoadImage가 없으면 오버레이를 만들지 않는다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(body: EditorPanel(note: note(img), onNoteChanged: (_) {})),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(InlineImageView), findsNothing);
  });

  testWidgets('활성 이미지의 X 버튼은 태그 줄을 삭제한다', (tester) async {
    Note? saved;
    await pump(tester, note('$img\ntext'), onChanged: (n) => saved = n);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(InlineImageView)); // 활성화
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump(const Duration(seconds: 2)); // 자동 저장 디바운스
    expect(saved, isNotNull);
    expect(saved!.content, 'text');
  });
}
```

- [ ] **Step 2: 실패 확인** → FAIL

- [ ] **Step 3: InlineImageView 구현**

`desktop/lib/widgets/inline_image_view.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 에디터의 숨겨진 <img> 마크다운 줄 위에 겹쳐 그려지는 인라인 이미지.
/// InlineTableView와 같은 오버레이 패턴. 활성(클릭/캐럿) 상태에서 우상단
/// 삭제 버튼과 우하단 리사이즈 핸들을 보여준다. 리사이즈는 비율 고정이며
/// 드롭 시 [onResized]로 width/height를 마크다운에 재기록한다.
class InlineImageView extends StatefulWidget {
  const InlineImageView({
    super.key,
    required this.src,
    required this.width,
    required this.height,
    required this.scale,
    required this.active,
    required this.readOnly,
    required this.loadImage,
    required this.onActivate,
    required this.onResized,
    required this.onRemove,
  });

  final String src;

  /// 마크다운 속성 기준 크기 (px). 표시 크기 = width * scale.
  final int width;
  final int height;

  /// 에디터 콘텐츠 줌 배율.
  final double scale;

  final bool active;
  final bool readOnly;
  final Future<Uint8List?> Function(String src) loadImage;
  final VoidCallback onActivate;
  final void Function(int width, int height) onResized;
  final VoidCallback onRemove;

  /// 리사이즈 폭 한계 (마크다운 속성 기준 px).
  static const int minWidth = 48;
  static const int maxWidth = 1200;

  @override
  State<InlineImageView> createState() => _InlineImageViewState();
}

class _InlineImageViewState extends State<InlineImageView> {
  late Future<Uint8List?> _bytesFuture;

  /// 드래그 중 미리보기 폭 (마크다운 속성 기준 px). null이면 드래그 중 아님.
  double? _dragWidth;

  @override
  void initState() {
    super.initState();
    _bytesFuture = widget.loadImage(widget.src);
  }

  @override
  void didUpdateWidget(InlineImageView old) {
    super.didUpdateWidget(old);
    if (old.src != widget.src) {
      _bytesFuture = widget.loadImage(widget.src);
    }
  }

  double get _aspect =>
      widget.height <= 0 ? 1 : widget.width / widget.height;

  void _endDrag() {
    final w = _dragWidth;
    if (w == null) return;
    setState(() => _dragWidth = null);
    final newW =
        w.round().clamp(InlineImageView.minWidth, InlineImageView.maxWidth);
    widget.onResized(newW, (newW / _aspect).round());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final attrW = (_dragWidth ?? widget.width.toDouble()).clamp(
        InlineImageView.minWidth.toDouble(),
        InlineImageView.maxWidth.toDouble());
    final displayW = attrW * widget.scale;
    final displayH = attrW / _aspect * widget.scale;

    return Align(
      alignment: Alignment.topLeft,
      child: GestureDetector(
        onTap: widget.onActivate,
        child: Stack(
          children: [
            Container(
              width: displayW,
              height: displayH,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: widget.active ? c.accent : c.border,
                  width: widget.active ? 1.5 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: FutureBuilder<Uint8List?>(
                future: _bytesFuture,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: c.accent),
                      ),
                    );
                  }
                  final bytes = snap.data;
                  if (bytes == null) {
                    return Center(
                      child: Icon(Icons.broken_image_outlined,
                          size: 20, color: c.textMuted),
                    );
                  }
                  return Image.memory(bytes,
                      fit: BoxFit.fill, gaplessPlayback: true);
                },
              ),
            ),
            if (widget.active && !widget.readOnly) ...[
              Positioned(
                top: 4,
                right: 4,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: widget.onRemove,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: c.surface.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: c.border),
                      ),
                      child:
                          Icon(Icons.close_rounded, size: 14, color: c.textSecondary),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeDownRight,
                  child: GestureDetector(
                    onPanUpdate: (d) => setState(() {
                      _dragWidth = (_dragWidth ?? widget.width.toDouble()) +
                          d.delta.dx / widget.scale;
                    }),
                    onPanEnd: (_) => _endDrag(),
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: c.accent,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          bottomRight: Radius.circular(5),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: editor_panel 오버레이 + 조작 구현**

`editor_panel.dart`:

1. import 추가: `import 'dart:typed_data';`, `import 'inline_image_view.dart';`
2. `EditorPanel`에 prop 추가 (+ 생성자 파라미터):

```dart
  /// 노트 기준 상대 src('assets/…')의 이미지 바이트 로더. null이면 이미지
  /// 오버레이 비활성(로드 경로가 없는 컨텍스트).
  final Future<Uint8List?> Function(String src)? onLoadImage;
```

3. `_buildEditor`의 Stack에서 details 토글 오버레이 다음에 추가:

```dart
        // 인라인 이미지 — 숨겨진 <img> 줄의 예약 밴드 위에 그린다.
        Positioned.fill(
          child: _buildImageOverlays(c, bodyStyle, strut, textScaler),
        ),
```

4. 메서드 추가 (`_buildDetailsToggles` 아래):

```dart
  Widget _buildImageOverlays(
    AppColorsExtension c,
    TextStyle bodyStyle,
    StrutStyle strut,
    TextScaler textScaler,
  ) {
    final onLoad = widget.onLoadImage;
    if (onLoad == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable:
          Listenable.merge([_contentController, _contentScrollController]),
      builder: (context, _) {
        final images = findImageRegions(_contentController.text);
        if (images.isEmpty) return const SizedBox.shrink();
        return LayoutBuilder(
          builder: (context, constraints) {
            final span = _contentController.buildTextSpan(
                context: context, style: bodyStyle, withComposing: false);
            final measured = measureRanges(
                span,
                [for (final r in images) (start: r.start, end: r.end)],
                strut,
                textScaler,
                constraints.maxWidth);
            final scrollY = _contentScrollController.hasClients
                ? _contentScrollController.offset
                : 0.0;
            final sel = _contentController.selection;
            final caret = sel.isValid ? sel.baseOffset : -1;
            final scale = widget.contentScale;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                for (final m in measured)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: m.top -
                        scrollY +
                        MarkdownEditingController.imagePadding * scale,
                    height: images[m.index].height * scale.toDouble(),
                    child: InlineImageView(
                      key: ValueKey(
                          '${images[m.index].start}:${images[m.index].src}'),
                      src: images[m.index].src,
                      width: images[m.index].width,
                      height: images[m.index].height,
                      scale: scale,
                      active: !widget.isReadOnly &&
                          caret >= images[m.index].start &&
                          caret <= images[m.index].end,
                      readOnly: widget.isReadOnly,
                      loadImage: onLoad,
                      onActivate: () => _activateImage(images[m.index]),
                      onResized: (w, h) =>
                          _resizeImage(images[m.index], w, h),
                      onRemove: () => _removeImage(images[m.index]),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  // 이미지를 클릭하면 캐럿을 (숨겨진) 태그 줄로 옮겨 활성화한다.
  void _activateImage(ImageRegion r) {
    if (widget.isReadOnly) return;
    _contentFocusNode.requestFocus();
    _contentController.selection = TextSelection.collapsed(
        offset: r.start.clamp(0, _contentController.text.length));
  }

  // 리사이즈 결과를 태그의 width/height 속성으로 재기록한다.
  void _resizeImage(ImageRegion r, int w, int h) {
    if (widget.isReadOnly || widget.note == null) return;
    _replaceRange(r.start, r.end, serializeImageTag(r.src, w, h));
  }

  // 태그 줄 전체(뒤따르는 개행 포함)를 삭제한다. 파일 정리는 하지 않는다
  // (orphan 허용 — 설계 문서 범위 외 참고).
  void _removeImage(ImageRegion r) {
    if (widget.isReadOnly || widget.note == null) return;
    final text = _contentController.text;
    final s = r.start.clamp(0, text.length);
    var e = r.end.clamp(s, text.length);
    if (e < text.length && text[e] == '\n') e++;
    _contentController.value = TextEditingValue(
      text: text.replaceRange(s, e, ''),
      selection: TextSelection.collapsed(offset: s),
    );
    _onContentChanged();
  }
```

주의: `MarkdownEditingController.imagePadding`을 쓰려면 Task 12의 `imagePadding`이 public이어야 한다 (계획대로 `static const double imagePadding = 6.0;`).

- [ ] **Step 5: 통과 확인** → `flutter test test/widgets/ && flutter analyze` 전체 PASS

- [ ] **Step 6: 커밋**

```bash
git add desktop/lib/widgets/ desktop/test/widgets/editor_panel_image_test.dart
git commit -m "feat: 인라인 이미지 뷰어 오버레이 (리사이즈/삭제)"
```

---

## Task 14: 붙여넣기 인터셉트 + 툴바 첨부 + 와이어링

**Files:**
- Modify: `desktop/pubspec.yaml` (pasteboard 추가)
- Modify: `desktop/lib/widgets/editor_panel.dart` (onAttachImage prop, cmd+V 인터셉트, 툴바 버튼, 삽입 흐름)
- Modify: `desktop/lib/screens/document_screen.dart` (ImageAssetService 와이어링)
- Test: `desktop/test/widgets/editor_panel_image_test.dart` (추가)

**Interfaces:**
- Consumes: Task 11 `ImageAssetService`, Task 12 `serializeImageTag`, Task 13 prop 패턴
- Produces: `EditorPanel.onAttachImage: Future<String> Function(Uint8List bytes, String extension)?` — 반환값은 삽입할 src

- [ ] **Step 1: 의존성 추가**

Run: `cd desktop && flutter pub add pasteboard`
Expected: pubspec.yaml dependencies에 `pasteboard: ^x.y.z` 추가됨 (버전은 pub 해석 결과를 따른다). macOS 클립보드 이미지 읽기용 — Flutter 기본 `Clipboard`는 텍스트 전용이라 필수. `flutter analyze`로 빌드 정상 확인.

- [ ] **Step 2: 실패하는 테스트 작성**

`editor_panel_image_test.dart`에 추가:

```dart
  testWidgets('attachImageForTest는 업로드 후 태그를 삽입한다', (tester) async {
    Note? saved;
    Uint8List? uploaded;
    final key = GlobalKey<EditorPanelState>();
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: EditorPanel(
          key: key,
          note: note(''),
          onNoteChanged: (n) => saved = n,
          onLoadImage: (src) async => _png,
          onAttachImage: (bytes, ext) async {
            uploaded = bytes;
            return 'assets/img-test.$ext';
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await key.currentState!.attachImageBytes(_png, 'png');
    await tester.pump(const Duration(seconds: 2)); // 자동 저장 디바운스
    expect(uploaded, _png);
    expect(saved!.content,
        '<img src="assets/img-test.png" width="1" height="1">\n');
  });

  testWidgets('onAttachImage 실패 시 태그를 삽입하지 않고 스낵바를 띄운다',
      (tester) async {
    final key = GlobalKey<EditorPanelState>();
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: EditorPanel(
          key: key,
          note: note(''),
          onNoteChanged: (_) {},
          onLoadImage: (src) async => _png,
          onAttachImage: (bytes, ext) async => throw Exception('fail'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await key.currentState!.attachImageBytes(_png, 'png');
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.controller!.text, '');
  });
```

(1x1 PNG이므로 natural size 1x1 → `width="1" height="1"`. 삽입 기본폭 480은 `min(naturalWidth, 480)`이라 1이 된다.)

- [ ] **Step 3: 실패 확인** → FAIL (`onAttachImage`/`attachImageBytes` 미정의)

- [ ] **Step 4: EditorPanel 구현**

`editor_panel.dart`:

1. import 추가:

```dart
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:pasteboard/pasteboard.dart';
```

2. prop 추가:

```dart
  /// 이미지 바이트를 스토리지에 저장하고 삽입할 src('assets/…')를 돌려준다.
  /// null이면 이미지 첨부 비활성 (읽기 전용 등).
  final Future<String> Function(Uint8List bytes, String extension)? onAttachImage;
```

3. `EditorPanelState`에 첨부 흐름 추가:

```dart
  /// 삽입 시 기본 표시 폭 (px). 원본이 더 작으면 원본 폭.
  static const int _defaultImageWidth = 480;

  /// 이미지 바이트를 업로드하고 캐럿 위치에 <img> 태그를 삽입한다.
  /// (테스트에서 직접 호출할 수 있게 public)
  Future<void> attachImageBytes(Uint8List bytes, String extension) async {
    final onAttach = widget.onAttachImage;
    if (onAttach == null || widget.isReadOnly || widget.note == null) return;
    try {
      final decoded = await decodeImageFromList(bytes);
      final natW = decoded.width;
      final natH = decoded.height;
      decoded.dispose();
      final src = await onAttach(bytes, extension);
      final w = math.min(natW, _defaultImageWidth);
      final h = (natH * w / natW).round();
      if (!mounted) return;
      _insertBlock(serializeImageTag(src, w, h));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미지 첨부에 실패했습니다.')),
      );
    }
  }

  Future<void> _attachImageFromPicker() async {
    if (widget.isReadOnly || widget.note == null || widget.onAttachImage == null) {
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'gif', 'webp'],
      withData: true,
    );
    final file = result?.files.firstOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    await attachImageBytes(bytes, (file.extension ?? 'png').toLowerCase());
  }

  /// cmd+V 인터셉트: 클립보드에 이미지가 있으면 첨부, 아니면 일반 텍스트
  /// 붙여넣기를 수동 수행한다(이벤트를 가로챘으므로). 우클릭 메뉴 Paste는
  /// 이 경로를 타지 않는다 — 텍스트만 붙는 기존 동작 유지 (MVP 한계).
  KeyEventResult _onEditorKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.keyV) return KeyEventResult.ignored;
    if (!HardwareKeyboard.instance.isMetaPressed) return KeyEventResult.ignored;
    if (widget.isReadOnly || widget.note == null || widget.onAttachImage == null) {
      return KeyEventResult.ignored;
    }
    unawaited(_handlePaste());
    return KeyEventResult.handled;
  }

  Future<void> _handlePaste() async {
    final image = await Pasteboard.image;
    if (image != null) {
      await attachImageBytes(image, 'png');
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text;
    if (t == null || t.isEmpty) return;
    final value = _contentController.value;
    final start = (value.selection.isValid ? value.selection.start : value.text.length)
        .clamp(0, value.text.length);
    final end = (value.selection.isValid ? value.selection.end : start)
        .clamp(start, value.text.length);
    _contentController.value = TextEditingValue(
      text: value.text.replaceRange(start, end, t),
      selection: TextSelection.collapsed(offset: start + t.length),
    );
    _onContentChanged();
  }
```

4. `_buildEditor`에서 field를 Focus로 감싼다 (Stack의 `field` 자리에 `wrappedField` 사용):

```dart
    // cmd+V 이미지 붙여넣기를 TextField 기본 paste보다 먼저 가로챈다.
    final wrappedField = Focus(
      onKeyEvent: _onEditorKeyEvent,
      child: field,
    );
```

5. 툴바에 버튼 추가 (`_buildToolbar`의 표 버튼 다음):

```dart
            const SizedBox(width: AppDimensions.spacingXs),
            _ToolbarIconButton(
              icon: Icons.image_outlined,
              tooltip: '이미지 첨부',
              onTap: () => unawaited(_attachImageFromPicker()),
            ),
```

- [ ] **Step 5: document_screen 와이어링**

`document_screen.dart`:

1. import 추가: `import '../services/image_asset_service.dart';` (Uint8List는 flutter/services 경유로 이미 사용 가능; 필요 시 `dart:typed_data` 추가)
2. 상태 필드 + 헬퍼 추가 (`_storageFor` 아래):

```dart
  /// 스토리지별 이미지 자산 서비스 (메모리/디스크 캐시 보존을 위해 재사용).
  final Map<NoteStorage, ImageAssetService> _imageServices = {};

  ImageAssetService _imageServiceFor(Note note) {
    final storage = _storageFor(note);
    return _imageServices.putIfAbsent(
      storage,
      () => ImageAssetService(
        storage: storage,
        // 원격(synced) 스토리지만 디스크 캐시를 쓴다. 로컬은 원본이 곧 디스크.
        useDiskCache: identical(storage, _storage),
      ),
    );
  }
```

3. `_buildRightPanel`의 `EditorPanel(` 생성자에 추가:

```dart
      onAttachImage: _selectedNote == null || selectedNoteIsReadOnly
          ? null
          : (bytes, ext) {
              final note = _selectedNote!;
              return _imageServiceFor(note).saveImage(
                  noteDate: note.noteDate, bytes: bytes, extension: ext);
            },
      onLoadImage: _selectedNote == null
          ? null
          : (src) {
              final note = _selectedNote!;
              return _imageServiceFor(note)
                  .loadImage(noteDate: note.noteDate, src: src);
            },
```

- [ ] **Step 6: 통과 확인**

Run: `flutter test && flutter analyze`
Expected: 전체 PASS, 0 issues

- [ ] **Step 7: 커밋**

```bash
git add desktop/pubspec.yaml desktop/pubspec.lock desktop/lib/ desktop/test/
git commit -m "feat: 이미지 붙여넣기/파일 첨부와 스토리지 와이어링"
```

macOS 러너 설정 주의: pasteboard가 macOS entitlement를 요구하지는 않지만, 첫 `flutter run -d macos`에서 pod 설치가 돌 수 있다. 실패 시 `cd macos && pod install` 후 재시도.

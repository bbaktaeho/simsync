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
    if (extension.contains('/') || extension.contains('..')) {
      throw ArgumentError.value(extension, 'extension', '경로 문자를 포함할 수 없다');
    }
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

    File? cacheFile;
    try {
      cacheFile = await _diskCacheFileFor(rel);
      if (cacheFile != null && await cacheFile.exists()) {
        final bytes = await cacheFile.readAsBytes();
        _cacheInMemory(rel, bytes);
        return bytes;
      }
    } catch (_) {
      // 디스크 캐시는 최적화일 뿐 — 읽기 실패(손상/삭제/권한)해도 로드는
      // 성공해야 한다. 스토리지 읽기로 폴백한다.
      cacheFile = null;
    }

    final bytes = await storage.readBinaryFile(rel);
    if (bytes == null) return null;
    _cacheInMemory(rel, bytes);
    if (cacheFile != null) {
      try {
        await cacheFile.parent.create(recursive: true);
        await cacheFile.writeAsBytes(bytes);
      } catch (_) {
        // 디스크 캐시는 최적화일 뿐 — 쓰기 실패(디스크 부족/권한)해도 이미
        // 바이트를 확보했으므로 로드는 성공해야 한다.
      }
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

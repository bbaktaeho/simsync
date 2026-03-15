import 'dart:async';

/// 동기화 상태.
enum SyncStatus { idle, syncing, error }

/// 동기화 엔진 인터페이스.
abstract class SyncEngine {
  void start();
  void stop();
  Future<void> syncNow();
  Stream<SyncStatus> get statusStream;
  void dispose();
}

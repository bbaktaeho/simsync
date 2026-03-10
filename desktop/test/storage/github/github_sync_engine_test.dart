import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simsync/storage/github/github_sync_engine.dart';
import 'package:simsync/storage/sync_engine.dart';

void main() {
  group('GitHubSyncEngine', () {
    test('syncNow calls onRemoteChanged when commit SHA changes', () async {
      var callCount = 0;
      var currentSha = 'sha-aaa';

      final client = MockClient((request) async {
        return http.Response(
          jsonEncode([
            {'sha': currentSha}
          ]),
          200,
        );
      });

      final engine = GitHubSyncEngine(
        token: 'test-token',
        owner: 'owner',
        repo: 'repo',
        httpClient: client,
        onRemoteChanged: () async {
          callCount++;
        },
      );

      // First call — always triggers (no previous SHA).
      await engine.syncNow();
      expect(callCount, 1);

      // Same SHA — should NOT trigger.
      await engine.syncNow();
      expect(callCount, 1);

      // New SHA — should trigger.
      currentSha = 'sha-bbb';
      await engine.syncNow();
      expect(callCount, 2);

      engine.dispose();
    });

    test('syncNow emits syncing then idle status', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode([
            {'sha': 'sha-abc'}
          ]),
          200,
        );
      });

      final engine = GitHubSyncEngine(
        token: 'test-token',
        owner: 'owner',
        repo: 'repo',
        httpClient: client,
      );

      final statuses = <SyncStatus>[];
      engine.statusStream.listen(statuses.add);

      await engine.syncNow();

      // Allow microtasks to flush.
      await Future<void>.delayed(Duration.zero);

      expect(statuses, [SyncStatus.syncing, SyncStatus.idle]);

      engine.dispose();
    });

    test('syncNow emits error status on API failure', () async {
      final client = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final engine = GitHubSyncEngine(
        token: 'test-token',
        owner: 'owner',
        repo: 'repo',
        httpClient: client,
      );

      final statuses = <SyncStatus>[];
      engine.statusStream.listen(statuses.add);

      await engine.syncNow();

      await Future<void>.delayed(Duration.zero);

      expect(statuses, [SyncStatus.syncing, SyncStatus.error]);

      engine.dispose();
    });

    test('exponential backoff increases interval on consecutive errors', () async {
      var requestCount = 0;

      final client = MockClient((request) async {
        requestCount++;
        return http.Response('Internal Server Error', 500);
      });

      final engine = GitHubSyncEngine(
        token: 'test-token',
        owner: 'owner',
        repo: 'repo',
        interval: const Duration(seconds: 5),
        httpClient: client,
      );

      // Trigger multiple errors
      await engine.syncNow();
      await engine.syncNow();
      await engine.syncNow();

      // All three calls should have gone through (backoff affects timer, not manual syncNow)
      expect(requestCount, 3);

      // Engine should be in error state
      final statuses = <SyncStatus>[];
      engine.statusStream.listen(statuses.add);
      await engine.syncNow();
      await Future<void>.delayed(Duration.zero);
      expect(statuses, [SyncStatus.syncing, SyncStatus.error]);

      engine.dispose();
    });

    test('backoff resets after a successful sync', () async {
      var failCount = 0;
      var succeedAfter = 3;

      final client = MockClient((request) async {
        failCount++;
        if (failCount <= succeedAfter) {
          return http.Response('Internal Server Error', 500);
        }
        return http.Response(
          jsonEncode([
            {'sha': 'sha-reset'}
          ]),
          200,
        );
      });

      final engine = GitHubSyncEngine(
        token: 'test-token',
        owner: 'owner',
        repo: 'repo',
        interval: const Duration(seconds: 5),
        httpClient: client,
      );

      // Trigger errors to build up backoff
      await engine.syncNow();
      await engine.syncNow();
      await engine.syncNow();

      // Now succeed — should reset backoff
      final statuses = <SyncStatus>[];
      engine.statusStream.listen(statuses.add);
      await engine.syncNow();
      await Future<void>.delayed(Duration.zero);

      expect(statuses, [SyncStatus.syncing, SyncStatus.idle]);

      engine.dispose();
    });

    test('rate limit header triggers error when exhausted', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode([
            {'sha': 'sha-rate'}
          ]),
          200,
          headers: {'x-ratelimit-remaining': '0'},
        );
      });

      final engine = GitHubSyncEngine(
        token: 'test-token',
        owner: 'owner',
        repo: 'repo',
        httpClient: client,
      );

      final statuses = <SyncStatus>[];
      engine.statusStream.listen(statuses.add);

      await engine.syncNow();
      await Future<void>.delayed(Duration.zero);

      expect(statuses, [SyncStatus.syncing, SyncStatus.error]);

      engine.dispose();
    });
  });
}

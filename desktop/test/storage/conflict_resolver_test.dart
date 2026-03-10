import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/storage/conflict_resolver.dart';

void main() {
  group('LastWriteWinsResolver', () {
    late LastWriteWinsResolver resolver;

    setUp(() {
      resolver = LastWriteWinsResolver();
    });

    test('picks local when local is newer', () async {
      final now = DateTime.now();
      final local = Note(
        id: '1',
        noteDate: now,
        title: 'Local',
        content: 'local content',
        isDefault: false,
        tags: [],
        createdAt: now,
        updatedAt: now.add(const Duration(seconds: 10)),
      );
      final remote = Note(
        id: '1',
        noteDate: now,
        title: 'Remote',
        content: 'remote content',
        isDefault: false,
        tags: [],
        createdAt: now,
        updatedAt: now,
      );

      final result = await resolver.resolve(local, remote);

      expect(result.title, equals('Local'));
      expect(result.content, equals('local content'));
    });

    test('picks remote when remote is newer', () async {
      final now = DateTime.now();
      final local = Note(
        id: '1',
        noteDate: now,
        title: 'Local',
        content: 'local content',
        isDefault: false,
        tags: [],
        createdAt: now,
        updatedAt: now,
      );
      final remote = Note(
        id: '1',
        noteDate: now,
        title: 'Remote',
        content: 'remote content',
        isDefault: false,
        tags: [],
        createdAt: now,
        updatedAt: now.add(const Duration(seconds: 10)),
      );

      final result = await resolver.resolve(local, remote);

      expect(result.title, equals('Remote'));
      expect(result.content, equals('remote content'));
    });
  });
}

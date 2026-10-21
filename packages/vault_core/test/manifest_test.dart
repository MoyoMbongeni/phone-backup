import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

void main() {
  final now = DateTime.utc(2026, 10, 21);
  final blobIds = {'X': 'blob-x', 'Y': 'blob-y', 'Z': 'blob-z'};

  FileEntry file(String path, String sha) => FileEntry(
        source: 's',
        path: path,
        sha256: sha,
        blobId: blobIds[sha]!,
        size: 1,
        modified: now,
        firstSeen: now,
        lastChanged: now,
      );

  ManifestEntry entry(String path, String sha) =>
      ManifestEntry(path: path, size: 1, modified: now, sha256: sha);

  ChangeSet diff(List<FileEntry> current, List<ManifestEntry> manifest) => diffManifest(
        source: 's',
        current: {for (final f in current) f.path: f},
        manifest: manifest,
        blobIds: blobIds,
        now: now,
      );

  test('a copy next to the original is an addition, not a move', () {
    final changes = diff([file('a', 'X')], [entry('a', 'X'), entry('b', 'X')]);
    expect(changes.events.single.type, EventType.fileAdded);
    expect(changes.unchanged, 1);
  });

  test('two copies collapsing into one renamed file: one move, one delete', () {
    final changes =
        diff([file('a', 'X'), file('b', 'X')], [entry('c', 'X')]);
    expect(changes.events.map((e) => (e.type, e.path, e.fromPath)), [
      (EventType.fileMoved, 'c', 'a'),
      (EventType.fileDeleted, 'b', null),
    ]);
  });

  test('changed content at the same path is a modification', () {
    final changes = diff([file('a', 'X')], [entry('a', 'Y')]);
    expect(changes.events.single.type, EventType.fileModified);
    expect(changes.events.single.blobId, 'blob-y');
  });

  test('an empty source deletes everything; deletions keep the old hash', () {
    final changes = diff([file('a', 'X'), file('b', 'Z')], []);
    expect(changes.deleted, 2);
    expect(changes.events.map((e) => e.sha256), ['X', 'Z']);
  });

  group('recovery key', () {
    test('round-trips and reads back what a person might type', () {
      final bytes = Uint8List.fromList(List.generate(20, (i) => i * 13 % 256));
      final text = encodeRecoveryKey(bytes);
      expect(text, matches(RegExp(r'^([0-9A-Z]{4}-){7}[0-9A-Z]{4}$')));
      expect(decodeRecoveryKey(text), bytes);
      final sloppy = text.toLowerCase().replaceAll('-', ' ').replaceAll('0', 'o');
      expect(decodeRecoveryKey(sloppy), bytes);
    });

    test('rejects a wrong length or a letter outside the alphabet', () {
      expect(() => decodeRecoveryKey('ABCD'), throwsFormatException);
      expect(() => decodeRecoveryKey('U' * 32), throwsFormatException);
    });
  });
}

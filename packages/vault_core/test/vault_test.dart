import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

void main() {
  late Directory temp;
  late String vaultDir;
  late Directory photos;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('vault_core_test_');
    vaultDir = p.join(temp.path, 'vault');
    photos = await Directory(p.join(temp.path, 'photos')).create();
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  Future<void> write(String relative, List<int> bytes) async {
    final file = File(p.join(photos.path, relative));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  Uint8List randomData(int length) {
    final random = Random(length);
    return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
  }

  Future<Vault> newVault([String password = 'pw']) async =>
      (await Vault.create(vaultDir, password, kdf: KdfParams.forTests())).vault;

  test('unlocks with the password or the recovery key, and the password can change',
      () async {
    final created =
        await Vault.create(vaultDir, 'first password', kdf: KdfParams.forTests());
    created.vault.lock();

    await expectLater(Vault.unlockWithPassword(vaultDir, 'wrong password'),
        throwsA(isA<WrongKeyException>()));
    final byPassword = await Vault.unlockWithPassword(vaultDir, 'first password');
    expect(byPassword.index.events.single.type, EventType.vaultCreated);
    byPassword.lock();

    // Lower case and missing dashes are accepted when typing the key.
    final typed = created.recoveryKey.toLowerCase().replaceAll('-', '');
    final byRecovery = await Vault.unlockWithRecoveryKey(vaultDir, typed);
    await byRecovery.changePassword('second password');
    expect(await byRecovery.checkPassword('second password'), isTrue);
    expect(await byRecovery.checkPassword('first password'), isFalse);
    byRecovery.lock();

    await expectLater(Vault.unlockWithPassword(vaultDir, 'first password'),
        throwsA(isA<WrongKeyException>()));
    final reopened = await Vault.unlockWithPassword(vaultDir, 'second password');
    expect(reopened.index.events.map((e) => e.type),
        [EventType.vaultCreated, EventType.passwordChanged]);
    await expectLater(Vault.unlockWithRecoveryKey(vaultDir, 'not-a-key'),
        throwsA(isA<WrongKeyException>()));
  });

  test('stores identical files once and logs adds, edits, moves and deletes', () async {
    final photo = randomData(300 * 1024);
    final video = randomData(2 * 1024 * 1024 + 123); // three chunks
    await write('DCIM/a.jpg', photo);
    await write('DCIM/copy-of-a.jpg', photo);
    await write('notes/todo.txt', utf8.encode('buy milk'));
    await write('empty.txt', const []);

    final vault = await newVault();
    final first = await vault.importFolder(photos.path);
    expect(first.added, 4);
    expect(first.newBlobs, 3);
    expect(first.duplicatesAvoided, 1);
    expect(first.duplicateBytes, photo.length);

    // Running again with nothing changed stores and logs no file changes.
    final idle = await vault.importFolder(photos.path);
    expect(idle.sourceId, first.sourceId);
    expect(idle.unchanged, 4);
    expect(idle.changes.events, isEmpty);
    expect(idle.newBlobs, 0);

    await File(p.join(photos.path, 'DCIM', 'a.jpg'))
        .rename(p.join(photos.path, 'DCIM', 'renamed.jpg'));
    await File(p.join(photos.path, 'DCIM', 'copy-of-a.jpg')).delete();
    await write('notes/todo.txt', utf8.encode('buy milk and eggs'));
    await write('videos/clip.mp4', video);

    final second = await vault.importFolder(photos.path);
    expect(
      [second.added, second.modified, second.moved, second.deleted, second.unchanged],
      [1, 1, 1, 1, 1],
    );
    expect(second.newBlobs, 2);

    final files = vault.index.filesOf(second.sourceId);
    expect(files.keys, unorderedEquals(
        ['DCIM/renamed.jpg', 'notes/todo.txt', 'videos/clip.mp4', 'empty.txt']));
    expect(await vault.readFile(files['videos/clip.mp4']!), video);
    expect(await vault.readFile(files['empty.txt']!), isEmpty);
    expect(utf8.decode(await vault.readFile(files['notes/todo.txt']!)),
        'buy milk and eggs');

    // The deleted copy is listed with its date and can still be opened.
    final deleted = vault.index.deleted.single;
    expect(deleted.file.path, 'DCIM/copy-of-a.jpg');
    expect(await vault.readFile(deleted.file), photo);

    final history = vault.index.historyOf(second.sourceId, 'DCIM/renamed.jpg');
    expect(history.map((e) => (e.type, e.path)), [
      (EventType.fileAdded, 'DCIM/a.jpg'),
      (EventType.fileMoved, 'DCIM/renamed.jpg'),
    ]);

    final exported = p.join(temp.path, 'exported.mp4');
    await vault.exportFile(files['videos/clip.mp4']!, exported);
    expect(await File(exported).readAsBytes(), video);

    // Reopening from disk rebuilds exactly the same state from the log.
    final paths = files.keys.toList();
    final eventCount = vault.index.events.length;
    vault.lock();
    final again = await Vault.unlockWithPassword(vaultDir, 'pw');
    expect(again.index.filesOf(second.sourceId).keys, unorderedEquals(paths));
    expect(again.index.events, hasLength(eventCount));
    expect(again.index.deleted.single.file.path, 'DCIM/copy-of-a.jpg');
    expect(again.index.stats.duplicatesAvoided, 1);
  });

  test('nothing in the vault folder reveals file contents or names', () async {
    const marker = 'PLAINTEXT-MARKER-0123456789';
    await write('secret-holiday.txt', utf8.encode(marker * 3));
    final vault = await newVault();
    await vault.importFolder(photos.path);

    await for (final entity in Directory(vaultDir).list(recursive: true)) {
      if (entity is! File) continue;
      final text = latin1.decode(await entity.readAsBytes());
      expect(text.contains(marker), isFalse, reason: entity.path);
      expect(text.contains('secret-holiday'), isFalse, reason: entity.path);
      expect(entity.path.contains('secret-holiday'), isFalse);
    }
  });

  test('a modified blob fails to read instead of returning wrong data', () async {
    await write('a.bin', randomData(5000));
    final vault = await newVault();
    final result = await vault.importFolder(photos.path);
    final entry = vault.index.filesOf(result.sourceId)['a.bin']!;
    final blob = File(p.join(
        vaultDir, 'blobs', entry.blobId.substring(0, 2), '${entry.blobId}.blob'));
    final bytes = await blob.readAsBytes();
    bytes[bytes.length - 20] ^= 0x01;
    await blob.writeAsBytes(bytes);
    await expectLater(vault.readFile(entry), throwsA(isA<VaultCorruptException>()));
  });

  test('a half-written log record from a crash is dropped on open', () async {
    final vault = await newVault();
    await vault.changePassword('pw2');
    vault.lock();
    await File(p.join(vaultDir, 'log', 'events.pblog'))
        .writeAsBytes([0, 0, 1, 0, 9, 9, 9], mode: FileMode.append);

    final reopened = await Vault.unlockWithPassword(vaultDir, 'pw2');
    expect(reopened.index.events, hasLength(2));
    await reopened.changePassword('pw3');
    reopened.lock();
    expect((await Vault.unlockWithPassword(vaultDir, 'pw3')).index.events, hasLength(3));
  });

  test('backing up a folder that holds the vault skips the vault', () async {
    await write('a.txt', utf8.encode('hello'));
    final vault = await newVault();
    final result = await vault.importFolder(temp.path);
    expect(vault.index.filesOf(result.sourceId).keys, ['photos/a.txt']);
    await expectLater(vault.importFolder(vaultDir), throwsA(isA<VaultException>()));
    await expectLater(
        vault.importFolder(p.join(vaultDir, 'blobs')), throwsA(isA<VaultException>()));
  });

  test('a new vault needs an empty folder', () async {
    await Directory(vaultDir).create();
    await File(p.join(vaultDir, 'something.txt')).writeAsString('x');
    await expectLater(Vault.create(vaultDir, 'pw', kdf: KdfParams.forTests()),
        throwsA(isA<VaultException>()));
  });
}

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'blob_store.dart';
import 'bytes.dart';
import 'cipher.dart';
import 'errors.dart';
import 'event_log.dart';
import 'events.dart';
import 'import_job.dart';
import 'index.dart';
import 'manifest.dart';
import 'vault_header.dart';

class VaultCreated {
  const VaultCreated(this.vault, this.recoveryKey);

  final Vault vault;

  /// Shown to the user once. It opens the vault if the password is lost.
  final String recoveryKey;
}

class ImportResult {
  const ImportResult({
    required this.sourceId,
    required this.changes,
    required this.skipped,
    required this.newBlobs,
    required this.newBytes,
    required this.duplicatesAvoided,
    required this.duplicateBytes,
    required this.elapsed,
  });

  final String sourceId;
  final ChangeSet changes;
  final List<String> skipped;

  /// Contents stored for the first time, and their size before encryption.
  final int newBlobs;
  final int newBytes;

  /// Files in this run whose content was already in the vault.
  final int duplicatesAvoided;
  final int duplicateBytes;
  final Duration elapsed;

  int get added => changes.added;
  int get modified => changes.modified;
  int get moved => changes.moved;
  int get deleted => changes.deleted;
  int get unchanged => changes.unchanged;
}

/// An unlocked vault. Every file's content is read and written through it;
/// nothing in the vault folder is readable without the keys it holds.
class Vault {
  Vault._(this.directory, this._header, this._masterKey, this._keys, this._log, this.index);

  final String directory;
  VaultHeader _header;
  Uint8List? _masterKey;
  VaultKeys? _keys;
  final EventLog _log;
  final VaultIndex index;
  bool _importing = false;

  String get vaultId => _header.vaultId;
  DateTime get createdAt => _header.createdAt;
  bool get isLocked => _keys == null;
  bool get isImporting => _importing;
  String get _storeRoot => p.join(directory, 'blobs');

  static Future<bool> existsIn(String directory) => VaultHeader.existsIn(directory);

  /// Creates a vault in [directory], which must be empty or not exist yet.
  static Future<VaultCreated> create(String directory, String password,
      {KdfParams? kdf}) async {
    final dir = Directory(directory);
    if (await dir.exists()) {
      if (!await dir.list().isEmpty) {
        throw const VaultException('Choose an empty folder for a new vault.');
      }
    } else {
      await dir.create(recursive: true);
    }
    final vaultId = toHex(randomBytes(16));
    final masterKey = randomBytes(keyLength);
    final params = kdf ?? KdfParams.recommended();
    final passwordKey = await deriveKeyFromPassword(password, params);
    final recovery = randomBytes(recoveryKeyBytes);
    final recoverySalt = randomBytes(16);
    final recoveryKey = await hkdfSha256(recovery,
        salt: recoverySalt, info: 'phone-backup/v1/recovery');
    final header = VaultHeader(
      vaultId: vaultId,
      createdAt: DateTime.now().toUtc(),
      kdf: params,
      passwordSlot: await sealBox(passwordKey, masterKey,
          aad: slotAad(vaultId, 'password')),
      recoverySalt: recoverySalt,
      recoverySlot: await sealBox(recoveryKey, masterKey,
          aad: slotAad(vaultId, 'recovery')),
    );
    wipe(passwordKey);
    wipe(recoveryKey);
    await header.write(directory);
    await Directory(p.join(directory, 'blobs')).create();
    await EventLog.create(p.join(directory, 'log'));
    final vault = await _open(directory, header, masterKey);
    await vault._append([VaultEvent(type: EventType.vaultCreated, time: _now())]);
    final text = encodeRecoveryKey(recovery);
    wipe(recovery);
    return VaultCreated(vault, text);
  }

  static Future<Vault> unlockWithPassword(String directory, String password) async {
    final header = await VaultHeader.read(directory);
    final key = await deriveKeyFromPassword(password, header.kdf);
    final masterKey = await _unwrap(key, header.passwordSlot, header.vaultId,
        'password', 'That password does not open this vault.');
    return _open(directory, header, masterKey);
  }

  static Future<Vault> unlockWithRecoveryKey(String directory, String recoveryKey) async {
    final header = await VaultHeader.read(directory);
    final Uint8List recovery;
    try {
      recovery = decodeRecoveryKey(recoveryKey);
    } on FormatException catch (e) {
      throw WrongKeyException(e.message);
    }
    final key = await hkdfSha256(recovery,
        salt: header.recoverySalt, info: 'phone-backup/v1/recovery');
    final masterKey = await _unwrap(key, header.recoverySlot, header.vaultId,
        'recovery', 'That recovery key does not open this vault.');
    return _open(directory, header, masterKey);
  }

  static Future<Uint8List> _unwrap(Uint8List key, Uint8List slot, String vaultId,
      String slotName, String message) async {
    try {
      return await openBox(key, slot, aad: slotAad(vaultId, slotName));
    } on DecryptionFailed {
      throw WrongKeyException(message);
    } finally {
      wipe(key);
    }
  }

  static Future<Vault> _open(String directory, VaultHeader header, Uint8List masterKey) async {
    final keys = await VaultKeys.derive(masterKey, header.vaultId);
    final (log, events) = await EventLog.open(p.join(directory, 'log'), keys.logKey);
    // Leftovers of a backup that was interrupted before it finished.
    final temp = Directory(p.join(directory, 'blobs', 'tmp'));
    if (await temp.exists()) await temp.delete(recursive: true);
    return Vault._(directory, header, masterKey, keys, log, VaultIndex.fromEvents(events));
  }

  /// True if [password] is the vault's current password.
  Future<bool> checkPassword(String password) async {
    final key = await deriveKeyFromPassword(password, _header.kdf);
    try {
      await _unwrap(key, _header.passwordSlot, vaultId, 'password', '');
      return true;
    } on WrongKeyException {
      return false;
    }
  }

  /// Re-wraps the master key; no stored file needs re-encrypting.
  Future<void> changePassword(String newPassword) async {
    final masterKey = _requireMasterKey();
    final params = _header.kdf.withNewSalt();
    final key = await deriveKeyFromPassword(newPassword, params);
    final slot = await sealBox(key, masterKey, aad: slotAad(vaultId, 'password'));
    wipe(key);
    _header = _header.copyWith(kdf: params, passwordSlot: slot);
    await _header.write(directory);
    await _append([VaultEvent(type: EventType.passwordChanged, time: _now())]);
  }

  /// Backs up [folder]: new and changed files are encrypted (content already
  /// in the vault is not stored again), and every addition, change, move and
  /// deletion since the last run of this folder is logged.
  Future<ImportResult> importFolder(String folder,
      {void Function(ImportProgress progress)? onProgress}) async {
    final keys = _requireKeys();
    if (_importing) throw const VaultException('A backup is already running.');
    final root = p.normalize(p.absolute(folder));
    if (p.equals(root, directory) || p.isWithin(directory, root)) {
      throw const VaultException('That folder is inside the vault itself.');
    }
    if (!await Directory(root).exists()) {
      throw VaultException('Folder not found: $root');
    }
    _importing = true;
    final clock = Stopwatch()..start();
    final port = ReceivePort();
    final subscription = port.listen((message) {
      if (message is ImportProgress) onProgress?.call(message);
    });
    try {
      final existing = index.sources.values
          .where((s) => s.kind == 'folder' && s.location != null && p.equals(s.location!, root))
          .firstOrNull;
      final sourceId = existing?.id ?? 'folder-${toHex(randomBytes(6))}';
      final current = index.filesOf(sourceId);
      final scan = await scanAndStoreInBackground(ImportRequest(
        folder: root,
        excludeDir: directory,
        storeRoot: _storeRoot,
        blobKey: keys.blobKey,
        idKey: keys.idKey,
        known: {
          for (final f in current.values)
            f.path: KnownFile(f.size, f.modified.millisecondsSinceEpoch, f.sha256),
        },
        knownBlobIds: {for (final b in index.blobs.values) b.sha256: b.blobId},
        progress: port.sendPort,
      ));
      onProgress?.call(const ImportProgress(ImportPhase.saving, 0, 1));

      final now = _now();
      final changes = diffManifest(
        source: sourceId,
        current: current,
        manifest: scan.manifest,
        blobIds: scan.blobIds,
        now: now,
      );
      final duplicatesBefore = index.duplicatesAvoided;
      final duplicateBytesBefore = index.duplicateBytes;
      await _append([
        if (existing == null)
          VaultEvent(
            type: EventType.sourceAdded,
            time: now,
            source: sourceId,
            info: {'name': p.basename(root), 'kind': 'folder', 'location': root},
          ),
        ...changes.events,
        VaultEvent(
          type: EventType.snapshot,
          time: now,
          source: sourceId,
          info: {
            'added': changes.added,
            'modified': changes.modified,
            'moved': changes.moved,
            'deleted': changes.deleted,
            'unchanged': changes.unchanged,
            'skipped': scan.skipped.length,
            'newBytes': scan.newBytes,
          },
        ),
      ]);
      return ImportResult(
        sourceId: sourceId,
        changes: changes,
        skipped: scan.skipped,
        newBlobs: scan.newBlobs,
        newBytes: scan.newBytes,
        duplicatesAvoided: index.duplicatesAvoided - duplicatesBefore,
        duplicateBytes: index.duplicateBytes - duplicateBytesBefore,
        elapsed: clock.elapsed,
      );
    } finally {
      await subscription.cancel();
      port.close();
      _importing = false;
    }
  }

  /// Decrypts a file into memory, for viewing inside the app.
  Future<Uint8List> readFile(FileEntry file) =>
      _readInBackground(_storeRoot, _requireKeys().blobKey, file.blobId);

  /// Writes a normal, unencrypted copy of [file] to [destinationPath].
  Future<void> exportFile(FileEntry file, String destinationPath) =>
      _exportInBackground(_storeRoot, _requireKeys().blobKey, file.blobId, destinationPath);

  /// Forgets the keys and the decrypted index. Open the vault again to use it.
  void lock() {
    _keys?.wipeAll();
    _keys = null;
    wipe(_masterKey);
    _masterKey = null;
    index.clear();
  }

  Future<void> _append(List<VaultEvent> events) async {
    _requireKeys();
    for (final event in await _log.append(events)) {
      index.apply(event);
    }
  }

  VaultKeys _requireKeys() =>
      _keys ?? (throw const VaultException('The vault is locked.'));

  Uint8List _requireMasterKey() =>
      _masterKey ?? (throw const VaultException('The vault is locked.'));
}

DateTime _now() => DateTime.now().toUtc();

Future<Uint8List> _readInBackground(String storeRoot, Uint8List key, String blobId) =>
    Isolate.run(() => readBlob(storeRoot: storeRoot, blobKey: key, blobId: blobId));

Future<void> _exportInBackground(
        String storeRoot, Uint8List key, String blobId, String destination) =>
    Isolate.run(() => exportBlob(
        storeRoot: storeRoot, blobKey: key, blobId: blobId, destinationPath: destination));

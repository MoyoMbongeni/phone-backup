import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'bytes.dart';
import 'cipher.dart';
import 'crypto_backend.dart';
import 'errors.dart';

// Blob file layout:
//   "PBB1" | version (1 byte) | chunk size (u32)
//   then per chunk: final flag (1 byte) | length (u32) | nonce | ciphertext | tag
// Each chunk is sealed separately so large videos never sit in memory whole.
// The additional data binds every chunk to its blob id, its position and
// whether it is the last one, so chunks cannot be reordered, swapped between
// blobs or cut off without the read failing.

const int blobChunkSize = 1 << 20;
final Uint8List _magic = ascii.encode('PBB1');
const int _version = 1;
const int _headerLength = 9;
const int _frameHeaderLength = 5;

String blobPath(String storeRoot, String blobId) =>
    p.join(storeRoot, blobId.substring(0, 2), '$blobId.blob');

Uint8List _chunkAad(String blobId, int index, bool isFinal) => concatBytes([
      _magic,
      ascii.encode(blobId),
      uint64Bytes(index),
      [isFinal ? 1 : 0],
    ]);

Future<String> sha256OfFile(String path) async {
  final hasher = cryptoBackend.sha256();
  final raf = await File(path).open();
  Uint8List digest;
  try {
    while (true) {
      final chunk = await raf.read(blobChunkSize);
      if (chunk.isEmpty) break;
      hasher.add(chunk);
    }
  } finally {
    digest = hasher.close();
    await raf.close();
  }
  return toHex(digest);
}

class BlobWriteResult {
  const BlobWriteResult({required this.storedBytes, required this.created});

  /// Size of the encrypted file on disk.
  final int storedBytes;

  /// False when the blob was already there, e.g. from an interrupted run.
  final bool created;
}

/// Encrypts [sourcePath] into the store under [blobId]. The content is
/// hashed again while it is read; if it no longer matches [expectedSha256]
/// the file changed since it was scanned, nothing is kept and
/// [ContentChangedException] is thrown.
Future<BlobWriteResult> writeBlob({
  required String storeRoot,
  required Uint8List blobKey,
  required String blobId,
  required String sourcePath,
  required String expectedSha256,
}) async {
  final target = File(blobPath(storeRoot, blobId));
  if (await target.exists()) {
    return BlobWriteResult(storedBytes: await target.length(), created: false);
  }
  final tempDir = Directory(p.join(storeRoot, 'tmp'));
  await tempDir.create(recursive: true);
  final temp = File(p.join(tempDir.path, '${toHex(randomBytes(8))}.part'));

  final hasher = cryptoBackend.sha256();
  Uint8List? digest;
  var stored = 0;
  final input = await File(sourcePath).open();
  final output = await temp.open(mode: FileMode.write);
  try {
    final length = await input.length();
    final chunkCount =
        length == 0 ? 1 : (length + blobChunkSize - 1) ~/ blobChunkSize;
    await output.writeFrom(concatBytes([_magic, [_version], uint32Bytes(blobChunkSize)]));
    stored = _headerLength;
    for (var i = 0; i < chunkCount; i++) {
      final plain = await input.read(blobChunkSize);
      hasher.add(plain);
      final isFinal = i == chunkCount - 1;
      final sealed = await sealBox(blobKey, plain, aad: _chunkAad(blobId, i, isFinal));
      await output.writeFrom(
          concatBytes([[isFinal ? 1 : 0], uint32Bytes(sealed.length), sealed]));
      stored += _frameHeaderLength + sealed.length;
    }
    digest = hasher.close();
    await output.flush();
  } catch (_) {
    if (digest == null) hasher.close();
    await output.close();
    await input.close();
    if (await temp.exists()) await temp.delete();
    rethrow;
  }
  await output.close();
  await input.close();

  if (toHex(digest) != expectedSha256) {
    await temp.delete();
    throw ContentChangedException(sourcePath);
  }
  await target.parent.create(recursive: true);
  try {
    await temp.rename(target.path);
  } on FileSystemException {
    // Another run stored the same content meanwhile; keep that copy.
    if (!await target.exists()) rethrow;
    await temp.delete();
  }
  return BlobWriteResult(storedBytes: stored, created: true);
}

/// Decrypts a blob chunk by chunk.
Stream<Uint8List> decryptBlob({
  required String storeRoot,
  required Uint8List blobKey,
  required String blobId,
}) async* {
  final file = File(blobPath(storeRoot, blobId));
  if (!await file.exists()) {
    throw VaultCorruptException('The stored data for this file is missing (blob $blobId).');
  }
  const damaged = VaultCorruptException(
      'The stored data for this file is damaged or was changed outside the app.');
  final raf = await file.open();
  try {
    final header = await raf.read(_headerLength);
    if (header.length != _headerLength ||
        !startsWith(header, _magic) ||
        header[4] != _version) {
      throw damaged;
    }
    final maxFrame = readUint32(header, 5) + nonceLength + macLength;
    var index = 0;
    var finished = false;
    while (true) {
      final frameHeader = await raf.read(_frameHeaderLength);
      if (frameHeader.isEmpty) break;
      if (finished || frameHeader.length != _frameHeaderLength || frameHeader[0] > 1) {
        throw damaged;
      }
      final isFinal = frameHeader[0] == 1;
      final length = readUint32(frameHeader, 1);
      if (length < nonceLength + macLength || length > maxFrame) throw damaged;
      final sealed = await raf.read(length);
      if (sealed.length != length) throw damaged;
      final Uint8List plain;
      try {
        plain = await openBox(blobKey, sealed, aad: _chunkAad(blobId, index, isFinal));
      } on DecryptionFailed {
        throw damaged;
      }
      yield plain;
      index++;
      finished = isFinal;
    }
    if (!finished) throw damaged;
  } finally {
    await raf.close();
  }
}

Future<Uint8List> readBlob({
  required String storeRoot,
  required Uint8List blobKey,
  required String blobId,
}) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk
      in decryptBlob(storeRoot: storeRoot, blobKey: blobKey, blobId: blobId)) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

/// Writes the decrypted content to [destinationPath]. A damaged blob leaves
/// no partial file behind.
Future<void> exportBlob({
  required String storeRoot,
  required Uint8List blobKey,
  required String blobId,
  required String destinationPath,
}) async {
  final temp = File('$destinationPath.part');
  final sink = temp.openWrite();
  try {
    await for (final chunk
        in decryptBlob(storeRoot: storeRoot, blobKey: blobKey, blobId: blobId)) {
      sink.add(chunk);
    }
  } catch (_) {
    await sink.close();
    if (await temp.exists()) await temp.delete();
    rethrow;
  }
  await sink.close();
  final destination = File(destinationPath);
  if (await destination.exists()) await destination.delete();
  await temp.rename(destinationPath);
}

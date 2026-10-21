import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'bytes.dart';
import 'crypto_backend.dart';
import 'errors.dart';

const int keyLength = 32;

// AES-256-GCM with a random 96-bit nonce per message. Every blob chunk is
// one message, so the 2^32-message limit per key is 4 PiB of backups.
const int nonceLength = gcmNonceLength;
const int macLength = gcmTagLength;

/// Argon2id settings stored in the vault header. Parallelism stays 1 so
/// libsodium's crypto_pwhash can derive the same key.
class KdfParams {
  const KdfParams({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
    required this.salt,
  });

  factory KdfParams.recommended() => KdfParams(
      memoryKiB: 64 * 1024, iterations: 3, parallelism: 1, salt: randomBytes(16));

  /// Cheap settings for unit tests only.
  factory KdfParams.forTests() =>
      KdfParams(memoryKiB: 64, iterations: 1, parallelism: 1, salt: randomBytes(16));

  factory KdfParams.fromJson(Map<String, dynamic> json) {
    if (json['alg'] != 'argon2id') {
      throw VaultCorruptException('Unsupported key derivation "${json['alg']}".');
    }
    return KdfParams(
      memoryKiB: json['memoryKiB'] as int,
      iterations: json['iterations'] as int,
      parallelism: json['parallelism'] as int,
      salt: base64Decode(json['salt'] as String),
    );
  }

  final int memoryKiB;
  final int iterations;
  final int parallelism;
  final Uint8List salt;

  KdfParams withNewSalt() => KdfParams(
      memoryKiB: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
      salt: randomBytes(16));

  Map<String, Object?> toJson() => {
        'alg': 'argon2id',
        'memoryKiB': memoryKiB,
        'iterations': iterations,
        'parallelism': parallelism,
        'salt': base64Encode(salt),
      };
}

/// Derives the key-encryption key from a password. Argon2id is slow on
/// purpose, so it runs in a background isolate to keep the UI responsive.
Future<Uint8List> deriveKeyFromPassword(String password, KdfParams params) {
  final passwordBytes = Uint8List.fromList(utf8.encode(password));
  final salt = params.salt;
  final memory = params.memoryKiB;
  final iterations = params.iterations;
  final parallelism = params.parallelism;
  return Isolate.run(
      () => _argon2id(passwordBytes, salt, memory, iterations, parallelism));
}

Future<Uint8List> _argon2id(Uint8List password, Uint8List salt, int memory,
    int iterations, int parallelism) async {
  final algorithm = Argon2id(
    parallelism: parallelism,
    memory: memory,
    iterations: iterations,
    hashLength: keyLength,
  );
  final key =
      await algorithm.deriveKey(secretKey: SecretKeyData(password), nonce: salt);
  return asBytes(await key.extractBytes());
}

/// Encrypts [plain] and returns nonce | ciphertext | tag.
Future<Uint8List> sealBox(Uint8List key, List<int> plain, {List<int> aad = const []}) =>
    cryptoBackend.seal(key, randomBytes(nonceLength), plain, aad);

/// Reverses [sealBox]. Throws [DecryptionFailed] for a wrong key, a wrong
/// [aad] or any modified byte.
Future<Uint8List> openBox(Uint8List key, Uint8List sealed,
    {List<int> aad = const []}) async {
  final plain = await cryptoBackend.open(key, sealed, aad);
  if (plain == null) throw const DecryptionFailed();
  return plain;
}

Future<Uint8List> hkdfSha256(Uint8List inputKey,
    {required List<int> salt, required String info}) async {
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: keyLength);
  final key = await hkdf.deriveKey(
    secretKey: SecretKeyData(inputKey),
    nonce: salt,
    info: utf8.encode(info),
  );
  return asBytes(await key.extractBytes());
}

Future<Uint8List> hmacSha256(Uint8List key, List<int> data) async {
  final mac = await Hmac.sha256().calculateMac(data, secretKey: SecretKeyData(key));
  return asBytes(mac.bytes);
}

/// Name of the blob holding content with this SHA-256. Keyed, so the file
/// names in `blobs/` do not reveal which well-known files the vault holds.
Future<String> blobIdFor(Uint8List idKey, String sha256Hex) async =>
    toHex(await hmacSha256(idKey, ascii.encode(sha256Hex)));

/// Additional data binding a wrapped master key to its vault and slot.
List<int> slotAad(String vaultId, String slot) =>
    utf8.encode('phone-backup/v1/slot|$vaultId|$slot');

/// Subkeys derived from the vault's random master key, one per purpose.
class VaultKeys {
  VaultKeys._(this.blobKey, this.idKey, this.logKey);

  final Uint8List blobKey;
  final Uint8List idKey;
  final Uint8List logKey;

  static Future<VaultKeys> derive(Uint8List masterKey, String vaultId) async {
    final salt = utf8.encode(vaultId);
    return VaultKeys._(
      await hkdfSha256(masterKey, salt: salt, info: 'phone-backup/v1/blob'),
      await hkdfSha256(masterKey, salt: salt, info: 'phone-backup/v1/blob-id'),
      await hkdfSha256(masterKey, salt: salt, info: 'phone-backup/v1/log'),
    );
  }

  void wipeAll() {
    wipe(blobKey);
    wipe(idKey);
    wipe(logKey);
  }
}

// Recovery keys: 20 random bytes written as 32 Crockford base32 characters
// in groups of four. The alphabet has no I, L, O or U, so a hand-copied key
// cannot be misread.
const int recoveryKeyBytes = 20;
const int recoveryKeyLength = 32;
const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

String encodeRecoveryKey(Uint8List bytes) {
  final chars = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final b in bytes) {
    buffer = (buffer << 8) | b;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      chars.write(_alphabet[(buffer >> bits) & 31]);
    }
    buffer &= (1 << bits) - 1;
  }
  if (bits > 0) chars.write(_alphabet[(buffer << (5 - bits)) & 31]);
  final text = chars.toString();
  return [
    for (var i = 0; i < text.length; i += 4)
      text.substring(i, i + 4 > text.length ? text.length : i + 4),
  ].join('-');
}

Uint8List decodeRecoveryKey(String text) {
  final cleaned = text
      .toUpperCase()
      .replaceAll(RegExp(r'[\s-]'), '')
      .replaceAll('O', '0')
      .replaceAll(RegExp('[IL]'), '1');
  if (cleaned.length != recoveryKeyLength) {
    throw const FormatException(
        'A recovery key has 32 letters and digits (dashes are optional).');
  }
  final out = BytesBuilder();
  var buffer = 0;
  var bits = 0;
  for (var i = 0; i < cleaned.length; i++) {
    final value = _alphabet.indexOf(cleaned[i]);
    if (value < 0) {
      throw FormatException('"${cleaned[i]}" cannot appear in a recovery key.');
    }
    buffer = (buffer << 5) | value;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.addByte((buffer >> bits) & 0xff);
      buffer &= (1 << bits) - 1;
    }
  }
  return out.takeBytes();
}

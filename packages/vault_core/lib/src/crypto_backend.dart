import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashing;
import 'package:cryptography/cryptography.dart';

import 'bytes.dart';
import 'windows_cng.dart';

const int gcmNonceLength = 12;
const int gcmTagLength = 16;

/// AES-256-GCM and SHA-256: the two operations every byte of a backup goes
/// through. On Windows they run in the OS crypto library (CNG, hardware
/// accelerated). Elsewhere a much slower pure-Dart version produces exactly
/// the same bytes, so a vault opens with either.
abstract interface class CryptoBackend {
  String get name;

  /// Returns nonce | ciphertext | tag.
  Future<Uint8List> seal(Uint8List key, Uint8List nonce, List<int> plain, List<int> aad);

  /// Returns null if [sealed] does not authenticate under [key] and [aad].
  Future<Uint8List?> open(Uint8List key, Uint8List sealed, List<int> aad);

  Sha256Sink sha256();
}

abstract interface class Sha256Sink {
  void add(List<int> data);

  /// Returns the digest and releases the hasher.
  Uint8List close();
}

CryptoBackend? _selected;

/// The backend for this isolate, chosen on first use.
CryptoBackend get cryptoBackend => _selected ??=
    (Platform.isWindows ? WindowsCngBackend.tryCreate() : null) ?? DartCryptoBackend();

class DartCryptoBackend implements CryptoBackend {
  final Cipher _aes = AesGcm.with256bits();

  @override
  String get name => 'pure Dart';

  @override
  Future<Uint8List> seal(
      Uint8List key, Uint8List nonce, List<int> plain, List<int> aad) async {
    final box =
        await _aes.encrypt(plain, secretKey: SecretKeyData(key), nonce: nonce, aad: aad);
    return asBytes(box.concatenation());
  }

  @override
  Future<Uint8List?> open(Uint8List key, Uint8List sealed, List<int> aad) async {
    if (sealed.length < gcmNonceLength + gcmTagLength) return null;
    final box = SecretBox.fromConcatenation(sealed,
        nonceLength: gcmNonceLength, macLength: gcmTagLength, copy: false);
    try {
      return asBytes(await _aes.decrypt(box, secretKey: SecretKeyData(key), aad: aad));
    } on SecretBoxAuthenticationError {
      return null;
    }
  }

  @override
  Sha256Sink sha256() => _DartSha256();
}

class _DartSha256 implements Sha256Sink {
  _DartSha256() {
    _input = hashing.sha256.startChunkedConversion(_output);
  }

  final _DigestSink _output = _DigestSink();
  late final ByteConversionSink _input;

  @override
  void add(List<int> data) => _input.add(data);

  @override
  Uint8List close() {
    _input.close();
    return Uint8List.fromList(_output.value!.bytes);
  }
}

class _DigestSink implements Sink<hashing.Digest> {
  hashing.Digest? value;

  @override
  void add(hashing.Digest data) => value = data;

  @override
  void close() {}
}

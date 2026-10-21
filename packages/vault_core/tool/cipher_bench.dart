// Compares the pure-Dart ciphers and hashes on 1 MiB chunks:
//   dart compile exe tool/cipher_bench.dart && run it
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashing;
import 'package:cryptography/cryptography.dart';

Future<void> main() async {
  const rounds = 32;
  final chunk = Uint8List(1 << 20);
  for (var i = 0; i < chunk.length; i++) {
    chunk[i] = i * 31;
  }
  final key32 = SecretKeyData(List.filled(32, 7));

  Future<void> time(String name, Future<void> Function() body) async {
    await body();
    final clock = Stopwatch()..start();
    for (var i = 0; i < rounds; i++) {
      await body();
    }
    final ms = clock.elapsedMilliseconds;
    print('${name.padRight(28)} ${(rounds * 1000 / ms).toStringAsFixed(1).padLeft(7)} MiB/s');
  }

  final ciphers = <String, Cipher>{
    'XChaCha20-Poly1305': Xchacha20.poly1305Aead(),
    'ChaCha20-Poly1305': Chacha20.poly1305Aead(),
    'AES-256-GCM': AesGcm.with256bits(),
    'AES-256-CTR (no MAC)': AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty),
  };
  for (final entry in ciphers.entries) {
    final nonce = entry.value.newNonce();
    await time('${entry.key} encrypt', () async {
      await entry.value.encrypt(chunk, secretKey: key32, nonce: nonce);
    });
  }
  await time('SHA-256 (package:crypto)', () async {
    hashing.sha256.convert(chunk);
  });
  await time('SHA-256 (cryptography)', () async {
    await Sha256().hash(chunk);
  });
  await time('BLAKE2b (cryptography)', () async {
    await Blake2b().hash(chunk);
  });
}

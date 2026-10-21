import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vault_core/src/bytes.dart';
import 'package:vault_core/src/crypto_backend.dart';
import 'package:vault_core/src/windows_cng.dart';

void main() {
  final backends = <CryptoBackend>[
    DartCryptoBackend(),
    if (Platform.isWindows) WindowsCngBackend.tryCreate()!,
  ];

  test('Windows uses the native backend', () {
    expect(cryptoBackend.name, Platform.isWindows ? 'Windows CNG' : 'pure Dart');
  }, testOn: 'windows');

  for (final backend in backends) {
    group(backend.name, () {
      // Test cases 13 and 14 of the GCM specification (McGrew & Viega).
      test('matches the published AES-256-GCM test vectors', () async {
        final key = Uint8List(32);
        final nonce = Uint8List(12);
        final empty = await backend.seal(key, nonce, const [], const []);
        expect(toHex(empty.sublist(12)), '530f8afbc74536b9a963b4f1c4cb738b');
        final block = await backend.seal(key, nonce, Uint8List(16), const []);
        expect(toHex(block.sublist(12)),
            'cea7403d4d606b6e074ec5d3baf39d18d0d1c8a799996bf0265b98b5d48ab919');
      });

      test('matches the published SHA-256 vectors, however the input is split', () {
        final abc = backend.sha256()..add(utf8.encode('abc'));
        expect(toHex(abc.close()),
            'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
        final split = backend.sha256()
          ..add(utf8.encode('a'))
          ..add(const [])
          ..add(utf8.encode('bc'));
        expect(toHex(split.close()),
            'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
        expect(toHex(backend.sha256().close()),
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      });

      test('rejects a wrong key, wrong additional data or a flipped bit', () async {
        final key = randomBytes(32);
        final sealed = await backend.seal(key, randomBytes(12), utf8.encode('hello'), [1, 2]);
        expect(utf8.decode((await backend.open(key, sealed, [1, 2]))!), 'hello');
        expect(await backend.open(randomBytes(32), sealed, [1, 2]), isNull);
        expect(await backend.open(key, sealed, [1, 3]), isNull);
        final flipped = Uint8List.fromList(sealed)..[14] ^= 1;
        expect(await backend.open(key, flipped, [1, 2]), isNull);
        expect(await backend.open(key, Uint8List(10), const []), isNull);
      });
    });
  }

  test('both backends read what the other wrote', () async {
    if (backends.length < 2) return;
    final key = randomBytes(32);
    for (final length in [0, 1, 1000, (1 << 20) + 5]) {
      final plain = randomBytes(length);
      for (final writer in backends) {
        final sealed = await writer.seal(key, randomBytes(12), plain, [9]);
        for (final reader in backends) {
          expect(await reader.open(key, sealed, [9]), plain,
              reason: '${writer.name} -> ${reader.name}, $length bytes');
        }
      }
    }
  });
}

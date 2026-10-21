import 'dart:ffi';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'crypto_backend.dart';

// Windows CNG (bcrypt.dll), called through dart:ffi. It uses the algorithm
// pseudo-handles of Windows 10 and later, which need no opening or closing,
// so the short-lived isolates that read and write blobs leak nothing. Key
// and hash objects are allocated by CNG itself (null object buffers).

final Pointer<Void> _aesGcmAlgorithm = Pointer.fromAddress(0x1e1); // BCRYPT_AES_GCM_ALG_HANDLE
final Pointer<Void> _sha256Algorithm = Pointer.fromAddress(0x41); // BCRYPT_SHA256_ALG_HANDLE

typedef _GenerateKeyC = Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>,
    Pointer<Uint8>, Uint32, Pointer<Uint8>, Uint32, Uint32);
typedef _GenerateKey = int Function(
    Pointer<Void>, Pointer<Pointer<Void>>, Pointer<Uint8>, int, Pointer<Uint8>, int, int);
typedef _CryptC = Int32 Function(Pointer<Void>, Pointer<Uint8>, Uint32, Pointer<Void>,
    Pointer<Uint8>, Uint32, Pointer<Uint8>, Uint32, Pointer<Uint32>, Uint32);
typedef _Crypt = int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Void>,
    Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint32>, int);
typedef _DestroyC = Int32 Function(Pointer<Void>);
typedef _Destroy = int Function(Pointer<Void>);
typedef _CreateHashC = Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>,
    Pointer<Uint8>, Uint32, Pointer<Uint8>, Uint32, Uint32);
typedef _CreateHash = int Function(
    Pointer<Void>, Pointer<Pointer<Void>>, Pointer<Uint8>, int, Pointer<Uint8>, int, int);
typedef _HashDataC = Int32 Function(Pointer<Void>, Pointer<Uint8>, Uint32, Uint32);
typedef _HashData = int Function(Pointer<Void>, Pointer<Uint8>, int, int);

/// BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO
final class _AuthInfo extends Struct {
  @Uint32()
  external int cbSize;
  @Uint32()
  external int dwInfoVersion;
  external Pointer<Uint8> pbNonce;
  @Uint32()
  external int cbNonce;
  external Pointer<Uint8> pbAuthData;
  @Uint32()
  external int cbAuthData;
  external Pointer<Uint8> pbTag;
  @Uint32()
  external int cbTag;
  external Pointer<Uint8> pbMacContext;
  @Uint32()
  external int cbMacContext;
  @Uint32()
  external int cbAAD;
  @Uint64()
  external int cbData;
  @Uint32()
  external int dwFlags;
}

const int _statusAuthTagMismatch = 0xC000A002 - 0x100000000;

class _Bcrypt {
  _Bcrypt(DynamicLibrary lib)
      : generateSymmetricKey =
            lib.lookupFunction<_GenerateKeyC, _GenerateKey>('BCryptGenerateSymmetricKey'),
        encrypt = lib.lookupFunction<_CryptC, _Crypt>('BCryptEncrypt'),
        decrypt = lib.lookupFunction<_CryptC, _Crypt>('BCryptDecrypt'),
        destroyKey = lib.lookupFunction<_DestroyC, _Destroy>('BCryptDestroyKey'),
        createHash = lib.lookupFunction<_CreateHashC, _CreateHash>('BCryptCreateHash'),
        hashData = lib.lookupFunction<_HashDataC, _HashData>('BCryptHashData'),
        finishHash = lib.lookupFunction<_HashDataC, _HashData>('BCryptFinishHash'),
        destroyHash = lib.lookupFunction<_DestroyC, _Destroy>('BCryptDestroyHash');

  final _GenerateKey generateSymmetricKey;
  final _Crypt encrypt;
  final _Crypt decrypt;
  final _Destroy destroyKey;
  final _CreateHash createHash;
  final _HashData hashData;
  final _HashData finishHash;
  final _Destroy destroyHash;

  /// Imports [key] and wipes the native copy of it.
  Pointer<Void> importKey(Arena arena, Uint8List key) {
    final handle = arena<Pointer<Void>>();
    final secret = _copy(arena, key);
    try {
      _check(generateSymmetricKey(_aesGcmAlgorithm, handle, nullptr, 0, secret, key.length, 0),
          'BCryptGenerateSymmetricKey');
    } finally {
      secret.asTypedList(key.length).fillRange(0, key.length, 0);
    }
    return handle.value;
  }
}

class WindowsCngBackend implements CryptoBackend {
  WindowsCngBackend._(this._api);

  /// Null unless bcrypt.dll is there and gives the published answers for an
  /// AES-256-GCM and a SHA-256 test vector, so a misbehaving native library
  /// can never write a vault that will not read back.
  static WindowsCngBackend? tryCreate() {
    try {
      final backend = WindowsCngBackend._(_Bcrypt(DynamicLibrary.open('bcrypt.dll')));
      final tag = backend._seal(Uint8List(32), Uint8List(gcmNonceLength), const [], const []);
      final abc = backend.sha256()..add(const [0x61, 0x62, 0x63]);
      final works = _hex(tag.sublist(gcmNonceLength)) == '530f8afbc74536b9a963b4f1c4cb738b' &&
          _hex(abc.close()) ==
              'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
      return works ? backend : null;
    } catch (_) {
      return null;
    }
  }

  final _Bcrypt _api;

  @override
  String get name => 'Windows CNG';

  @override
  Future<Uint8List> seal(
          Uint8List key, Uint8List nonce, List<int> plain, List<int> aad) async =>
      _seal(key, nonce, plain, aad);

  @override
  Future<Uint8List?> open(Uint8List key, Uint8List sealed, List<int> aad) async =>
      _open(key, sealed, aad);

  @override
  Sha256Sink sha256() => _CngSha256(_api);

  Uint8List _seal(Uint8List key, Uint8List nonce, List<int> plain, List<int> aad) {
    return using((arena) {
      final keyHandle = _api.importKey(arena, key);
      try {
        final length = plain.length;
        final output = arena<Uint8>(max(length, 1));
        final tag = arena<Uint8>(gcmTagLength);
        final info = _authInfo(arena, _copy(arena, nonce), nonce.length,
            aad.isEmpty ? nullptr : _copy(arena, aad), aad.length, tag);
        _check(
            _api.encrypt(keyHandle, _copy(arena, plain), length, info.cast(), nullptr, 0,
                output, length, arena<Uint32>(), 0),
            'BCryptEncrypt');
        final sealed = Uint8List(nonce.length + length + gcmTagLength);
        sealed
          ..setRange(0, nonce.length, nonce)
          ..setRange(nonce.length, nonce.length + length, output.asTypedList(length))
          ..setRange(nonce.length + length, sealed.length, tag.asTypedList(gcmTagLength));
        return sealed;
      } finally {
        _api.destroyKey(keyHandle);
      }
    }, malloc);
  }

  Uint8List? _open(Uint8List key, Uint8List sealed, List<int> aad) {
    final length = sealed.length - gcmNonceLength - gcmTagLength;
    if (length < 0) return null;
    return using((arena) {
      final keyHandle = _api.importKey(arena, key);
      try {
        final nonce = _copy(arena, Uint8List.sublistView(sealed, 0, gcmNonceLength));
        final input = _copy(
            arena, Uint8List.sublistView(sealed, gcmNonceLength, gcmNonceLength + length));
        final tag = _copy(arena, Uint8List.sublistView(sealed, gcmNonceLength + length));
        final output = arena<Uint8>(max(length, 1));
        final info = _authInfo(arena, nonce, gcmNonceLength,
            aad.isEmpty ? nullptr : _copy(arena, aad), aad.length, tag);
        final status = _api.decrypt(keyHandle, input, length, info.cast(), nullptr, 0,
            output, length, arena<Uint32>(), 0);
        if (status == _statusAuthTagMismatch) return null;
        _check(status, 'BCryptDecrypt');
        return Uint8List.fromList(output.asTypedList(length));
      } finally {
        _api.destroyKey(keyHandle);
      }
    }, malloc);
  }
}

class _CngSha256 implements Sha256Sink {
  _CngSha256(this._api) {
    final handle = malloc<Pointer<Void>>();
    try {
      _check(_api.createHash(_sha256Algorithm, handle, nullptr, 0, nullptr, 0, 0),
          'BCryptCreateHash');
      _hash = handle.value;
    } finally {
      malloc.free(handle);
    }
  }

  final _Bcrypt _api;
  late final Pointer<Void> _hash;

  @override
  void add(List<int> data) {
    if (data.isEmpty) return;
    using((arena) {
      _check(_api.hashData(_hash, _copy(arena, data), data.length, 0), 'BCryptHashData');
    }, malloc);
  }

  @override
  Uint8List close() {
    try {
      return using((arena) {
        final digest = arena<Uint8>(32);
        _check(_api.finishHash(_hash, digest, 32, 0), 'BCryptFinishHash');
        return Uint8List.fromList(digest.asTypedList(32));
      }, malloc);
    } finally {
      _api.destroyHash(_hash);
    }
  }
}

Pointer<_AuthInfo> _authInfo(Arena arena, Pointer<Uint8> nonce, int nonceLength,
    Pointer<Uint8> aad, int aadLength, Pointer<Uint8> tag) {
  final info = arena<_AuthInfo>();
  info.ref
    ..cbSize = sizeOf<_AuthInfo>()
    ..dwInfoVersion = 1
    ..pbNonce = nonce
    ..cbNonce = nonceLength
    ..pbAuthData = aad
    ..cbAuthData = aadLength
    ..pbTag = tag
    ..cbTag = gcmTagLength
    ..pbMacContext = nullptr
    ..cbMacContext = 0
    ..cbAAD = 0
    ..cbData = 0
    ..dwFlags = 0;
  return info;
}

Pointer<Uint8> _copy(Allocator allocator, List<int> bytes) {
  final pointer = allocator<Uint8>(max(bytes.length, 1));
  pointer.asTypedList(bytes.length).setAll(0, bytes);
  return pointer;
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void _check(int status, String call) {
  if (status < 0) {
    throw StateError(
        '$call failed with NTSTATUS 0x${(status & 0xffffffff).toRadixString(16)}');
  }
}

import 'dart:math';
import 'dart:typed_data';

final Random _random = Random.secure();

/// Cryptographically secure random bytes.
Uint8List randomBytes(int length) {
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = _random.nextInt(256);
  }
  return out;
}

String toHex(List<int> bytes) {
  const digits = '0123456789abcdef';
  final buffer = StringBuffer();
  for (final b in bytes) {
    buffer
      ..write(digits[b >> 4])
      ..write(digits[b & 0x0f]);
  }
  return buffer.toString();
}

Uint8List uint32Bytes(int value) {
  final out = Uint8List(4);
  ByteData.sublistView(out).setUint32(0, value);
  return out;
}

Uint8List uint64Bytes(int value) {
  final out = Uint8List(8);
  ByteData.sublistView(out).setUint64(0, value);
  return out;
}

int readUint32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes).getUint32(offset);

Uint8List concatBytes(List<List<int>> parts) {
  final builder = BytesBuilder(copy: false);
  for (final part in parts) {
    builder.add(part);
  }
  return builder.takeBytes();
}

bool startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

Uint8List asBytes(List<int> bytes) =>
    bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

/// Overwrites key material before it is dropped. Dart cannot promise that no
/// other copy exists, but this stops the obvious one from lingering.
void wipe(Uint8List? bytes) => bytes?.fillRange(0, bytes.length, 0);

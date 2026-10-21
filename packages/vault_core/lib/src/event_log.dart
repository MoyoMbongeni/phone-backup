import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'bytes.dart';
import 'cipher.dart';
import 'errors.dart';
import 'events.dart';

// Log file layout: "PBL1", then records of length (u32) | nonce | ciphertext | tag.
// A record holds a JSON list of events written together, so one backup run
// is committed all at once. The record number is the additional data, so
// records cannot be reordered or removed from the middle unnoticed.

final Uint8List _magic = ascii.encode('PBL1');

Uint8List _recordAad(int record) => concatBytes([_magic, uint64Bytes(record)]);

/// The vault's append-only, encrypted change log.
class EventLog {
  EventLog._(this._file, this._key, this._nextSeq, this._records);

  static const fileName = 'events.pblog';

  final File _file;
  final Uint8List _key;
  int _nextSeq;
  int _records;

  static Future<void> create(String logDir) async {
    await Directory(logDir).create(recursive: true);
    await File(p.join(logDir, fileName)).writeAsBytes(_magic, flush: true);
  }

  /// Opens the log and decrypts every event in a background isolate.
  static Future<(EventLog, List<VaultEvent>)> open(
      String logDir, Uint8List key) async {
    final path = p.join(logDir, fileName);
    final loaded = await Isolate.run(() => _load(path, key));
    final events = loaded.events;
    final nextSeq = events.isEmpty ? 1 : events.last.seq + 1;
    return (EventLog._(File(path), key, nextSeq, loaded.records), events);
  }

  /// Numbers [events], writes them as one record and flushes it to disk.
  Future<List<VaultEvent>> append(List<VaultEvent> events) async {
    if (events.isEmpty) return const [];
    var seq = _nextSeq;
    final stamped = [for (final event in events) event.withSeq(seq++)];
    final plain = utf8.encode(jsonEncode([for (final e in stamped) e.toJson()]));
    final sealed = await sealBox(_key, plain, aad: _recordAad(_records));
    final raf = await _file.open(mode: FileMode.append);
    try {
      await raf.writeFrom(concatBytes([uint32Bytes(sealed.length), sealed]));
      await raf.flush();
    } finally {
      await raf.close();
    }
    _nextSeq = seq;
    _records++;
    return stamped;
  }
}

class _LoadedLog {
  const _LoadedLog(this.events, this.records);

  final List<VaultEvent> events;
  final int records;
}

Future<_LoadedLog> _load(String path, Uint8List key) async {
  final file = File(path);
  if (!await file.exists()) {
    throw const VaultCorruptException('The change log (log/events.pblog) is missing.');
  }
  final bytes = await file.readAsBytes();
  if (!startsWith(bytes, _magic)) {
    throw const VaultCorruptException('The change log is not a Phone Backup log.');
  }
  const damaged = VaultCorruptException(
      'The change log is damaged or was changed outside the app.');
  final events = <VaultEvent>[];
  var offset = _magic.length;
  var records = 0;
  while (offset < bytes.length) {
    if (bytes.length - offset < 4) break;
    final length = readUint32(bytes, offset);
    final end = offset + 4 + length;
    if (end > bytes.length) break;
    final Uint8List plain;
    try {
      plain = await openBox(key, Uint8List.sublistView(bytes, offset + 4, end),
          aad: _recordAad(records));
    } on DecryptionFailed {
      // Only a last record after at least one good one can be a torn write.
      if (end == bytes.length && records > 0) break;
      throw damaged;
    }
    for (final item in jsonDecode(utf8.decode(plain)) as List<dynamic>) {
      events.add(VaultEvent.fromJson(item as Map<String, dynamic>));
    }
    offset = end;
    records++;
  }
  if (offset < bytes.length) {
    // The app or the PC stopped while a record was being written; that run
    // was never committed, so drop the partial record.
    final raf = await file.open(mode: FileMode.append);
    try {
      await raf.truncate(offset);
    } finally {
      await raf.close();
    }
  }
  for (var i = 0; i < events.length; i++) {
    if (events[i].seq != i + 1) throw damaged;
  }
  return _LoadedLog(events, records);
}

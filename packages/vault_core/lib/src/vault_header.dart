import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'cipher.dart';
import 'errors.dart';

/// `vault.json`: the only plaintext file in a vault. It holds the master key
/// twice, once wrapped by the password and once by the recovery key, plus
/// the Argon2id settings. It names no files and holds no content.
class VaultHeader {
  const VaultHeader({
    required this.vaultId,
    required this.createdAt,
    required this.kdf,
    required this.passwordSlot,
    required this.recoverySalt,
    required this.recoverySlot,
  });

  factory VaultHeader.fromJson(Map<String, dynamic> json) {
    if (json['format'] != format) {
      throw const VaultException('This folder does not contain a Phone Backup vault.');
    }
    if (json['version'] != version) {
      throw VaultException(
          'This vault was made by a newer version of the app (format ${json['version']}).');
    }
    return VaultHeader(
      vaultId: json['vaultId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      kdf: KdfParams.fromJson(json['kdf'] as Map<String, dynamic>),
      passwordSlot: base64Decode(json['passwordSlot'] as String),
      recoverySalt: base64Decode(json['recoverySalt'] as String),
      recoverySlot: base64Decode(json['recoverySlot'] as String),
    );
  }

  static const fileName = 'vault.json';
  static const backupFileName = 'vault.json.bak';
  static const format = 'phone-backup-vault';
  static const version = 1;

  final String vaultId;
  final DateTime createdAt;
  final KdfParams kdf;
  final Uint8List passwordSlot;
  final Uint8List recoverySalt;
  final Uint8List recoverySlot;

  VaultHeader copyWith({KdfParams? kdf, Uint8List? passwordSlot}) => VaultHeader(
        vaultId: vaultId,
        createdAt: createdAt,
        kdf: kdf ?? this.kdf,
        passwordSlot: passwordSlot ?? this.passwordSlot,
        recoverySalt: recoverySalt,
        recoverySlot: recoverySlot,
      );

  Map<String, Object?> toJson() => {
        'format': format,
        'version': version,
        'vaultId': vaultId,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'kdf': kdf.toJson(),
        'passwordSlot': base64Encode(passwordSlot),
        'recoverySalt': base64Encode(recoverySalt),
        'recoverySlot': base64Encode(recoverySlot),
      };

  static Future<bool> existsIn(String directory) async =>
      await File(p.join(directory, fileName)).exists() ||
      await File(p.join(directory, backupFileName)).exists();

  /// Reads `vault.json`, falling back to the backup copy if it is missing or
  /// damaged. Without either, the vault cannot be opened at all.
  static Future<VaultHeader> read(String directory) async {
    var damaged = false;
    for (final name in [fileName, backupFileName]) {
      final file = File(p.join(directory, name));
      if (!await file.exists()) continue;
      try {
        return VaultHeader.fromJson(
            jsonDecode(await file.readAsString()) as Map<String, dynamic>);
      } on FormatException {
        damaged = true;
      } on TypeError {
        damaged = true;
      }
    }
    if (damaged) {
      throw const VaultCorruptException('The vault header (vault.json) is damaged.');
    }
    throw const VaultException('This folder does not contain a Phone Backup vault.');
  }

  /// Replaces `vault.json` through a temporary file, then refreshes the
  /// backup copy, so a crash leaves at least one good header.
  Future<void> write(String directory) async {
    final json = const JsonEncoder.withIndent('  ').convert(toJson());
    final target = File(p.join(directory, fileName));
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(json, flush: true);
    try {
      await temp.rename(target.path);
    } on FileSystemException {
      if (await target.exists()) await target.delete();
      await temp.rename(target.path);
    }
    await File(p.join(directory, backupFileName)).writeAsString(json, flush: true);
  }
}

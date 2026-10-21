import 'errors.dart';

enum EventType {
  vaultCreated,
  sourceAdded,
  fileAdded,
  fileModified,
  fileMoved,
  fileDeleted,
  snapshot,
  passwordChanged;

  static EventType parse(String name) => EventType.values.firstWhere(
        (type) => type.name == name,
        orElse: () => throw VaultCorruptException('Unknown event type "$name".'),
      );
}

/// One entry in the change log. The log is the source of truth: the list of
/// files, deleted files, sources and stored blobs is rebuilt by replaying it.
class VaultEvent {
  const VaultEvent({
    required this.type,
    required this.time,
    this.seq = 0,
    this.source,
    this.path,
    this.fromPath,
    this.sha256,
    this.blobId,
    this.size,
    this.modified,
    this.info,
  });

  factory VaultEvent.fromJson(Map<String, dynamic> json) => VaultEvent(
        seq: json['seq'] as int,
        type: EventType.parse(json['type'] as String),
        time: DateTime.parse(json['time'] as String),
        source: json['source'] as String?,
        path: json['path'] as String?,
        fromPath: json['from'] as String?,
        sha256: json['sha256'] as String?,
        blobId: json['blob'] as String?,
        size: json['size'] as int?,
        modified: json['modified'] == null
            ? null
            : DateTime.parse(json['modified'] as String),
        info: json['info'] as Map<String, dynamic>?,
      );

  /// Position in the log, starting at 1. Zero until the log assigns it.
  final int seq;
  final EventType type;
  final DateTime time;

  /// Id of the folder or device the file belongs to.
  final String? source;

  /// Path inside the source, always with forward slashes.
  final String? path;

  /// Old path of a moved file.
  final String? fromPath;
  final String? sha256;
  final String? blobId;
  final int? size;

  /// Modification time the source reported for the file.
  final DateTime? modified;

  /// Extra details: a source's name and kind, a snapshot's counts.
  final Map<String, dynamic>? info;

  VaultEvent withSeq(int seq) => VaultEvent(
        type: type,
        time: time,
        seq: seq,
        source: source,
        path: path,
        fromPath: fromPath,
        sha256: sha256,
        blobId: blobId,
        size: size,
        modified: modified,
        info: info,
      );

  Map<String, Object?> toJson() => {
        'seq': seq,
        'type': type.name,
        'time': time.toUtc().toIso8601String(),
        if (source != null) 'source': source,
        if (path != null) 'path': path,
        if (fromPath != null) 'from': fromPath,
        if (sha256 != null) 'sha256': sha256,
        if (blobId != null) 'blob': blobId,
        if (size != null) 'size': size,
        if (modified != null) 'modified': modified!.toUtc().toIso8601String(),
        if (info != null) 'info': info,
      };
}

import 'dart:collection';

import 'events.dart';

/// A file as it currently exists in a source.
class FileEntry {
  const FileEntry({
    required this.source,
    required this.path,
    required this.sha256,
    required this.blobId,
    required this.size,
    required this.modified,
    required this.firstSeen,
    required this.lastChanged,
  });

  final String source;
  final String path;
  final String sha256;
  final String blobId;
  final int size;
  final DateTime modified;
  final DateTime firstSeen;
  final DateTime lastChanged;

  String get name => path.substring(path.lastIndexOf('/') + 1);

  String get folder {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? '' : path.substring(0, slash);
  }

  FileEntry copyWith({String? path, DateTime? lastChanged}) => FileEntry(
        source: source,
        path: path ?? this.path,
        sha256: sha256,
        blobId: blobId,
        size: size,
        modified: modified,
        firstSeen: firstSeen,
        lastChanged: lastChanged ?? this.lastChanged,
      );
}

/// A file that disappeared from its source. Its content stays in the vault.
class DeletedFile {
  const DeletedFile(this.file, this.deletedAt);

  final FileEntry file;
  final DateTime deletedAt;
}

/// A folder on this PC now; a phone from milestone 2 on.
class SourceInfo {
  SourceInfo({
    required this.id,
    required this.name,
    required this.kind,
    required this.addedAt,
    this.location,
  });

  final String id;
  final String name;
  final String kind;
  final String? location;
  final DateTime addedAt;
  DateTime? lastBackupAt;
  int backups = 0;
}

/// One unique content, stored once however many paths point to it.
class StoredBlob {
  StoredBlob({required this.blobId, required this.sha256, required this.size});

  final String blobId;
  final String sha256;
  final int size;

  /// Paths that currently point here (deleted files not counted).
  int liveReferences = 0;
}

class VaultStats {
  const VaultStats({
    required this.sources,
    required this.liveFiles,
    required this.liveBytes,
    required this.deletedFiles,
    required this.deletedBytes,
    required this.storedBlobs,
    required this.storedBytes,
    required this.duplicatesAvoided,
    required this.duplicateBytes,
    required this.events,
  });

  final int sources;
  final int liveFiles;
  final int liveBytes;
  final int deletedFiles;
  final int deletedBytes;

  /// Unique contents kept, and their size before encryption.
  final int storedBlobs;
  final int storedBytes;

  /// Files that were not stored again because their content was already in.
  final int duplicatesAvoided;
  final int duplicateBytes;
  final int events;
}

class FolderListing {
  const FolderListing(this.folders, this.files);

  final List<String> folders;
  final List<FileEntry> files;
}

/// Everything the vault knows, rebuilt in memory by replaying the change log.
class VaultIndex {
  final Map<String, SourceInfo> sources = {};
  final Map<String, Map<String, FileEntry>> _files = {};
  final List<DeletedFile> deleted = [];

  /// Stored contents by SHA-256.
  final Map<String, StoredBlob> blobs = {};
  final List<VaultEvent> events = [];
  int duplicatesAvoided = 0;
  int duplicateBytes = 0;

  /// The vault as it was right after event [upToSeq], or now if omitted.
  static VaultIndex fromEvents(Iterable<VaultEvent> events, {int? upToSeq}) {
    final index = VaultIndex();
    for (final event in events) {
      if (upToSeq != null && event.seq > upToSeq) break;
      index.apply(event);
    }
    return index;
  }

  Map<String, FileEntry> filesOf(String source) =>
      UnmodifiableMapView(_files[source] ?? const {});

  /// Direct subfolders and files of [folder] ('' is the source's top).
  FolderListing listFolder(String source, String folder) {
    final prefix = folder.isEmpty ? '' : '$folder/';
    final folders = <String>{};
    final files = <FileEntry>[];
    for (final entry in filesOf(source).values) {
      if (!entry.path.startsWith(prefix)) continue;
      final rest = entry.path.substring(prefix.length);
      final slash = rest.indexOf('/');
      if (slash < 0) {
        files.add(entry);
      } else {
        folders.add(rest.substring(0, slash));
      }
    }
    final sortedFolders = folders.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return FolderListing(sortedFolders, files);
  }

  /// Every logged change of the file at [path], oldest first, following
  /// renames back to when the file was first added.
  List<VaultEvent> historyOf(String source, String path) {
    final paths = {path};
    final history = <VaultEvent>[];
    for (final event in events.reversed) {
      if (event.source != source || !paths.contains(event.path)) continue;
      history.add(event);
      if (event.type == EventType.fileMoved) {
        paths.add(event.fromPath!);
      } else if (event.type == EventType.fileAdded) {
        // Anything older at this path belonged to a different file.
        paths.remove(event.path);
      }
    }
    return history.reversed.toList();
  }

  VaultStats get stats {
    var liveFiles = 0;
    var liveBytes = 0;
    for (final files in _files.values) {
      liveFiles += files.length;
      for (final file in files.values) {
        liveBytes += file.size;
      }
    }
    var storedBytes = 0;
    for (final blob in blobs.values) {
      storedBytes += blob.size;
    }
    var deletedBytes = 0;
    for (final d in deleted) {
      deletedBytes += d.file.size;
    }
    return VaultStats(
      sources: sources.length,
      liveFiles: liveFiles,
      liveBytes: liveBytes,
      deletedFiles: deleted.length,
      deletedBytes: deletedBytes,
      storedBlobs: blobs.length,
      storedBytes: storedBytes,
      duplicatesAvoided: duplicatesAvoided,
      duplicateBytes: duplicateBytes,
      events: events.length,
    );
  }

  void clear() {
    sources.clear();
    _files.clear();
    deleted.clear();
    blobs.clear();
    events.clear();
    duplicatesAvoided = 0;
    duplicateBytes = 0;
  }

  void apply(VaultEvent event) {
    events.add(event);
    switch (event.type) {
      case EventType.vaultCreated:
      case EventType.passwordChanged:
        break;
      case EventType.sourceAdded:
        _sourceAdded(event);
      case EventType.fileAdded:
      case EventType.fileModified:
        _fileStored(event);
      case EventType.fileMoved:
        _fileMoved(event);
      case EventType.fileDeleted:
        _fileDeleted(event);
      case EventType.snapshot:
        final source = sources[event.source];
        if (source != null) {
          source.lastBackupAt = event.time;
          source.backups++;
        }
    }
  }

  void _sourceAdded(VaultEvent event) {
    final info = event.info ?? const {};
    sources[event.source!] = SourceInfo(
      id: event.source!,
      name: info['name'] as String? ?? event.source!,
      kind: info['kind'] as String? ?? 'folder',
      location: info['location'] as String?,
      addedAt: event.time,
    );
  }

  void _fileStored(VaultEvent event) {
    final files = _files.putIfAbsent(event.source!, () => {});
    final previous = files[event.path!];
    if (previous != null) _release(previous);
    final entry = FileEntry(
      source: event.source!,
      path: event.path!,
      sha256: event.sha256!,
      blobId: event.blobId!,
      size: event.size!,
      modified: event.modified ?? event.time,
      firstSeen: previous?.firstSeen ?? event.time,
      lastChanged: event.time,
    );
    files[entry.path] = entry;
    // A file that comes back at the same path is no longer deleted.
    deleted.removeWhere((d) => d.file.source == entry.source && d.file.path == entry.path);

    final blob = blobs[entry.sha256];
    if (blob == null) {
      blobs[entry.sha256] =
          StoredBlob(blobId: entry.blobId, sha256: entry.sha256, size: entry.size)
            ..liveReferences = 1;
    } else {
      blob.liveReferences++;
      duplicatesAvoided++;
      duplicateBytes += entry.size;
    }
  }

  void _fileMoved(VaultEvent event) {
    final files = _files[event.source];
    final previous = files?.remove(event.fromPath);
    if (files == null || previous == null) return;
    files[event.path!] = previous.copyWith(path: event.path, lastChanged: event.time);
  }

  void _fileDeleted(VaultEvent event) {
    final previous = _files[event.source]?.remove(event.path);
    if (previous == null) return;
    _release(previous);
    deleted.add(DeletedFile(previous, event.time));
  }

  void _release(FileEntry entry) {
    final blob = blobs[entry.sha256];
    if (blob != null && blob.liveReferences > 0) blob.liveReferences--;
  }
}

import 'events.dart';
import 'index.dart';

/// One file as a source reports it: a folder on this PC now, a phone's
/// file list from milestone 2 on.
class ManifestEntry {
  const ManifestEntry({
    required this.path,
    required this.size,
    required this.modified,
    required this.sha256,
  });

  final String path;
  final int size;
  final DateTime modified;
  final String sha256;
}

class ChangeSet {
  ChangeSet(this.events);

  final List<VaultEvent> events;
  int added = 0;
  int modified = 0;
  int moved = 0;
  int deleted = 0;
  int unchanged = 0;
}

/// Compares what a source holds now with what the vault last recorded for
/// it and returns the events that turn one into the other.
///
/// Content that appears at a new path while the same content disappeared
/// from an old path is a move, so renaming or reorganising photos is logged
/// as such and never stores or counts them as new.
ChangeSet diffManifest({
  required String source,
  required Map<String, FileEntry> current,
  required List<ManifestEntry> manifest,
  required Map<String, String> blobIds,
  required DateTime now,
}) {
  final changes = ChangeSet([]);
  final seen = <String>{};
  final appeared = <ManifestEntry>[];
  final sorted = [...manifest]..sort((a, b) => a.path.compareTo(b.path));
  for (final entry in sorted) {
    seen.add(entry.path);
    final previous = current[entry.path];
    if (previous == null) {
      appeared.add(entry);
    } else if (previous.sha256 == entry.sha256) {
      changes.unchanged++;
    } else {
      changes.events.add(_stored(EventType.fileModified, source, entry, blobIds, now));
      changes.modified++;
    }
  }

  final vanished = current.keys.where((path) => !seen.contains(path)).toList()..sort();
  final vanishedBySha = <String, List<String>>{};
  for (final path in vanished) {
    vanishedBySha.putIfAbsent(current[path]!.sha256, () => []).add(path);
  }

  final movedAway = <String>{};
  for (final entry in appeared) {
    final candidates = vanishedBySha[entry.sha256];
    if (candidates != null && candidates.isNotEmpty) {
      final from = candidates.removeAt(0);
      movedAway.add(from);
      changes.events.add(VaultEvent(
        type: EventType.fileMoved,
        time: now,
        source: source,
        path: entry.path,
        fromPath: from,
        sha256: entry.sha256,
        size: entry.size,
      ));
      changes.moved++;
    } else {
      changes.events.add(_stored(EventType.fileAdded, source, entry, blobIds, now));
      changes.added++;
    }
  }

  for (final path in vanished) {
    if (movedAway.contains(path)) continue;
    final previous = current[path]!;
    changes.events.add(VaultEvent(
      type: EventType.fileDeleted,
      time: now,
      source: source,
      path: path,
      sha256: previous.sha256,
      size: previous.size,
    ));
    changes.deleted++;
  }
  return changes;
}

VaultEvent _stored(EventType type, String source, ManifestEntry entry,
    Map<String, String> blobIds, DateTime now) {
  final blobId = blobIds[entry.sha256];
  if (blobId == null) throw StateError('No stored content for ${entry.path}.');
  return VaultEvent(
    type: type,
    time: now,
    source: source,
    path: entry.path,
    sha256: entry.sha256,
    blobId: blobId,
    size: entry.size,
    modified: entry.modified,
  );
}

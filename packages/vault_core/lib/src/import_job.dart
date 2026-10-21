import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'blob_store.dart';
import 'cipher.dart';
import 'errors.dart';
import 'manifest.dart';

enum ImportPhase { scanning, hashing, encrypting, saving }

class ImportProgress {
  const ImportProgress(this.phase, this.done, this.total,
      {this.bytesDone = 0, this.bytesTotal = 0, this.current});

  final ImportPhase phase;
  final int done;
  final int total;
  final int bytesDone;
  final int bytesTotal;
  final String? current;
}

/// What the vault last recorded for a path, used to skip re-hashing files
/// whose size and modification time have not changed.
class KnownFile {
  const KnownFile(this.size, this.modifiedMs, this.sha256);

  final int size;
  final int modifiedMs;
  final String sha256;
}

class ImportRequest {
  const ImportRequest({
    required this.folder,
    required this.excludeDir,
    required this.storeRoot,
    required this.blobKey,
    required this.idKey,
    required this.known,
    required this.knownBlobIds,
    this.progress,
  });

  final String folder;

  /// The vault folder, never backed up into itself.
  final String excludeDir;
  final String storeRoot;
  final Uint8List blobKey;
  final Uint8List idKey;
  final Map<String, KnownFile> known;

  /// Blob ids of every content already in the vault, by SHA-256.
  final Map<String, String> knownBlobIds;
  final SendPort? progress;
}

class ImportScan {
  const ImportScan({
    required this.manifest,
    required this.blobIds,
    required this.skipped,
    required this.newBlobs,
    required this.newBytes,
    required this.storedBytes,
  });

  final List<ManifestEntry> manifest;
  final Map<String, String> blobIds;
  final List<String> skipped;
  final int newBlobs;
  final int newBytes;
  final int storedBytes;
}

Future<ImportScan> scanAndStoreInBackground(ImportRequest request) =>
    Isolate.run(() => scanAndStore(request));

/// Lists [ImportRequest.folder], hashes what is new or changed, and encrypts
/// each content the vault does not hold yet. Writes no log entries: the
/// caller turns the returned manifest into events and commits them.
Future<ImportScan> scanAndStore(ImportRequest request) async {
  final reporter = _Reporter(request.progress);
  final skipped = <String>[];
  final manifest = <ManifestEntry>[];

  // Files that cannot be read this time keep their last known state, so a
  // locked or unreadable file is never logged as deleted.
  void keepKnown(String relative) {
    final known = request.known[relative];
    if (known == null) return;
    manifest.add(ManifestEntry(
      path: relative,
      size: known.size,
      modified: DateTime.fromMillisecondsSinceEpoch(known.modifiedMs, isUtc: true),
      sha256: known.sha256,
    ));
  }

  // 1. Find the files.
  reporter.send(const ImportProgress(ImportPhase.scanning, 0, 0), force: true);
  final files = <File>[];
  final listed = Completer<void>();
  Directory(request.folder).list(recursive: true, followLinks: false).listen(
    (entity) {
      if (entity is File && !p.isWithin(request.excludeDir, entity.path)) {
        files.add(entity);
        reporter.send(ImportProgress(ImportPhase.scanning, files.length, 0));
      }
    },
    onError: (Object error) => skipped.add(_describe(error)),
    onDone: listed.complete,
    cancelOnError: false,
  );
  await listed.future;

  // 2. Hash what is new or changed since the last run.
  final candidates = <_Candidate>[];
  for (final file in files) {
    final relative =
        p.relative(file.path, from: request.folder).replaceAll(r'\', '/');
    try {
      final stat = await file.stat();
      final known = request.known[relative];
      final unchanged = known != null &&
          known.size == stat.size &&
          known.modifiedMs == stat.modified.millisecondsSinceEpoch;
      candidates.add(_Candidate(file.path, relative, stat.size, stat.modified,
          unchanged ? known.sha256 : null));
    } on FileSystemException catch (e) {
      skipped.add('$relative: ${e.message}');
      keepKnown(relative);
    }
  }
  final toHash = candidates.where((c) => c.sha256 == null).toList();
  final hashBytesTotal = toHash.fold<int>(0, (sum, c) => sum + c.size);
  var hashed = 0;
  var hashedBytes = 0;
  final absolutePaths = <String, String>{};
  for (final candidate in candidates) {
    var sha = candidate.sha256;
    if (sha == null) {
      try {
        sha = await sha256OfFile(candidate.absolute);
      } on FileSystemException catch (e) {
        skipped.add('${candidate.relative}: ${e.message}');
        keepKnown(candidate.relative);
        continue;
      }
      hashed++;
      hashedBytes += candidate.size;
      reporter.send(ImportProgress(ImportPhase.hashing, hashed, toHash.length,
          bytesDone: hashedBytes,
          bytesTotal: hashBytesTotal,
          current: candidate.relative));
    }
    absolutePaths[candidate.relative] = candidate.absolute;
    manifest.add(ManifestEntry(
      path: candidate.relative,
      size: candidate.size,
      modified: candidate.modified,
      sha256: sha,
    ));
  }

  // 3. Encrypt each content the vault does not have yet, once.
  final blobIds = <String, String>{};
  final pending = <String, ManifestEntry>{};
  for (final entry in manifest) {
    final known = request.knownBlobIds[entry.sha256];
    if (known != null) {
      blobIds[entry.sha256] = known;
    } else {
      pending.putIfAbsent(entry.sha256, () => entry);
    }
  }
  final pendingBytes = pending.values.fold<int>(0, (sum, e) => sum + e.size);
  final failed = <String>{};
  var done = 0;
  var doneBytes = 0;
  var newBlobs = 0;
  var newBytes = 0;
  var storedBytes = 0;
  for (final entry in pending.values) {
    reporter.send(ImportProgress(ImportPhase.encrypting, done, pending.length,
        bytesDone: doneBytes, bytesTotal: pendingBytes, current: entry.path));
    final blobId = await blobIdFor(request.idKey, entry.sha256);
    try {
      final result = await writeBlob(
        storeRoot: request.storeRoot,
        blobKey: request.blobKey,
        blobId: blobId,
        sourcePath: absolutePaths[entry.path]!,
        expectedSha256: entry.sha256,
      );
      blobIds[entry.sha256] = blobId;
      storedBytes += result.storedBytes;
      if (result.created) {
        newBlobs++;
        newBytes += entry.size;
      }
    } on ContentChangedException {
      failed.add(entry.sha256);
      skipped.add('${entry.path}: changed while it was being backed up');
    } on FileSystemException catch (e) {
      failed.add(entry.sha256);
      skipped.add('${entry.path}: ${e.message}');
    }
    done++;
    doneBytes += entry.size;
  }
  reporter.send(
      ImportProgress(ImportPhase.encrypting, done, pending.length,
          bytesDone: doneBytes, bytesTotal: pendingBytes),
      force: true);

  final committed = <ManifestEntry>[];
  for (final entry in manifest) {
    if (!failed.contains(entry.sha256)) {
      committed.add(entry);
      continue;
    }
    // Keep the last good version of a file that could not be stored now.
    final known = request.known[entry.path];
    final knownBlob = known == null ? null : request.knownBlobIds[known.sha256];
    if (known != null && knownBlob != null) {
      committed.add(ManifestEntry(
        path: entry.path,
        size: known.size,
        modified: DateTime.fromMillisecondsSinceEpoch(known.modifiedMs, isUtc: true),
        sha256: known.sha256,
      ));
      blobIds[known.sha256] = knownBlob;
    }
  }

  return ImportScan(
    manifest: committed,
    blobIds: blobIds,
    skipped: skipped,
    newBlobs: newBlobs,
    newBytes: newBytes,
    storedBytes: storedBytes,
  );
}

class _Candidate {
  const _Candidate(this.absolute, this.relative, this.size, this.modified, this.sha256);

  final String absolute;
  final String relative;
  final int size;
  final DateTime modified;

  /// Known hash when size and modification time are unchanged.
  final String? sha256;
}

/// Sends progress at most ten times a second.
class _Reporter {
  _Reporter(this.port);

  final SendPort? port;
  final Stopwatch _clock = Stopwatch()..start();
  int _lastMs = -1000;

  void send(ImportProgress progress, {bool force = false}) {
    final port = this.port;
    if (port == null) return;
    final now = _clock.elapsedMilliseconds;
    if (!force && now - _lastMs < 100) return;
    _lastMs = now;
    port.send(progress);
  }
}

String _describe(Object error) =>
    error is FileSystemException ? '${error.path}: ${error.message}' : '$error';

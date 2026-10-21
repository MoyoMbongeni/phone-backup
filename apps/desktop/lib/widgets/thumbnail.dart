import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vault_core/vault_core.dart';

import '../format.dart';

/// Decrypted image bytes for thumbnails, kept in memory only and dropped
/// with the explorer when the vault locks. Never written to disk.
class ThumbnailCache {
  ThumbnailCache(this.vault);

  final Vault vault;

  static const int _budgetBytes = 150 << 20;
  static const int _parallel = 4;

  /// Larger images get an icon instead of a thumbnail.
  static const int maxImageBytes = 40 << 20;

  final _cache = <String, Uint8List>{}; // insertion order = least recent first
  final _pending = <String, Future<Uint8List>>{};
  final _wanted = <String, int>{};
  final _waiting = Queue<Completer<void>>();
  int _bytes = 0;
  int _running = 0;

  Uint8List? peek(String blobId) => _cache[blobId];

  /// Marks [blobId] as on screen; loads for tiles that scrolled away are skipped.
  void want(String blobId) => _wanted[blobId] = (_wanted[blobId] ?? 0) + 1;

  void release(String blobId) {
    final count = (_wanted[blobId] ?? 1) - 1;
    if (count <= 0) {
      _wanted.remove(blobId);
    } else {
      _wanted[blobId] = count;
    }
  }

  Future<Uint8List> load(FileEntry file) {
    final hit = _cache.remove(file.blobId);
    if (hit != null) {
      _cache[file.blobId] = hit;
      return Future.value(hit);
    }
    // A block body on purpose: returning the removed future from the callback
    // would make this future wait for itself and never complete.
    return _pending[file.blobId] ??= _fetch(file).whenComplete(() {
      _pending.remove(file.blobId);
    });
  }

  Future<Uint8List> _fetch(FileEntry file) async {
    if (_running >= _parallel) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    _running++;
    try {
      if (!_wanted.containsKey(file.blobId)) throw const _NoLongerNeeded();
      final bytes = await vault.readFile(file);
      _cache[file.blobId] = bytes;
      _bytes += bytes.length;
      while (_bytes > _budgetBytes && _cache.length > 1) {
        _bytes -= _cache.remove(_cache.keys.first)!.length;
      }
      return bytes;
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeFirst().complete();
    }
  }
}

class _NoLongerNeeded implements Exception {
  const _NoLongerNeeded();
}

/// A square preview of [file]: the picture for images, an icon otherwise.
class FileThumbnail extends StatefulWidget {
  const FileThumbnail({super.key, required this.file, required this.cache, this.iconSize = 56});

  final FileEntry file;
  final ThumbnailCache cache;
  final double iconSize;

  @override
  State<FileThumbnail> createState() => _FileThumbnailState();
}

class _FileThumbnailState extends State<FileThumbnail> {
  Future<Uint8List>? _bytes;
  String? _wantedBlob;

  bool get _isPicture =>
      kindOf(widget.file.name) == FileKind.image &&
      widget.file.size <= ThumbnailCache.maxImageBytes;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(FileThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.blobId != widget.file.blobId) {
      _stop();
      _start();
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _start() {
    if (!_isPicture) {
      _bytes = null;
      return;
    }
    _wantedBlob = widget.file.blobId;
    widget.cache.want(_wantedBlob!);
    _bytes = widget.cache.load(widget.file);
  }

  void _stop() {
    final blob = _wantedBlob;
    if (blob != null) widget.cache.release(blob);
    _wantedBlob = null;
  }

  Widget _icon(IconData icon) => Center(
      child: Icon(icon,
          size: widget.iconSize, color: Theme.of(context).colorScheme.onSurfaceVariant));

  Widget _image(Uint8List bytes) => Image.memory(
        bytes,
        fit: BoxFit.cover,
        cacheWidth: 320,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _icon(Icons.broken_image_outlined),
      );

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return _icon(iconFor(kindOf(widget.file.name)));
    final cached = widget.cache.peek(widget.file.blobId);
    if (cached != null) return _image(cached);
    return FutureBuilder<Uint8List>(
      future: bytes,
      builder: (context, snapshot) {
        if (snapshot.hasData) return _image(snapshot.data!);
        if (snapshot.hasError) return _icon(Icons.broken_image_outlined);
        return const Center(
            child: SizedBox.square(
                dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)));
      },
    );
  }
}

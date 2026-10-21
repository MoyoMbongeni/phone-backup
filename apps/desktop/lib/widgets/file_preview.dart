import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vault_core/vault_core.dart';

import '../file_dialogs.dart';
import '../format.dart';

/// Opens [file] inside the app: decrypted in memory, never written to disk
/// unless the user exports a copy.
Future<void> showFilePreview(BuildContext context, Vault vault, FileEntry file,
    {DateTime? deletedAt}) {
  return showDialog<void>(
    context: context,
    builder: (_) => FilePreviewDialog(vault: vault, file: file, deletedAt: deletedAt),
  );
}

class FilePreviewDialog extends StatefulWidget {
  const FilePreviewDialog(
      {super.key, required this.vault, required this.file, this.deletedAt});

  final Vault vault;
  final FileEntry file;
  final DateTime? deletedAt;

  @override
  State<FilePreviewDialog> createState() => _FilePreviewDialogState();
}

class _FilePreviewDialogState extends State<FilePreviewDialog> {
  static const _maxTextBytes = 2 << 20;

  late final FileKind _kind = kindOf(widget.file.name);
  late final Future<Uint8List>? _content = _kind == FileKind.image ||
          (_kind == FileKind.text && widget.file.size <= _maxTextBytes)
      ? widget.vault.readFile(widget.file)
      : null;
  bool _showHistory = false;

  void _snack(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _export() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export an unencrypted copy?'),
        content: const Text(
            'The copy is a normal file. Anyone who can open the folder you save it '
            'in can see it. The vault keeps its encrypted copy either way.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Choose where…')),
        ],
      ),
    );
    if (confirmed != true) return;
    final path = await fileDialogs.pickSaveLocation(suggestedName: widget.file.name);
    if (path == null) return;
    try {
      await widget.vault.exportFile(widget.file, path);
      _snack('Saved to $path');
    } catch (e) {
      _snack(e is VaultException ? e.message : 'Export failed: $e');
    }
  }

  Widget _preview(ThemeData theme) {
    final content = _content;
    if (content == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(iconFor(_kind), size: 96, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            const Text('There is no preview for this kind of file yet.'),
            const Text('Export a copy to open it in another app.'),
          ],
        ),
      );
    }
    return FutureBuilder<Uint8List>(
      future: content,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final error = snapshot.error;
          return Center(
              child: Text(error is VaultException ? error.message : 'Could not open: $error',
                  style: TextStyle(color: theme.colorScheme.error)));
        }
        final bytes = snapshot.data;
        if (bytes == null) return const Center(child: CircularProgressIndicator());
        if (_kind == FileKind.image) {
          return InteractiveViewer(
            maxScale: 8,
            child: Center(
              child: Image.memory(bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Text('This image could not be decoded.')),
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(utf8.decode(bytes, allowMalformed: true),
              style: const TextStyle(fontFamily: 'Consolas')),
        );
      },
    );
  }

  Widget _history(ThemeData theme) {
    final index = widget.vault.index;
    final events = index.historyOf(widget.file.source, widget.file.path);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final event in events.reversed)
          ListTile(
            leading: Icon(iconForEvent(event.type)),
            title: Text(describeEvent(event, index.sources)),
            subtitle: Text([
              formatDate(event.time),
              if (event.size != null) formatBytes(event.size!),
            ].join(' • ')),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = widget.file;
    return Dialog(
      insetPadding: const EdgeInsets.all(40),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 960,
        height: 720,
        child: Column(
          children: [
            ListTile(
              leading: Icon(iconFor(_kind)),
              title: Text(file.name),
              subtitle: Text(
                  '${formatBytes(file.size)} • modified ${formatDate(file.modified)} • ${file.path}'),
              trailing: IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            if (widget.deletedAt != null)
              Container(
                width: double.infinity,
                color: theme.colorScheme.errorContainer,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Deleted from its folder on ${formatDate(widget.deletedAt!)}. '
                  'The vault still keeps it.',
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            const Divider(height: 1),
            Expanded(child: _showHistory ? _history(theme) : _preview(theme)),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() => _showHistory = !_showHistory),
                    icon: Icon(_showHistory ? Icons.visibility_outlined : Icons.history),
                    label: Text(_showHistory ? 'Show the file' : 'History'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _export,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Export a copy…'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

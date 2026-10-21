import 'package:flutter/material.dart';
import 'package:vault_core/vault_core.dart';

import '../format.dart';

/// Runs a backup of [folder] and shows its progress, then a summary.
/// Pops with the [ImportResult], or null if the backup failed.
class ImportDialog extends StatefulWidget {
  const ImportDialog({super.key, required this.vault, required this.folder});

  final Vault vault;
  final String folder;

  @override
  State<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<ImportDialog> {
  ImportProgress? _progress;
  ImportResult? _result;
  Object? _error;

  bool get _finished => _result != null || _error != null;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final result = await widget.vault.importFolder(widget.folder, onProgress: (progress) {
        if (mounted) setState(() => _progress = progress);
      });
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Widget _progressView(ThemeData theme) {
    final progress = _progress;
    String label;
    double? fraction;
    switch (progress?.phase) {
      case null:
      case ImportPhase.scanning:
        label = 'Looking for files… ${progress?.done ?? 0} found';
      case ImportPhase.hashing:
        label = 'Checking new and changed files: ${progress!.done} of ${progress.total} '
            '(${formatBytes(progress.bytesDone)} of ${formatBytes(progress.bytesTotal)})';
        fraction = _fraction(progress);
      case ImportPhase.encrypting:
        label = 'Encrypting new content: ${progress!.done} of ${progress.total} '
            '(${formatBytes(progress.bytesDone)} of ${formatBytes(progress.bytesTotal)})';
        fraction = _fraction(progress);
      case ImportPhase.saving:
        label = 'Saving the change log…';
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.folder, style: theme.textTheme.bodySmall),
        const SizedBox(height: 20),
        Text(label),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: fraction),
        const SizedBox(height: 8),
        Text(progress?.current ?? '',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
      ],
    );
  }

  double? _fraction(ImportProgress progress) {
    if (progress.bytesTotal > 0) return progress.bytesDone / progress.bytesTotal;
    if (progress.total > 0) return progress.done / progress.total;
    return null;
  }

  Widget _summary(ThemeData theme, ImportResult result) {
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [Expanded(child: Text(label)), Text(value)]),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.folder, style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        row('Added', '${result.added}'),
        row('Changed', '${result.modified}'),
        row('Moved or renamed', '${result.moved}'),
        row('Deleted (still kept in the vault)', '${result.deleted}'),
        row('Unchanged', '${result.unchanged}'),
        const Divider(height: 24),
        row('New content encrypted', '${formatBytes(result.newBytes)} in ${result.newBlobs} files'),
        row('Duplicates not stored again',
            '${result.duplicatesAvoided} (${formatBytes(result.duplicateBytes)})'),
        row('Time', formatDuration(result.elapsed)),
        if (result.skipped.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('${result.skipped.length} files could not be read',
                style: TextStyle(color: theme.colorScheme.error)),
            children: [
              for (final line in result.skipped.take(100))
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text(line, style: theme.textTheme.bodySmall)),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    final error = _error;
    return PopScope(
      canPop: _finished,
      child: AlertDialog(
        title: Text(result != null
            ? 'Backup finished'
            : error != null
                ? 'Backup failed'
                : 'Backing up…'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: result != null
                ? _summary(theme, result)
                : error != null
                    ? Text(error is VaultException ? error.message : '$error')
                    : _progressView(theme),
          ),
        ),
        actions: [
          if (_finished)
            FilledButton(
              onPressed: () => Navigator.of(context).pop(result),
              child: const Text('Close'),
            ),
        ],
      ),
    );
  }
}

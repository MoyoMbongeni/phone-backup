import 'dart:io';

import 'package:flutter/material.dart';
import 'package:vault_core/vault_core.dart';

import '../format.dart';

class OverviewView extends StatelessWidget {
  const OverviewView({super.key, required this.vault});

  final Vault vault;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = vault.index.stats;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _StatCard('Files backed up', '${stats.liveFiles}', formatBytes(stats.liveBytes)),
            _StatCard('Unique content stored', formatBytes(stats.storedBytes),
                '${stats.storedBlobs} contents'),
            _StatCard('Duplicates not stored again', '${stats.duplicatesAvoided}',
                '${formatBytes(stats.duplicateBytes)} saved'),
            _StatCard('Deleted files kept', '${stats.deletedFiles}',
                formatBytes(stats.deletedBytes)),
            _StatCard('Logged changes', '${stats.events}',
                'since ${formatDate(vault.createdAt)}'),
          ],
        ),
        const SizedBox(height: 32),
        Text('Backed-up folders', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (vault.index.sources.isEmpty) const Text('None yet.'),
        for (final source in vault.index.sources.values)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_special_outlined),
            title: Text(source.name),
            subtitle: Text([
              source.location ?? '',
              '${source.backups} backups',
              if (source.lastBackupAt != null) 'last ${formatDate(source.lastBackupAt!)}',
            ].join(' • ')),
          ),
        const SizedBox(height: 32),
        Text('This vault', style: theme.textTheme.titleMedium),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.folder_outlined),
          title: Text(vault.directory),
          subtitle: const Text(
              'Everything in this folder is encrypted. Opening it in Windows Explorer '
              'shows only unreadable files.'),
          trailing: TextButton(
            onPressed: () => Process.start('explorer.exe', [vault.directory]),
            child: const Text('Show in Explorer'),
          ),
        ),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.enhanced_encryption_outlined),
          title: Text('AES-256-GCM, in 1 MiB chunks'),
          subtitle: Text(
              'The key is random and is itself locked by your password (Argon2id, '
              '64 MiB) and by your recovery key. File names exist only inside the '
              'encrypted change log.'),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.title, this.value, this.detail);

  final String title;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Text(value, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(detail, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

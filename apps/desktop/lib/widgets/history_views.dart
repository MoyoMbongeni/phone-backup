import 'package:flutter/material.dart';
import 'package:vault_core/vault_core.dart';

import '../format.dart';
import 'file_preview.dart';
import 'thumbnail.dart';

/// Files that disappeared from their folder. The vault keeps them.
class DeletedView extends StatelessWidget {
  const DeletedView({super.key, required this.vault, required this.thumbnails});

  final Vault vault;
  final ThumbnailCache thumbnails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deleted = vault.index.deleted.reversed.toList();
    if (deleted.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_sweep_outlined, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Nothing deleted yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('When a file disappears from a backed-up folder, it is listed '
                'here and the vault keeps its content.'),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: deleted.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 80),
      itemBuilder: (context, i) {
        final item = deleted[i];
        final source = vault.index.sources[item.file.source];
        return ListTile(
          leading: SizedBox.square(
            dimension: 48,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: ColoredBox(
                color: theme.colorScheme.surfaceContainerHighest,
                child: FileThumbnail(file: item.file, cache: thumbnails, iconSize: 28),
              ),
            ),
          ),
          title: Text(item.file.name),
          subtitle: Text('${source?.name ?? '?'}/${item.file.path} • '
              '${formatBytes(item.file.size)} • deleted ${formatDate(item.deletedAt)}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              showFilePreview(context, vault, item.file, deletedAt: item.deletedAt),
        );
      },
    );
  }
}

/// The change log, newest first.
class ActivityView extends StatelessWidget {
  const ActivityView({super.key, required this.vault});

  final Vault vault;

  @override
  Widget build(BuildContext context) {
    final events = vault.index.events;
    final sources = vault.index.sources;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: events.length,
      itemBuilder: (context, i) {
        final event = events[events.length - 1 - i];
        final source = sources[event.source];
        return ListTile(
          dense: true,
          leading: Icon(iconForEvent(event.type)),
          title: Text(describeEvent(event, sources)),
          subtitle: Text([
            formatDate(event.time),
            if (source != null) source.name,
            if (event.size != null && event.type != EventType.snapshot)
              formatBytes(event.size!),
          ].join(' • ')),
        );
      },
    );
  }
}

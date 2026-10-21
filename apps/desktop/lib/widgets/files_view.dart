import 'package:flutter/material.dart';
import 'package:vault_core/vault_core.dart';

import '../format.dart';
import 'file_preview.dart';
import 'thumbnail.dart';

/// Browses one source's files as folders, like a normal file explorer.
class FilesView extends StatelessWidget {
  const FilesView({
    super.key,
    required this.vault,
    required this.thumbnails,
    required this.sourceId,
    required this.folder,
    required this.onNavigate,
    required this.onBackUp,
    required this.onBackUpAgain,
  });

  final Vault vault;
  final ThumbnailCache thumbnails;
  final String? sourceId;
  final String folder;
  final void Function(String sourceId, String folder) onNavigate;
  final VoidCallback onBackUp;
  final void Function(SourceInfo source) onBackUpAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sources = vault.index.sources.values.toList();
    if (sources.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('The vault is empty', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('Back up a folder from this PC to try it out. '
                'Phones connect in the next version.'),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onBackUp,
              icon: const Icon(Icons.drive_folder_upload_outlined),
              label: const Text('Back up a folder…'),
            ),
          ],
        ),
      );
    }

    final source = vault.index.sources[sourceId] ?? sources.first;
    final listing = vault.index.listFolder(source.id, folder);
    final segments = folder.isEmpty ? <String>[] : folder.split('/');
    final items = listing.folders.length + listing.files.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              DropdownButton<String>(
                value: source.id,
                underline: const SizedBox.shrink(),
                items: [
                  for (final s in sources)
                    DropdownMenuItem(
                      value: s.id,
                      child: Row(children: [
                        const Icon(Icons.folder_special_outlined, size: 20),
                        const SizedBox(width: 8),
                        Text(s.name),
                      ]),
                    ),
                ],
                onChanged: (id) {
                  if (id != null) onNavigate(id, '');
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Back up this folder again',
                icon: const Icon(Icons.sync),
                onPressed: source.location == null ? null : () => onBackUpAgain(source),
              ),
              const Spacer(),
              Text('${listing.folders.length} folders, ${listing.files.length} files',
                  style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            [
              if (source.location != null) source.location!,
              if (source.lastBackupAt != null) 'last backed up ${formatDate(source.lastBackupAt!)}',
            ].join(' • '),
            style: theme.textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(onPressed: () => onNavigate(source.id, ''), child: Text(source.name)),
              for (var i = 0; i < segments.length; i++) ...[
                const Icon(Icons.chevron_right, size: 18),
                TextButton(
                  onPressed: () => onNavigate(source.id, segments.take(i + 1).join('/')),
                  child: Text(segments[i]),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: items == 0
              ? const Center(child: Text('This folder is empty.'))
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 170,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: items,
                  itemBuilder: (context, i) {
                    if (i < listing.folders.length) {
                      final name = listing.folders[i];
                      return _Tile(
                        label: name,
                        onTap: () => onNavigate(
                            source.id, folder.isEmpty ? name : '$folder/$name'),
                        child: Icon(Icons.folder, size: 72, color: theme.colorScheme.primary),
                      );
                    }
                    final file = listing.files[i - listing.folders.length];
                    return _Tile(
                      label: file.name,
                      tooltip: '${file.name}\n${formatBytes(file.size)} • ${formatDate(file.modified)}',
                      onTap: () => showFilePreview(context, vault, file),
                      child: FileThumbnail(file: file, cache: thumbnails),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.onTap, required this.child, this.tooltip});

  final String label;
  final VoidCallback onTap;
  final Widget child;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tile = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  width: double.infinity,
                  child: child,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
    return tooltip == null ? tile : Tooltip(message: tooltip!, waitDuration: const Duration(milliseconds: 600), child: tile);
  }
}

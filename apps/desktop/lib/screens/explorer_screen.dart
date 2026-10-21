import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:vault_core/vault_core.dart';

import '../app_state.dart';
import '../file_dialogs.dart';
import '../widgets/files_view.dart';
import '../widgets/history_views.dart';
import '../widgets/import_dialog.dart';
import '../widgets/overview_view.dart';
import '../widgets/password_dialogs.dart';
import '../widgets/thumbnail.dart';

/// The app's own file explorer: the only place the vault's files can be seen.
class ExplorerScreen extends StatefulWidget {
  const ExplorerScreen({super.key, required this.state, required this.vault});

  final AppState state;
  final Vault vault;

  @override
  State<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends State<ExplorerScreen> {
  late final ThumbnailCache _thumbnails = ThumbnailCache(widget.vault);
  int _section = 0;
  String? _sourceId;
  String _folder = '';

  Future<void> _backUp(String folder) async {
    final result = await showDialog<ImportResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ImportDialog(vault: widget.vault, folder: folder),
    );
    widget.state.vaultChanged();
    if (result != null && mounted) {
      setState(() {
        _section = 0;
        if (_sourceId != result.sourceId) {
          _sourceId = result.sourceId;
          _folder = '';
        }
      });
    }
  }

  Future<void> _chooseAndBackUp() async {
    final folder = await fileDialogs.pickDirectory(confirmButtonText: 'Back up this folder');
    if (folder != null) await _backUp(folder);
  }

  Future<void> _changePassword() async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => NewPasswordDialog(
          title: 'Change password', checkCurrent: widget.vault.checkPassword),
    );
    if (password == null) return;
    await widget.vault.changePassword(password);
    widget.state.vaultChanged();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Password changed. No file needed re-encrypting.')));
  }

  @override
  Widget build(BuildContext context) {
    final vault = widget.vault;
    return Scaffold(
      appBar: AppBar(
        title: Text(p.basename(vault.directory)),
        actions: [
          FilledButton.icon(
            onPressed: _chooseAndBackUp,
            icon: const Icon(Icons.drive_folder_upload_outlined),
            label: const Text('Back up a folder…'),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Change password',
            icon: const Icon(Icons.password),
            onPressed: _changePassword,
          ),
          IconButton(
            tooltip: 'Lock',
            icon: const Icon(Icons.lock_outline),
            onPressed: widget.state.lock,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _section,
            onDestinationSelected: (i) => setState(() => _section = i),
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                  icon: Icon(Icons.folder_outlined),
                  selectedIcon: Icon(Icons.folder),
                  label: Text('Files')),
              NavigationRailDestination(
                  icon: Icon(Icons.delete_outline),
                  selectedIcon: Icon(Icons.delete),
                  label: Text('Deleted')),
              NavigationRailDestination(icon: Icon(Icons.history), label: Text('Activity')),
              NavigationRailDestination(
                  icon: Icon(Icons.insights_outlined),
                  selectedIcon: Icon(Icons.insights),
                  label: Text('Overview')),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: switch (_section) {
              0 => FilesView(
                  vault: vault,
                  thumbnails: _thumbnails,
                  sourceId: _sourceId,
                  folder: _folder,
                  onNavigate: (sourceId, folder) => setState(() {
                    _sourceId = sourceId;
                    _folder = folder;
                  }),
                  onBackUp: _chooseAndBackUp,
                  onBackUpAgain: (source) => _backUp(source.location!),
                ),
              1 => DeletedView(vault: vault, thumbnails: _thumbnails),
              2 => ActivityView(vault: vault),
              _ => OverviewView(vault: vault),
            },
          ),
        ],
      ),
    );
  }
}

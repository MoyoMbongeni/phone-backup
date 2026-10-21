import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:vault_core/vault_core.dart';

import '../app_state.dart';
import '../file_dialogs.dart';
import 'create_vault_screen.dart';
import 'unlock_screen.dart';

class StartScreen extends StatefulWidget {
  const StartScreen({super.key, required this.state});

  final AppState state;

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  String? _error;

  Future<void> _open(String directory) async {
    if (!await Vault.existsIn(directory)) {
      setState(() => _error = 'There is no Phone Backup vault in $directory.');
      return;
    }
    if (!mounted) return;
    setState(() => _error = null);
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => UnlockScreen(state: widget.state, directory: directory)));
  }

  Future<void> _chooseVault() async {
    final directory = await fileDialogs.pickDirectory(confirmButtonText: 'Open vault');
    if (directory != null) await _open(directory);
  }

  void _create() {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => CreateVaultScreen(state: widget.state)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = widget.state.lastVaultPath;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.shield_outlined, size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text('Phone Backup',
                    style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'Your backups, encrypted on this PC. Only this app can open them, '
                  'and only with your password.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 40),
                if (last != null) ...[
                  FilledButton.icon(
                    onPressed: () => _open(last),
                    icon: const Icon(Icons.lock_open),
                    label: Text('Open ${p.basename(last)}'),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 20),
                    child: Text(last,
                        textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                  ),
                ],
                OutlinedButton.icon(
                  onPressed: _chooseVault,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('Open another vault…'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.add),
                  label: const Text('Create a new vault…'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 20),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

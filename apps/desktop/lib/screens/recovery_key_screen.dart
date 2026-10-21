import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vault_core/vault_core.dart';

import '../app_state.dart';
import '../file_dialogs.dart';

/// Shown once, right after a vault is created. The key cannot be shown again.
class RecoveryKeyScreen extends StatefulWidget {
  const RecoveryKeyScreen({super.key, required this.state, required this.created});

  final AppState state;
  final VaultCreated created;

  @override
  State<RecoveryKeyScreen> createState() => _RecoveryKeyScreenState();
}

class _RecoveryKeyScreenState extends State<RecoveryKeyScreen> {
  bool _stored = false;

  void _snack(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.created.recoveryKey));
    _snack('Copied. Paste it somewhere safe, then clear your clipboard.');
  }

  Future<void> _saveToFile() async {
    final path =
        await fileDialogs.pickSaveLocation(suggestedName: 'Phone Backup recovery key.txt');
    if (path == null) return;
    await File(path).writeAsString(
        'Phone Backup recovery key\r\n'
        'Vault: ${widget.created.vault.directory}\r\n\r\n'
        '${widget.created.recoveryKey}\r\n\r\n'
        'Anyone with this key and the vault folder can open your backups. '
        'Print it or keep it on a USB stick, not on this PC.\r\n');
    _snack('Saved to $path');
  }

  /// Two even lines of four groups, easier to copy by hand than one long line.
  String get _display {
    final groups = widget.created.recoveryKey.split('-');
    final half = groups.length ~/ 2;
    return '${groups.take(half).join('-')}\n${groups.skip(half).join('-')}';
  }

  void _continue() {
    widget.state.opened(widget.created.vault);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
            title: const Text('Your recovery key'), automaticallyImplyLeading: false),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.key, size: 48, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  const Text(
                    'If you forget your password, this key is the only way to open the '
                    'vault. Nobody can recover your backups without one of the two. '
                    'It is shown only now.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(
                      _display,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontFamily: 'Consolas', fontSize: 22, letterSpacing: 1.5),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                          onPressed: _copy,
                          icon: const Icon(Icons.copy),
                          label: const Text('Copy')),
                      const SizedBox(width: 12),
                      TextButton.icon(
                          onPressed: _saveToFile,
                          icon: const Icon(Icons.save_alt),
                          label: const Text('Save as text file…')),
                    ],
                  ),
                  const SizedBox(height: 24),
                  CheckboxListTile(
                    value: _stored,
                    onChanged: (value) => setState(() => _stored = value ?? false),
                    title: const Text(
                        'I have written this key down or stored it somewhere safe, '
                        'away from this PC.'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _stored ? _continue : null,
                    child: const Text('Open the vault'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

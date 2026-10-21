import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:vault_core/vault_core.dart';

import '../app_state.dart';
import '../file_dialogs.dart';
import '../widgets/password_dialogs.dart';
import 'recovery_key_screen.dart';

class CreateVaultScreen extends StatefulWidget {
  const CreateVaultScreen({super.key, required this.state});

  final AppState state;

  @override
  State<CreateVaultScreen> createState() => _CreateVaultScreenState();
}

class _CreateVaultScreenState extends State<CreateVaultScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _directory;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// A vault needs an empty folder; if the chosen one has files, the vault
  /// goes into a new subfolder of it.
  static Future<String> _vaultFolderIn(String chosen) async {
    final dir = Directory(chosen);
    if (!await dir.exists() || await dir.list().isEmpty) return chosen;
    var candidate = p.join(chosen, 'Phone Backup Vault');
    for (var n = 2; await Directory(candidate).exists(); n++) {
      candidate = p.join(chosen, 'Phone Backup Vault $n');
    }
    return candidate;
  }

  Future<void> _chooseFolder() async {
    final chosen = await fileDialogs.pickDirectory(confirmButtonText: 'Put the vault here');
    if (chosen == null) return;
    final directory = await _vaultFolderIn(chosen);
    setState(() {
      _directory = directory;
      _error = null;
    });
  }

  Future<void> _create() async {
    final directory = _directory;
    final problem = directory == null
        ? 'Choose where to keep the vault first.'
        : passwordProblem(_password.text, _confirm.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await Vault.create(directory!, _password.text);
      if (!mounted) {
        created.vault.lock();
        return;
      }
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => RecoveryKeyScreen(state: widget.state, created: created)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is VaultException ? e.message : 'Could not create the vault: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Create a vault')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('1. Where should the vault live?', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text(
                    'Pick a drive with room for your phone\'s photos and videos. An external '
                    'drive works too.'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _chooseFolder,
                      icon: const Icon(Icons.folder_outlined),
                      label: const Text('Choose folder…'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_directory ?? 'No folder chosen',
                          style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Text('2. Choose a password', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text('It unlocks the vault on this PC and never leaves it.'),
                const SizedBox(height: 16),
                PasswordField(
                  controller: _password,
                  label: 'Password',
                  enabled: !_busy,
                  helperText: passwordHint,
                ),
                const SizedBox(height: 16),
                PasswordField(
                  controller: _confirm,
                  label: 'Password again',
                  enabled: !_busy,
                  onSubmitted: (_) => _create(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _busy ? null : _create,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Create vault'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

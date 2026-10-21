import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:vault_core/vault_core.dart';

import '../app_state.dart';
import '../widgets/password_dialogs.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key, required this.state, required this.directory});

  final AppState state;
  final String directory;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _secret = TextEditingController();
  final _focus = FocusNode();
  bool _useRecoveryKey = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _secret.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// After a failed attempt the field is focused again with its text
  /// selected, so the user can simply type again.
  void _retry(String message) {
    setState(() {
      _busy = false;
      _error = message;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      _secret.selection = TextSelection(baseOffset: 0, extentOffset: _secret.text.length);
    });
  }

  Future<void> _unlock() async {
    if (_secret.text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final vault = _useRecoveryKey
          ? await Vault.unlockWithRecoveryKey(widget.directory, _secret.text)
          : await Vault.unlockWithPassword(widget.directory, _secret.text);
      if (!mounted) {
        vault.lock();
        return;
      }
      if (_useRecoveryKey) {
        final password = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const NewPasswordDialog(
            title: 'Choose a new password',
            intro: 'You opened the vault with the recovery key. Choose a new password '
                'for everyday use. The recovery key keeps working.',
            canCancel: false,
          ),
        );
        if (password != null) await vault.changePassword(password);
        if (!mounted) {
          vault.lock();
          return;
        }
      }
      widget.state.opened(vault);
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      _retry(e is VaultException ? e.message : 'Could not open the vault: $e');
    }
  }

  void _toggleMode() => setState(() {
        _useRecoveryKey = !_useRecoveryKey;
        _secret.clear();
        _error = null;
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Unlock vault')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.lock_outline, size: 48, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text(p.basename(widget.directory),
                    textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
                Text(widget.directory,
                    textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                const SizedBox(height: 32),
                if (_useRecoveryKey)
                  TextField(
                    controller: _secret,
                    focusNode: _focus,
                    autofocus: true,
                    enabled: !_busy,
                    onSubmitted: (_) => _unlock(),
                    style: const TextStyle(fontFamily: 'Consolas', letterSpacing: 1),
                    decoration: const InputDecoration(
                      labelText: 'Recovery key',
                      hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
                      border: OutlineInputBorder(),
                    ),
                  )
                else
                  PasswordField(
                    controller: _secret,
                    focusNode: _focus,
                    label: 'Password',
                    autofocus: true,
                    enabled: !_busy,
                    onSubmitted: (_) => _unlock(),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _unlock,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Unlock'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : _toggleMode,
                  child: Text(_useRecoveryKey
                      ? 'Use the password instead'
                      : 'Forgot the password? Use the recovery key'),
                ),
                if (_busy)
                  Text(
                    'Checking takes about a second on purpose, so password guessing is slow.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

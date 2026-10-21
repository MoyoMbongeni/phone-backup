import 'package:flutter/material.dart';

const int minPasswordLength = 10;

/// Null when [password] is acceptable and matches [confirmation].
String? passwordProblem(String password, String confirmation) {
  if (password.length < minPasswordLength) {
    return 'Use at least $minPasswordLength characters.';
  }
  if (password != confirmation) return 'The two passwords are not the same.';
  return null;
}

const passwordHint = 'At least $minPasswordLength characters. A few unrelated words '
    'are easy to remember and hard to guess.';

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.helperText,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final bool autofocus;
  final bool enabled;
  final String? helperText;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      obscureText: !_visible,
      enableSuggestions: false,
      autocorrect: false,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helperText,
        helperMaxLines: 3,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: _visible ? 'Hide' : 'Show',
          icon: Icon(_visible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          onPressed: () => setState(() => _visible = !_visible),
        ),
      ),
    );
  }
}

/// Asks for a new password (twice) and, when [checkCurrent] is given, the
/// current one first. Pops with the new password.
class NewPasswordDialog extends StatefulWidget {
  const NewPasswordDialog({
    super.key,
    required this.title,
    this.intro,
    this.checkCurrent,
    this.canCancel = true,
  });

  final String title;
  final String? intro;
  final Future<bool> Function(String password)? checkCurrent;
  final bool canCancel;

  @override
  State<NewPasswordDialog> createState() => _NewPasswordDialogState();
}

class _NewPasswordDialogState extends State<NewPasswordDialog> {
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final problem = passwordProblem(_password.text, _confirm.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final check = widget.checkCurrent;
    if (check != null) {
      setState(() {
        _busy = true;
        _error = null;
      });
      final ok = await check(_current.text);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _busy = false;
          _error = 'The current password is not right.';
        });
        return;
      }
    }
    Navigator.of(context).pop(_password.text);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.canCancel && !_busy,
      child: AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.intro != null) ...[
                Text(widget.intro!),
                const SizedBox(height: 16),
              ],
              if (widget.checkCurrent != null) ...[
                PasswordField(
                    controller: _current,
                    label: 'Current password',
                    autofocus: true,
                    enabled: !_busy),
                const SizedBox(height: 16),
              ],
              PasswordField(
                controller: _password,
                label: 'New password',
                autofocus: widget.checkCurrent == null,
                enabled: !_busy,
                helperText: passwordHint,
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _confirm,
                label: 'New password again',
                enabled: !_busy,
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
        actions: [
          if (widget.canCancel)
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox.square(
                    dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save password'),
          ),
        ],
      ),
    );
  }
}

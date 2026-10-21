import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app_state.dart';

/// Locks the vault after [AppState.autoLockAfter] without mouse or keyboard
/// input, but never in the middle of a backup.
class IdleLock extends StatefulWidget {
  const IdleLock({super.key, required this.state, required this.child});

  final AppState state;
  final Widget child;

  @override
  State<IdleLock> createState() => _IdleLockState();
}

class _IdleLockState extends State<IdleLock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    _restart();
    return false;
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer(widget.state.autoLockAfter, _expired);
  }

  void _expired() {
    final vault = widget.state.vault;
    if (vault != null && vault.isImporting) {
      _restart();
      return;
    }
    widget.state.lock();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _restart(),
      onPointerHover: (_) => _restart(),
      onPointerSignal: (_) => _restart(),
      child: widget.child,
    );
  }
}

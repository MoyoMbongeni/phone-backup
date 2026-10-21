import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:vault_core/vault_core.dart';

/// The open vault, if any, plus the one setting kept between runs: where
/// the last vault was. Nothing about its contents is stored outside it.
class AppState extends ChangeNotifier {
  /// [settingsPath] overrides where settings are kept (tests use a temp file).
  AppState({String? settingsPath}) : _settingsPath = settingsPath;

  final String? _settingsPath;
  final navigatorKey = GlobalKey<NavigatorState>();

  /// Lock after this long without mouse or keyboard input.
  final Duration autoLockAfter = const Duration(minutes: 10);

  Vault? _vault;
  String? _lastVaultPath;

  Vault? get vault => _vault;
  String? get lastVaultPath => _lastVaultPath;

  Future<void> load() async {
    try {
      final file = await _settingsFile();
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _lastVaultPath = json['lastVault'] as String?;
      }
    } catch (_) {
      // A missing or broken settings file only loses the shortcut.
    }
    notifyListeners();
  }

  void opened(Vault vault) {
    _vault = vault;
    _lastVaultPath = vault.directory;
    _save();
    notifyListeners();
  }

  /// Call after anything that changed the vault, so every view refreshes.
  void vaultChanged() => notifyListeners();

  /// Closes every dialog, forgets the keys and returns to the start screen.
  void lock() {
    final vault = _vault;
    if (vault == null) return;
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    _vault = null;
    vault.lock();
    notifyListeners();
  }

  Future<File> _settingsFile() async => File(_settingsPath ??
      p.join((await getApplicationSupportDirectory()).path, 'settings.json'));

  Future<void> _save() async {
    try {
      final file = await _settingsFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({'lastVault': _lastVaultPath}));
    } catch (_) {
      // Not worth interrupting the user for; the shortcut is a convenience.
    }
  }
}

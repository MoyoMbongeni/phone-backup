import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/explorer_screen.dart';
import 'screens/start_screen.dart';
import 'widgets/idle_lock.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.load();
  runApp(PhoneBackupApp(state: state));
}

class PhoneBackupApp extends StatelessWidget {
  const PhoneBackupApp({super.key, required this.state});

  final AppState state;

  static const _seed = Color(0xFF3949AB);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Phone Backup',
      debugShowCheckedModeBanner: false,
      navigatorKey: state.navigatorKey,
      theme: ThemeData(colorSchemeSeed: _seed, useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: _seed, brightness: Brightness.dark, useMaterial3: true),
      // Around the navigator, so input in dialogs also counts as activity.
      builder: (context, child) => IdleLock(state: state, child: child!),
      home: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final vault = state.vault;
          if (vault == null) return StartScreen(state: state);
          return ExplorerScreen(key: ObjectKey(vault), state: state, vault: vault);
        },
      ),
    );
  }
}

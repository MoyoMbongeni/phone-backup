// Times the real key derivation and the encryption speed on this machine:
//   dart run tool/bench.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:vault_core/vault_core.dart';

Future<void> main() async {
  final temp = await Directory.systemTemp.createTemp('vault_bench_');
  try {
    final clock = Stopwatch()..start();
    final created = await Vault.create(p.join(temp.path, 'vault'), 'benchmark password');
    print('Create vault (Argon2id 64 MiB, 3 passes): ${clock.elapsedMilliseconds} ms');
    created.vault.lock();

    clock.reset();
    final vault =
        await Vault.unlockWithPassword(p.join(temp.path, 'vault'), 'benchmark password');
    print('Unlock with password: ${clock.elapsedMilliseconds} ms');

    final source = await Directory(p.join(temp.path, 'source')).create();
    final random = Random(1);
    const megabytes = 64;
    await File(p.join(source.path, 'big.bin')).writeAsBytes(
        Uint8List.fromList(List.generate(megabytes << 20, (_) => random.nextInt(256))));

    clock.reset();
    final result = await vault.importFolder(source.path);
    final importMs = clock.elapsedMilliseconds;
    print('Back up $megabytes MiB: $importMs ms '
        '(${(megabytes * 1000 / importMs).toStringAsFixed(1)} MiB/s)');

    final file = vault.index.filesOf(result.sourceId).values.single;
    clock.reset();
    await vault.readFile(file);
    final readMs = clock.elapsedMilliseconds;
    print('Read $megabytes MiB back: $readMs ms '
        '(${(megabytes * 1000 / readMs).toStringAsFixed(1)} MiB/s)');
  } finally {
    await temp.delete(recursive: true);
  }
}

// Times reading small files back the way the explorer's thumbnails do:
//   dart run tool/read_latency.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:vault_core/vault_core.dart';

Future<void> main() async {
  final temp = await Directory.systemTemp.createTemp('vault_latency_');
  try {
    final source = await Directory(p.join(temp.path, 'source')).create();
    final random = Random(3);
    for (var i = 0; i < 12; i++) {
      await File(p.join(source.path, 'photo$i.jpg')).writeAsBytes(
          Uint8List.fromList(List.generate(400 * 1024, (_) => random.nextInt(256))));
    }
    final created = await Vault.create(p.join(temp.path, 'vault'), 'pw',
        kdf: KdfParams.forTests());
    final vault = created.vault;
    final result = await vault.importFolder(source.path);
    final files = vault.index.filesOf(result.sourceId).values.toList();

    final clock = Stopwatch()..start();
    await vault.readFile(files.first);
    print('first read: ${clock.elapsedMilliseconds} ms');
    for (final parallel in [1, 3, 12]) {
      clock.reset();
      await Future.wait([for (final f in files.take(parallel)) vault.readFile(f)]);
      print('$parallel in parallel: ${clock.elapsedMilliseconds} ms');
    }
  } finally {
    await temp.delete(recursive: true);
  }
}

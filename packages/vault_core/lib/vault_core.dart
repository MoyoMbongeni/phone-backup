/// Encrypted, deduplicating backup vault.
///
/// A vault is a folder holding `vault.json` (key slots), `blobs/` (each
/// unique file content once, encrypted) and `log/` (the encrypted change log).
/// Everything else, such as which files exist and where, is rebuilt from the log.
library;

export 'src/cipher.dart'
    show KdfParams, decodeRecoveryKey, encodeRecoveryKey, recoveryKeyLength;
export 'src/errors.dart';
export 'src/events.dart';
export 'src/import_job.dart' show ImportPhase, ImportProgress;
export 'src/index.dart';
export 'src/manifest.dart';
export 'src/vault.dart';

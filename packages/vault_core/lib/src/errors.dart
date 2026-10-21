/// A problem worth showing to the user as a message.
class VaultException implements Exception {
  const VaultException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The password or recovery key does not open this vault.
class WrongKeyException extends VaultException {
  const WrongKeyException(super.message);
}

/// Vault files are damaged, truncated or were changed outside the app.
class VaultCorruptException extends VaultException {
  const VaultCorruptException(super.message);
}

/// A file changed on disk while it was being backed up.
class ContentChangedException implements Exception {
  const ContentChangedException(this.path);

  final String path;

  @override
  String toString() => '$path changed while it was being backed up';
}

/// An encrypted message did not authenticate: wrong key or modified data.
class DecryptionFailed implements Exception {
  const DecryptionFailed();
}

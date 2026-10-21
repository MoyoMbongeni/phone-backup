# Phone Backup – architecture

## Pieces

| Part | Where | Status |
|---|---|---|
| Vault core: crypto, blob store, change log, index, diff, folder backup | `packages/vault_core` (pure Dart + Windows CNG via `dart:ffi`) | Milestone 1, done |
| Desktop app: create/unlock vault, explorer, backup of PC folders | `apps/desktop` (Flutter, Windows) | Milestone 1, done |
| Mobile app: choose what to back up, scan, send | `apps/mobile` (Flutter, Android first) | Milestone 2 |
| Account server: email login, alternate emails, 2FA, relay | not started | Milestone 4–5 |

The phone never stores or decrypts the vault. It sends a list of its files and then the
content the PC asks for; the PC does all vault encryption.

## A vault on disk

```
<vault folder>/
  vault.json, vault.json.bak   format, vault id, Argon2id settings + salt, two key slots
  blobs/ab/<blobId>.blob       one file per unique content, encrypted
  blobs/tmp/                   in-progress writes, cleared on unlock
  log/events.pblog             the encrypted change log
```

`vault.json` is the only plaintext file. It names no files. Losing both `vault.json` and
`vault.json.bak` makes the vault unrecoverable, so a vault should be copied or moved as a
whole folder.

## Keys

- **Master key:** 32 random bytes, created with the vault and never stored in the clear.
- **Password slot:** password → Argon2id (64 MiB, 3 passes, parallelism 1; ≈0.7 s on this
  PC) → key that unwraps the master key.
- **Recovery slot:** 20 random bytes shown once as 32 Crockford base32 characters
  (`XXXX-XXXX-…`, no I/L/O/U) → HKDF → key that unwraps the master key.
- **Subkeys:** from the master key with HKDF-SHA256 (salt = vault id): blob key, blob-id
  key, log key.
- **Changing the password** re-wraps the master key; no file is re-encrypted.
- **Wrapping additional data:** each wrapped key is bound to its vault id and slot name.

## Encryption format

AES-256-GCM, a random 96-bit nonce per message, a 16-byte tag. A sealed message is
`nonce | ciphertext | tag`.

- **Blob file:** `PBB1 | version | chunk size (u32)`, then for each 1 MiB chunk
  `final flag | length (u32) | sealed chunk`. Each chunk's additional data is
  `PBB1 | blobId | chunk index | final flag`, so chunks cannot be reordered, swapped
  between blobs or cut off unnoticed. Large videos never sit in memory whole.
- **Log file:** `PBL1`, then `length (u32) | sealed record`. The additional data is
  `PBL1 | record number`. A record is a JSON list of events written together, so one
  backup run commits all at once.
- **Speed:** on Windows, CNG (`bcrypt.dll`, using the Windows 10+ pseudo-handles) does
  AES-GCM and SHA-256: about 70 MiB/s backing up and 400 MiB/s reading on this PC. Before
  first use it is checked against published test vectors; elsewhere, or if that check
  fails, a pure-Dart backend writes the same bytes at about 7–25 MiB/s.
- **Why AES-GCM and not XChaCha20:** the pure-Dart XChaCha20 ran at about 25 MiB/s.
  AES-GCM is native everywhere (Windows CNG, Android Conscrypt, Apple CryptoKit, OpenSSL).
  With random nonces, the 2^32 messages-per-key limit means 4 PiB of backups.

## Deduplication

The SHA-256 of a file's content gives its blob id: HMAC-SHA256(blob-id key, sha256). The
id is keyed, so blob file names do not reveal which well-known files the vault holds. The
same content anywhere (another folder, a chat app's copy, later another phone) is stored
once. Later references cost only a log entry. Before encrypting, every write hashes the
content again; if the file changed since it was scanned, it is skipped this run and its
last good version kept.

## The change log is the source of truth

| Event | Meaning |
|---|---|
| `vaultCreated` | the vault was created |
| `sourceAdded` | a folder (later: a phone) started being backed up |
| `fileAdded` | a new file appeared in a source |
| `fileModified` | different content at the same path |
| `fileMoved` | the same content at a new path, gone from the old one (rename or move) |
| `fileDeleted` | a file disappeared from its source; its content stays in the vault |
| `snapshot` | a backup run finished, with its counts |
| `passwordChanged` | the password was changed |

On unlock the log is decrypted in a background isolate and replayed into `VaultIndex`.
`VaultIndex.fromEvents(upToSeq:)` rebuilds any past moment (basis for "restore as of a
date"). A file's history follows its renames back to when it was added.

**Backup run:**
1. List the files.
2. Re-use the known hash when size and modification time match.
3. Hash the rest.
4. Encrypt content the vault does not have.
5. Diff against the last state, then commit the events and a snapshot.

**Crash safety:**
- Blobs are written to `tmp/` and renamed into place only after the hash check.
- Events are committed after their blobs, so a crash leaves at most an unused blob.
- A half-written last log record is dropped when the vault is opened.

## Desktop app

**Screens:**
- Start
- Create vault, then recovery key (must be confirmed)
- Unlock, with password or recovery key (the recovery key then asks for a new password)
- Explorer:
  - Files: sources, folders, thumbnails, preview, history, export
  - Deleted
  - Activity (the log)
  - Overview: statistics and where the vault is

**Rules:**
- Decrypted data exists only in memory. Thumbnails use a 150 MB in-memory cache, never
  disk.
- Export writes a normal file after a warning.
- Auto-lock after 10 minutes without input, never during a backup. Locking closes every
  dialog and wipes the keys.
- `lib/file_dialogs.dart` wraps the native pickers so the integration test can answer
  them.

## Transport plan (milestone 2 on)

The same diff runs between phone and PC. The phone sends its list of
`(path, size, modified, sha256)`. The PC replies with the hashes it lacks. The phone sends
only that content.

- **Pairing:** the desktop shows a QR code. Scanning it exchanges keys, and every
  connection after that is mutually authenticated and encrypted.
- **Wi-Fi first.** The phone finds the PC on the local network.
- **USB cable on Android:** `adb forward` carries the same TCP protocol.
- **Internet:** through a relay that only ever sees encrypted data (milestone 5).
- **Bluetooth:** for small data only (contacts, settings, the log), because media over
  Bluetooth takes hours (milestone 5).

## Known limits

- An Android app cannot read other apps' data or take a full system image without root.
  "Everything" means photos, videos, music, documents, contacts, calendar, call log, SMS
  and the app list.
- A full iPhone backup is only possible through the desktop over a cable
  (libimobiledevice, milestone 6).
- If both the password and the recovery key are lost, nobody can recover the data.
- Dart cannot guarantee that no copy of a key remains in memory. Keys are wiped where the
  code holds them.

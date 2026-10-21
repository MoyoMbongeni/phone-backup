# Phone Backup – project instructions for Claude

A Windows desktop app plus an Android app (later iPhone) that back a phone up into an
encrypted, deduplicating vault on the PC. Keep all notes for it in this repository.

## First thing in every session

Read `docs/PROJECT-LOG.md` (decisions, current state, open items) and
`docs/ARCHITECTURE.md` (vault format, keys, protocol plan). Chat history is not kept.

## Keep the log up to date

After every piece of work append a dated entry under **Log** in `docs/PROJECT-LOG.md`
(what was done, where, what is open) and update **Current state** and **Open items** in the
same turn. Never delete past entries; correct them with a new note. If the vault format or
a security decision changes, update `docs/ARCHITECTURE.md` too.

## Layout

- `packages/vault_core` – pure Dart (+ Windows CNG through dart:ffi): crypto, blob store,
  change log, index, manifest diff, folder backup. Shared by both apps.
  `dart test` there; `tool/` has speed probes.
- `apps/desktop` – Flutter Windows app. `flutter test` (widget test) and
  `flutter test integration_test -d windows` (drives the real app; the window must stay
  visible, a minimized Flutter window stops drawing and the test stalls).
- `apps/mobile` – Flutter Android app, milestone 2, not started.

## Toolchain on this PC

- Flutter SDK in `C:\Users\hp\dev\flutter` (on the user PATH; in tool shells prepend
  `C:\Users\hp\dev\flutter\bin` to PATH). Analytics disabled.
- Visual Studio 2022 Build Tools with the C++ workload (for Windows builds).
- `flutter config` has Android disabled for now; milestone 2 needs Android Studio and
  `flutter config --enable-android`.
- Git Bash and PowerShell 5.1. No Node or Python.

## Conventions

- Talk to the user in English; they type fast with typos, infer the meaning.
- App UI text is English for now.
- Nothing in a vault folder may contain plaintext content or file names; tests check it.
  Any change to the on-disk format needs a version bump and a migration.
- Confirm before deleting the user's files or vaults.
- Commit only when the user asks.

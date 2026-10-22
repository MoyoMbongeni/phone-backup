# Phone Backup

Back up a phone to your PC into an encrypted vault that only this app can open.

- **Everything encrypted on disk.** AES-256-GCM. The key is unlocked by your password
  (Argon2id) or a printed recovery key. File names live only inside the encrypted log.
- **Nothing stored twice.** Identical photos (another folder, a chat app's copy, another
  phone) are kept once; the vault just records where each one appears.
- **A log of every change.** Files that are added, changed, renamed or deleted on the
  phone are logged. Deleted files stay in the vault and are listed with their dates.
- **The app's own file explorer.** Browse, preview and export files after unlocking.
  It locks itself after 10 minutes without use.

Milestone 1 (this version) is the Windows app with the vault. It backs up folders on the PC
so the whole flow can be tried. The Android app comes next. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/PROJECT-LOG.md](docs/PROJECT-LOG.md).

## Run it

```bash
cd apps/desktop
flutter run -d windows
```

Release build: `flutter build windows --release`, then run
`apps/desktop/build/windows/x64/runner/Release/phone_backup_desktop.exe`.

## Tests

```bash
cd packages/vault_core && dart test
cd apps/desktop && flutter test
cd apps/desktop && flutter test integration_test -d windows
```

The integration test drives the real app (creates a vault, backs up a folder twice,
browses, exports, locks and unlocks). Keep its window visible while it runs.

## Built with Claude Code: openly vibe-coded

This app is vibe-coded, and I say so proudly. I brought the product: what it must do,
who it is for, and a decision whenever the road forked. [Claude Code](https://claude.com/claude-code),
Anthropic's coding agent, did the engineering. With clear direction it works remarkably
well.

**What I gave it:**
- The idea, in one paragraph: back a phone up to the PC over Wi-Fi, cable or Bluetooth;
  everything or only chosen kinds of files; never store the same photo twice; log every
  change, including deletions; lock the data on the laptop so only the app can open it.
- The calls it asked me to make: Flutter, Android first, a Windows desktop app, and the
  vault before anything else.

**What it did, in one working session:**
- Turned the idea into an architecture and told me up front what phones don't allow: no
  full Android image without root, a full iPhone backup only over a cable, Bluetooth far
  too slow for photos.
- Installed the toolchain after asking first: the Flutter SDK and the Visual Studio Build
  Tools.
- Wrote the vault core, the Windows app and all the tests: 21 core tests, a widget test,
  and an end-to-end test of the real app.
- Measured instead of guessing. Its first, pure-Dart cipher managed only 9 MiB/s, so it
  switched to Windows' own crypto, checked against published test vectors: 70 MiB/s
  backing up, 400 MiB/s reading.
- Drove the real app with screenshots, which caught three bugs before I saw them:
  thumbnails that never finished loading, a password field that lost focus, and a
  recovery key that wrapped badly.
- Kept a project log ([docs/PROJECT-LOG.md](docs/PROJECT-LOG.md)) and its own
  instructions ([CLAUDE.md](CLAUDE.md)), so every later session picks up where the last
  one stopped.

Every commit is co-authored by Claude. One caveat: the encryption follows standard,
well-known designs and is tested against published vectors, but it has not had an
independent security audit yet. Don't make it the only copy of anything you can't afford
to lose until it has.

## Licence

MIT, see [LICENSE](LICENSE). Use it, change it and share it; keep the copyright notice.

## Contact

Mbongeni · mbongenimorey92@gmail.com

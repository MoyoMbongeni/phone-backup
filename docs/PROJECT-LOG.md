# Phone Backup – project log

The memory of this project. Read it first in every session; append to it after every
piece of work. Never delete entries; correct them with a new note.

## Current state (2026-10-21)

- **Milestone 1 (Windows desktop vault): done and tested.**
  - `packages/vault_core`: vault create / unlock (password or recovery key) / change
    password, encrypted deduplicating blob store, encrypted change log, index rebuilt from
    the log, diff (added / changed / moved / deleted), folder backup in a background
    isolate. 21 tests pass.
  - `apps/desktop`: start, create vault, recovery key, unlock, and the explorer:
    - Files: thumbnails, preview, history, export
    - Deleted
    - Activity
    - Overview
    - also: auto-lock after 10 minutes
  - The widget test and the end-to-end integration test (the real Windows app driven
    through a whole session) pass.
  - Release build: `apps/desktop/build/windows/x64/runner/Release/phone_backup_desktop.exe`.
- **Speed on this PC:** unlock about 0.7 s; backup about 70 MiB/s; reading back about
  400 MiB/s; thumbnails 2–4 ms each.
- **Public on GitHub:** https://github.com/MoyoMbongeni/phone-backup (branch `main`,
  published 2026-10-22). MIT licence, copyright Mbongeni.
- **Screenshots** of every screen are in `docs/screenshots/`.

## Open items

**Decisions waiting on the user:**
- What "more access with two or more emails" means: alternate login and recovery
  addresses, or step-up approval through a second email for risky actions (delete
  backups, add a device, restore to another phone). Suggested: both. Needed before
  milestone 4.
- When to add iPhone: it needs a Mac or a paid cloud build service.

**Milestone 2, Android app:**
- Install Android Studio, then `flutter config --enable-android`.
- `apps/mobile`: choose categories (photos/videos through MediaStore first), scan, hash
  natively.
- Pairing by QR code shown on the desktop.
- Wi-Fi transport with the manifest → "send me these hashes" → content protocol.
- The desktop side: devices as sources next to folders.

**Milestone 3:**
- USB cable (adb forward)
- More categories: music, documents, contacts, calendar, call log, SMS
- "Restore as of a date" UI (core support exists: `VaultIndex.fromEvents(upToSeq:)`)
- Restore to a phone

**Milestone 4:** account server: email login, alternate emails, 2FA.

**Milestone 5:** internet mode through a relay; Bluetooth for small data.

**Milestone 6:** iPhone app, plus full iPhone backup over cable through libimobiledevice.

**Smaller things for later:**
- Audio and video preview in the explorer.
- Search and filters in Activity.
- A "verify vault" action that test-reads every blob.
- App icon; installer (MSIX).
- Log checkpoints if very large logs make unlocking slow.

## Log

### 2026-10-21 – project start and milestone 1

- **What the user asked for:** a desktop app paired with a mobile app that backs up the
  phone:
  - over internet, Bluetooth or cable
  - everything or chosen categories
  - no file stored twice, keeping only location references
  - a log of changes, including deleted images
  - login by email, with alternate emails for more access
  - an encrypted vault on the laptop, opened only through the app's own explorer after a
    password
- **Limits I explained:**
  - no full Android image without root
  - a full iPhone backup only via cable plus desktop
  - Bluetooth is too slow for media
  - internet mode needs a relay server
- **The user's decisions:** Flutter, Android first, Windows desktop, project in
  `C:\Users\hp\Projects\phone-backup`, start with milestone 1.
- **Installed (user approved):**
  - Flutter SDK 3.47.7 (Dart 3.13.5), cloned to `C:\Users\hp\dev\flutter`, added to the
    user PATH, analytics off
  - Visual Studio 2022 Build Tools 17.14 with the C++ workload, through winget
  - `flutter config`: Windows on; Android and web off for now
- **Cipher decision:**
  - The first version used pure-Dart XChaCha20-Poly1305. It measured 9 MiB/s for backup
    and 14.5 MiB/s for reads, too slow (pure-Dart AES-GCM was 7 MiB/s, SHA-256
    52 MiB/s).
  - Switched to AES-256-GCM and SHA-256 through Windows CNG (`bcrypt.dll`, dart:ffi):
    70 MiB/s backup, 400 MiB/s read.
  - The pure-Dart backend stays as a fallback that writes identical bytes; tests check
    both against the published GCM and SHA-256 vectors and against each other.
  - CNG uses the Windows 10+ pseudo-handles, which fixed a handle leak in the background
    isolates, and checks itself on a test vector before use.
- **Bugs found by the end-to-end test and fixed:**
  - Thumbnails never finished loading: `whenComplete(() => map.remove(key))` returned the
    pending future itself, so it waited on itself. The callback now has a block body.
  - After a wrong password, focus left the password field. The field now refocuses with
    its text selected.
  - The recovery key wrapped unevenly. It is now shown as two lines of four groups.
- **Testing note:** the integration test opens a real window. If the window is minimized,
  Flutter stops drawing and the test stalls (this happened once).
- **Files:**
  - `packages/vault_core/` (lib, test, tool)
  - `apps/desktop/` (lib, test, integration_test, windows runner titled "Phone Backup")
  - `docs/ARCHITECTURE.md`, `docs/screenshots/`, `README.md`, `CLAUDE.md`

### 2026-10-21 – milestone 1 committed

- The user asked to commit milestone 1. It is the first commit on `main`, with all 79
  source files. Build output and `.dart_tool` are ignored. There is no remote; nothing was
  pushed.

### 2026-10-22 – published on GitHub

- **What the user asked for:**
  - the whole project on GitHub, public
  - nothing exposed that is unrelated to the app
  - their email may be shown
  - the README should openly credit Claude Code and embrace vibe coding
- **Removed:** a mention of the user's other projects from CLAUDE.md. Sample text in the
  tests is now neutral (a grocery list).
- **History:** the first commit had never been pushed, so it was amended rather than
  followed by a fix. The removed text therefore never reaches GitHub history.
- **README:**
  - "Built with Claude Code: openly vibe-coded", covering what the user directed, what
    Claude Code did, the measured speeds and the bugs the end-to-end test caught
  - a note that the crypto has not had an independent audit
  - a contact line with the user's email
- **Published:** a public repository at github.com/MoyoMbongeni/phone-backup, created and
  pushed with the GitHub CLI (logged in as MoyoMbongeni).
- **Open:** no licence file yet; without one the code is visible but not reusable by
  others. The user decides which licence, if any.

### 2026-10-22 – MIT licence

- At the user's request, added `LICENSE` (MIT, "Copyright (c) 2026 Mbongeni", the name
  from their git identity) and a Licence section in the README. Committed and pushed to
  `main`. This closes the licence item above.

### 2026-10-22 – credit in the README

- The user asked for at least 50% of the credit. The README now opens with "Created by
  Mbongeni · built with Claude Code". The vibe-coding section has a "Credit, at least
  50/50" paragraph: the idea, product, requirements, decisions and ownership are the
  user's; the architecture, code, tests and measurements are Claude Code's.
- Not committed yet; commit and push only when the user asks.
- Update: the user asked for it, so it was committed and pushed to `main` the same day.

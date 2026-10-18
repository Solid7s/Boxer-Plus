# Automatic Windows runtime restoration — 2026-10-18

The user correctly remembered automatic Windows setup. The separate project
`/Users/sung/Documents/projects/boxer-work 1.0 (win works well)` contains:

- `Resources/Windows311`: 466 runtime/driver files, 21,101,979 bytes, excluding
  Finder metadata.
- `BXImportSession._generateGameboxWithError:`: copies the bundled `Windows311`
  directory into a new `C.harddisk`.
- Xcode folder-resource entries that include Windows311 in both app targets.

The active project's Windows311 directory held only `.DS_Store`; its importer
and project file did not contain the old resource-copy integration. Earlier
investigation only checked the active checkout, its Git history and recent
build snapshots, and missed this separate working backup.

## Restored behavior

The 466 files have been copied from that backup into the active project's
`Resources/Windows311`, with every restored file hash checked against its source.
The original backup is unchanged. Xcode again bundles that directory.

Starting a detected Windows installer uses the bundled template automatically
when `WINDOWS/WIN.COM` is present. It copies the runtime into the new gamebox
using the background preparation/error-handling path, then launches the disc's
setup through the copied WIN.COM. Each game receives its own writable Windows
installation. The bundle template remains unchanged.

The existing gamebox chooser remains a fallback for builds without the runtime.
The new-game/shortcut chooser at the end of installation remains available.
DOS imports do not copy Windows. Finder metadata and the source placeholder are
excluded from the guest C drive. No renderer, input, GPU or CPU policy changes
are part of this restoration.

## Build and source records

Local runtime files live in `Resources/Windows311` and are ignored by Git;
`.gitkeep` retains the empty resource folder in source snapshots. The source
archive excludes these runtime binaries. To reproduce this local app from that
archive, restore your Windows311 directory before building. Without it, the app
builds with an empty runtime folder and uses the existing-gamebox fallback.

`build/windows-runtime-restoration.json` records the original location and every
restored file's SHA-256. The saved release is
`build/Saved-Releases/2026-10-18-windows-auto-restore/`; its `BUILD-INFO.json`
records installation status and the previous-app backup path.

## Verification

- `release-windows-auto-final.log`: Release build and strict code-signature
  verification passed. The importer introduces no compiler warnings.
- `import-windows-auto-final.log`: the actual Al Unser ISO opened setup without
  a runtime chooser. It copied the bundled Windows files and drivers, installed
  the game and Win32s, restarted Windows, selected the installed game in the
  final chooser, bundled the disc, and exited normally. Cancelling the final
  program chooser returned to installation before retrying successfully.
- `import-windows-fallback-final.log`: a disposable app without Windows311
  correctly showed the runtime chooser. Cancellation, missing-runtime recovery,
  saved-file/deletion handling, and full Al Unser installation/finalization all
  passed with an existing gamebox template.
- `Import-windows-auto-final/verification.json`: all 466 original, project and
  tested-app runtime files retained their original hashes after installation.
  The imported game executable matches the supplied disc, and the bundled ISO
  matches the source ISO. The installed launcher targets
  `C:\ALUNSER\ALUNSER.EXE` through `C.harddisk/WINDOWS/WIN.COM`.
- `import-auto-runtime-dos-final.log` and
  `import-auto-runtime-preinstalled-final.log`: DOS installer execution,
  installed-file creation, preinstalled-folder import, finalization and normal
  exit passed. Neither DOS gamebox received Windows files.
- `import-auto-runtime-scan-final.log`: Windows-only setup recognition,
  uninstaller exclusion and DOS priority on mixed media passed.
- `Windows-auto-runtime-launch/launch.log`: a fresh process opened the gamebox
  created by automatic import, used the saved launcher, completed WinG's
  first-run display calibration and reached the Al Unser title screen. This
  verifies startup, not full gameplay/audio compatibility or performance.

## Separate shutdown observation

The fresh-launch test closed its window and delivered the application termination
notification, but the process then hung. Its helper's “closes normally” line
records that notification and does not establish process exit. A one-second
sample in `Windows-auto-runtime-launch/shutdown-sample.txt` showed the main
thread waiting in `BXKeyboardEventTap._stopTapping` for the event-tap thread,
while that thread was synchronously waiting on the main queue. The disposable
test process was stopped with SIGTERM after saving the sample. The five import
checks above exited successfully on their own.

The keyboard-hook/thread code is unchanged by this restoration. This shutdown
race is recorded for a separate fix; it is not resolved by restoring Windows.

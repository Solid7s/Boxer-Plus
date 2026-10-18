# CUE/BIN importing — 2026-10-18

## What changed

The release candidate had a working CUE/BIN reader and track bundler, but the
import scanner only used host folders and images mounted through macOS.
Selecting a CUE therefore could not discover its installer.

- Added CUE sources to the import chooser/dropzone.
- `ADBImageAwareFileScan` now scans CUE contents through `ADBBinCueImage` instead
  of asking hdiutil to mount them. It respects cancellation and scanner filters.
- `BXInstallerScan` uses the image filesystem for executable type detection and
  game profiles. Windows setup is identified from executable headers, preserving
  the existing DOS-first installer ordering and uninstaller exclusion.
- Corrected CUE logical URLs to use the cuesheet as their base. The underlying
  data-track URL remains an alias for existing references. Installer launch can
  use normal drive/path resolution; no hardcoded D: drive or URL fragments.
- Windows installer launch reads its header through the image filesystem, so the
  Windows 3.x setup workflow still applies to Windows installers inside CUEs.
  Both automatic runtime copying and the fallback gamebox chooser use this check.
- The reader checks that all referenced tracks exist before scanning, including
  audio tracks. The existing `.cdmedia` bundler copies tracks and rewrites paths
  relative to the bundle so the game can reopen independently of its source disc.
- Fixed `configurationURLsForEmulator:` to use its computed gamebox detection URL
  rather than an installer path inside a disc. The latter caused a silent startup
  exception when profile detection asked for a nonexistent host volume. Volume
  detection also now guards against a missing volume URL.
- Disc filename extensions are stripped from automatically generated gamebox names.

Performance/input settings, GPU selection and Windows runtime contents are preserved.

## How to import

Choose **File → Import New Game**, select the `.cue`, choose its installer, and
finish installation normally. Keep every file referenced by the CUE available
until importing finishes. BIN data is read through its cuesheet; a bare BIN is
not offered as a standalone import source.

## Validation and evidence

The user's `Crusader - No Remorse v1.23 (1995)(Origin).cue` references one
MODE1/2048 ISO data track. Tests use fresh app preferences and disposable gameboxes
under `build/`; original disc files and existing user gameboxes are unchanged.

- Crusader `INSTALL.EXE` detected, cancellation/retry exercised, installer launched,
  full installation completed with keyboard/mouse controls and SB16 settings.
- The resulting gamebox contains `C.harddisk/CRUSADER/CRUSADER.EXE` and a `.cdmedia`
  directory with `tracks.cue` and the full ISO. Source and bundled ISO SHA-256
  values match. See `build/crusader-cue-verification.json`.
- A fresh process reached Crusader's main menu with the CD mounted from inside
  its gamebox, rather than the original external drive.
- `Tests/run-cue-check.sh` generates its own small ISO and raw MODE1/2352 BIN,
  plus a separate audio track. It checks exact file reads, nested programs,
  Windows setup detection, logical URL round trips, invalid/missing-track errors,
  byte-for-byte track copying and reopening the bundled CUE.
- `Tests/run-import-check.sh ... disc-installer .../mixed.cue` actually runs a
  generated DOS installer from raw BIN sectors and verifies the installed payload
  and completed gamebox. The final build passed this test and exited successfully.
- DOS folder and Windows-only/mixed-media scan regressions passed. ISO import
  completed correctly, but its process hit the existing shutdown hang.
- Al Unser Jr. Arcade Racing installation through a CUE prepared its
  Windows environment automatically, installed the game, saved its Windows launcher
  and bundled the disc.
- The final build also passed the CUE Windows fallback test: cancellation and
  missing-runtime handling, copying saved Windows changes, installation, final
  launcher selection, disc bundling and successful process exit.

Relevant artifacts:

- `build/Import-crusader-cue-r6/installation-complete.png`
- `build/import-crusader-cue-final-r2.log` and its `commands.json` sidecar
- `build/Game-crusader-cue/main-menu.png` and `results.log`
- `build/Cue-r1/results.log`
- `build/import-cue-final-raw.log`
- `build/import-cue-windows-auto.log`
- `build/import-cue-windows-fallback-final.log`
- `build/release-cue-20261018-final-r2.log`

The final automated Crusader run supersedes early diagnostic attempts. An earlier
test script was edited while running, which disrupted its shell postcheck/log;
subsequent runs use the fixed script and a separate injected library per test.
Termination notifications now say that exit was requested. Only the shell's zero
process exit counts as successful shutdown.

## Limits and release status

The existing keyboard event-tap shutdown race is not fixed by this change.
See `WINDOWS-AUTO-IMPORT-2026-10-18.md`. Disc/import checks do not establish full
gameplay compatibility or audible CD music correctness. The underlying reader
still assumes the first referenced file contains the ISO data track; unusual
audio-first or offset/pregap layouts have not been validated.

Xcode builds with Windows 3.x support require a legally obtained copy of
Windows 3.x supplied by the builder. The final app ZIP, source snapshot,
checksums, release notes and validation records are saved under
`build/Saved-Releases/2026-10-18-cue-bin-final-v1.1.0/`.

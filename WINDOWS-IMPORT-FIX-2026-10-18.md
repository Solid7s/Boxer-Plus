# Windows 3.x importer integration — 2026-10-18

**Follow-up:** the separate `boxer-work 1.0 (win works well)` backup contains
the original automatic-copy code and a complete `Resources/Windows311` runtime.
Those have now been restored as the default local import path. The gamebox
chooser described below is the fallback for builds without that runtime.
See [WINDOWS-AUTO-IMPORT-2026-10-18.md](WINDOWS-AUTO-IMPORT-2026-10-18.md).

Al Unser's mixed Windows/DOS disc was recognized as DOS media because it
contained DOS support utilities, while its Windows setup was excluded from
installer choices. Import New Game then silently copied the disc into a gamebox
without Windows. The earlier DOS fixes did not address this path.

## Behavior

1. Import the disc/folder through **File → Import New Game**. Windows setup
   programs now appear in the installer choices; DOS installers retain priority
   on mixed discs. Uninstallers are excluded from Windows setup suggestions.
2. Launch the Windows installer and choose an existing, closed Windows 3.x
   `.boxer` gamebox. Boxer copies its folder-based C: drive, including installed
   software and saved changes. It does not copy the source game's launchers,
   identity, disc, or startup commands, and does not modify the source gamebox.
3. The copy runs in the background with a preparation status. A failed or
   cancelled preparation returns to selection or closes without keeping a
   partial destination. A missing Windows installation produces a clear error.
4. Setup runs through the copied `WIN.COM`, using the mounted source drive and
   setup's working directory. The copied DOSBox hardware settings are sanitized;
   startup commands from the source gamebox/disc are omitted.
5. When finishing installation, choose the new game's shortcut or executable.
   Cancel returns to installation. Finish saves the selected Windows launcher,
   bundles the disc, and completes the gamebox. Windows files such as `.PIF`
   files are preserved instead of being removed by DOS cleanup heuristics.

Windows itself is supplied by the selected gamebox, not bundled into Boxer.
This workflow does not implement Windows 95/98. The existing NE/PE detector
identifies Windows programs but cannot guarantee that every Windows program
runs under Windows 3.x/Win32s. Templates with image-based C: drives or filesystem
links/special files are rejected with guidance; ordinary folder-based gameboxes
are supported.

## Copy correctness

Runtime copying reads through `ADBShadowedFilesystem` so saved changes replace
base files and deletion markers are respected. Testing exposed an existing
enumerator bug: calling `skipDescendants` for a deleted regular file could skip
the next directory's contents, including the entire Windows directory. It now
calls `skipDescendants` only for deleted directories. The test uses a deleted
file followed by Windows files to exercise this failure.

The copier also preserves hidden files, handles templates without a shadow
folder, and avoids creating metadata in source gameboxes without identifiers.
The new gamebox has an independent identity. Copying uses a temporary directory
and moves it into the destination only after a successful copy.

## Validation record

`Tests/run-import-check.sh` now supports:

- `windows-scan`: generated Win16 headers verify Windows-only acceptance,
  uninstaller exclusion, and DOS priority when a DOS installer is added.
- `windows ISO WINDOWS_GAMEBOX`: real Windows import with a disposable template,
  source-selection cancellation, missing-runtime rejection/retry, saved-file and
  deletion handling, hidden-file preservation, independent gamebox identity,
  final-program chooser cancellation, setup execution, and finalization.
- Existing `installer` and `preinstalled` modes continue to check DOS imports.

The supplied Al Unser ISO is unchanged (SHA-256
`9b2d83a2f21d02d33855ad093c2705ddd3dd27f956122d95d5968664a8edb397`).
The full import first passed in `build/import-win-import-r4.log`: real setup,
Win32s installation/restart, saved `C:\ALUNSER\ALUNSER.EXE` launcher, disc
bundling, and normal exit. Earlier runs caught the saved-deletion enumeration
bug before installation of the app.

Final-candidate checks:

- `import-win-scan-final-r2.log`: Windows-only detection, uninstaller exclusion,
  mixed-media DOS priority, and normal close passed.
- `import-dos-installer-windows-final.log`: generated DOS installer executed,
  wrote the expected executable, completed import, and closed normally.
- `import-dos-preinstalled-windows-final.log`: already-installed DOS folder
  import and normal close passed.
- `import-win-import-final.log`: complete Al Unser installation and finalization
  passed, including runtime-panel cancellation, missing-Windows recovery,
  current saved files, deleted/hidden files, new identity, and cancellation/retry
  of the final program chooser. Template base files remained byte-identical to
  their original sources. The bundled ISO matches the original; installed
  `ALUNSER.EXE` matches the disc. Verification JSON is in the fixture folder.
- `import-descent-windows-final-r2.log`: the actual Descent DOS CD installer
  reported “Installation successful,” entered/exited setup, bundled the disc,
  finalized, and closed normally. All 23 installed disc files matched their
  sources. Original and bundled ISO SHA-256:
  `0997bec58777cc4b475a9fcb89215867ae9d273f06aaf344510734e27d8fbf2a`.
  The first final-candidate run sent its finish command while copying was still
  underway; the second used screen-by-screen timing. No app change was needed.
- `Windows-imported-al-unser-final/launch-direct.log`: a fresh process opened
  the newly imported gamebox, dispatched its saved Windows launcher, completed
  WinG's first-run display calibration, and reached the racing demo. A guest
  screenshot records the running game; closing its window exited normally.
  This was a startup check, not a full gameplay, audio, or performance test.

Build log: `build/release-windows-import-final.log`. Release compilation and
strict signature verification passed. Game/Windows data is confined to ignored
test gameboxes and their separately identified save states.

No renderer, GPU policy, CPU budget, input timing, or scheduler changes were
made for this fix. Source snapshots exclude all Windows/game/ISO test data.

## Saved release

`build/Saved-Releases/2026-10-18-windows-import/` contains the Release app,
dated source archive and manifest, test logs, verification hashes, screenshots,
and these notes. `BUILD-INFO.json` records the installation result and backup
location after `install-local.sh` replaces `/Applications/Boxer+.app`.

# Windows import investigation — Al Unser Jr. Arcade Racing

Correction: this initial investigation missed the separate project backup
`boxer-work 1.0 (win works well)`, which has both the automatic Windows-copy
implementation and its `Resources/Windows311` files. See the restored workflow
in [WINDOWS-AUTO-IMPORT-2026-10-18.md](WINDOWS-AUTO-IMPORT-2026-10-18.md).

This is the initial investigation. The implemented fix and its validation are
recorded in [WINDOWS-IMPORT-FIX-2026-10-18.md](WINDOWS-IMPORT-FIX-2026-10-18.md).

Tested on 2026-10-18 with the installed `/Applications/Boxer+.app`, the saved
2026-10-17 import-fix build. No production app code or installed app was changed
during this investigation. Test helpers and these notes were added to the project.

## Source and isolation

- Disc: `/Volumes/Media SSD/ISOs/Al Unser Jr. Arcade Racing (1995)(Mindscape).iso`
- Size: 27,140,096 bytes. Mounted volume name: `Untitled`.
- SHA-256: `9b2d83a2f21d02d33855ad093c2705ddd3dd27f956122d95d5968664a8edb397`.
- Tests use signed disposable app copies, separate preferences domains, new
  gamebox identifiers, and test gameboxes under the ignored `build/` folder.
- The Windows test copies only the existing Congo gamebox's C drive and DOSBox
  configuration, then adds a copy of this disc as D. It never writes to the
  original Congo gamebox or its save state.
- Guest installation writes go into Boxer's separate shadow state for the new
  test gamebox UUID, as in normal play. Game/Windows/disc data is not included in
  source archives.

## Import New Game: reproduced skipped setup

Both runs bypassed installer selection and copied the disc into `Untitled.boxer`
with an empty C drive. The regression test failed at the expected installer stage.
The second run logged the compiled scanner's actual results:

- DOS programs: `HELP4YOU/CDTEST.EXE`, `HELP4YOU/DISCINFO.EXE`,
  `HELP4YOU/SNAP.EXE`, `SETUP/FREPLACE.EXE`.
- Windows programs included `SETUP.EXE`, `INSTALL/ALSETUP.EXE`,
  `UNSER/ALUNSER.EXE`, `UNSER/CONFIG.EXE`, and `UNSER/NETUNSER.EXE`.
- Installer matches: **empty**. Already installed: **false**. Scan error: **none**.

`BXInstallerScan` only adds DOS-compatible installer names to `matchingPaths`.
The support utilities make this disc pass its DOS-content check. With an empty
installer list, `BXImportSession` calls `skipInstaller`. It does not connect the
detected Windows setup to the Windows chooser or provide a Windows runtime.
This is distinct from the two DOS import bugs fixed on 2026-10-17.

Evidence: `build/import-al-unser-import-r1.log` and
`build/import-al-unser-import-r2.log`. The latter includes scanner diagnostics.

## Existing Windows workflow: installer works

The installed app's **Emulation → Choose Windows 3.x Program…** discovered
`D:\SETUP.EXE` inside the disc and saved it through `C:\WINDOWS\WIN.COM`.
Closing/reopening the disposable gamebox launched the real setup UI.

Observed sequence:

1. English language selection.
2. Installation directory `C:\ALUNSER`.
3. Game file copying.
4. Setup's prompt to install/upgrade Win32s; accepted inside the disposable copy.
5. Setup's restart prompt; accepted, returning to Windows Program Manager.

The installed `ALUNSER.EXE` matches the disc byte-for-byte. Setup created
`WINDOWS\ALUNSERJ.GRP` and installed Win32s version `1.25.142.0` (OLE `2.03`).
The disc's own `INSTALL/UNSER.INF` explicitly implements `WIN31_INSTALL`,
Win32s and WinG installation, and a separate Windows 95 path.

Evidence under `build/Windows-al-unser-r1/`: `choose.log`, `launch.log`,
`language-selection.png`, `directory-selection.png`, `win32s-prompt.png`,
`installation-restart.png`, `after-install-restart.png`, and
`installed-file-verification.json`.

## Installed game startup

The existing chooser also found the newly installed
`C:\ALUNSER\ALUNSER.EXE` through the shadow filesystem and saved it as the
default Windows program. A fresh app process launched it, completed its WinG
first-run display check, reached the title screen, and advanced to the menu on
Enter. This verifies installation and startup, not a completed race, audio, or
input/performance quality. Initial diagnostic captures used an incorrect bitmap
channel/alpha format, making screenshots appear washed out. The test capture
now explicitly converts the renderer's BGRA buffer to opaque RGBA. A fresh launch
with the corrected capture shows normal title-screen colors; this required no
production renderer change.

Evidence: `build/Windows-al-unser-r1/choose-game.log`, `launch-game.log`,
`game-wing-first-run.png`, `game-title-corrected.png`, and
`game-menu-corrected.png`. `launch-game-capture.log` records the final capture run.
Both installer and game sessions exited normally through the window close path.

## Code comparison

These files match the full source manifest from
`build/Saved-Releases/2026-10-17-windows-shortcuts/` byte-for-byte:

- `Boxer/BXInstallerScan.m`
- `Boxer/BXFileTypes.m`
- `Boxer/BXImportSession+BXImportPolicies.m`
- `Boxer/BXSession+BXUIControls.m`
- `Boxer/BXWindowsProgramGroup.m`
- `Boxer/BXSession+BXFileManagement.m`
- `Boxer/BXGamebox.m`
- `Boxer/BXSession.m`

Hashes are recorded in `build/Windows-al-unser-r1/source-comparison.json`.
The existing Windows detection, shortcut handling, and WIN.COM launcher were
not removed by the GPU menu changes or DOS import fixes.

The EXE classifier groups NE and PE executables together as Windows programs;
it does not guarantee Windows 3.x compatibility. This particular game's setup
provides its Win32s dependencies. Recognizing a PE executable alone is not
enough to decide that arbitrary Windows games will run.

## Remaining importer work

To make this disc work directly in Import New Game, connect Windows installer
detection to a workflow that selects an existing Windows 3.x installation,
copies its runtime into a new gamebox with a fresh identity, mounts the source
disc, and runs setup through WIN.COM. Then let the user choose the installed
game/shortcut instead of leaving setup as the startup program. Keep OS/runtime
selection explicit and preserve the source gamebox and its state.

Simply adding Windows EXEs to the DOS installer list would be insufficient:
they need Windows and may need Win32s/WinG. DOS-only imports, mixed-media discs,
Windows-only rejection/help, cancellation, runtime copying, and saved startup
selection need separate functional checks if this integration is implemented.

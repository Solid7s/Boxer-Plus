# Windows 3.x program selection — 2026-10-17

Open a `.boxer` game, then use **Emulation → Choose Windows 3.x Program…**.
Choose its Windows shortcut or game executable and Windows installation, then
click **Save for Next Launch**. Close and reopen the gamebox to use it. Cancel leaves the launcher
unchanged. The chooser does not install Windows: the gamebox must already contain
a working Windows 3.x installation.

The program list shows named Windows 3.x Program Manager shortcuts first,
followed by Windows executables on mounted hard disks and CD images. Shortcut
entries show their source group path; the details underneath show the program,
arguments and working folder that will actually be used. Paths include the drive letter, so a game running from its CD can be
distinguished from installer files on C:. Setup and Windows utilities are also
listed; choose the actual game executable. A missing Windows installation or an
empty program list disables saving. Standalone signed game applications cannot
edit their bundled launchers and do not enable this command.

The shortcut reader handles Windows 3.x `.GRP` files, including their per-item
working-directory extensions. Windows 95 `.LNK` files, DOS `.PIF` shortcuts,
environment-variable expansion and document associations are not implemented.
Unsupported or unavailable targets cannot be saved; raw Windows EXEs remain
selectable. Bare program names are searched in the shortcut's working folder,
the selected Windows folder, then its SYSTEM subfolder. Arguments, including
quoted arguments, are preserved. Windows itself must support the chosen program.

## Congo diagnosis

`Congo - Descent into Zinj.boxer/Game Info.plist` selected
`C.harddisk/WINDOWS/WIN.COM` with `C:\~WING.TMP\_MSTEST.EXE` as its argument.
The installation detector had chosen a temporary WinG setup executable.
Both `C.harddisk/WINDOWS/CONGO.GRP` and `C.harddisk/CONGO/SETUP.LOG` identify
`D:\CONGO.EXE` as the real game. It lives on the bundled Congo ISO, so a normal
macOS file picker restricted to C: would not find it.

The correct launcher uses the same `WIN.COM` with `D:\CONGO.EXE` as its argument.
The Congo shortcut is stored in `C:\WINDOWS\CONGO.GRP`. Its item-table slot is 1
and its working-directory extension is `D:\`. Slot 0 is **Congo Release Notes**,
which uses `C:\CONGO\` and points to a `.WRI` document. This distinction was
verified against the actual group records: the order of strings in the file is
not the order of entries in the item table. The game's save path is separately
configured as `C:\CONGO` in `WINDOWS/CONGO.INI`.
The first launch can run WinG's own display calibration before the game opens.
This is guest software initialization, not Boxer's performance test harness.

The original Congo gamebox now has the corrected argument and explicit startup
marker. Its prior metadata, configuration and recorded user settings are backed
up in `build/Backups/Congo-before-windows-selector-20261017/`. That initial
EXE-only correction did not modify game data, Windows files or save-state overlays.

The subsequent shortcut update records the name **Congo**, group slot 1, and
working folder `D:\`. That metadata change is backed up in
`build/Backups/Congo-before-shortcuts-20261017/`.

## Implementation

- `BXSession+BXUIControls.m` presents the picker. An on-demand `ADBScanOperation`
  reads the existing mounted-drive filesystems, including ISO and shadow layers.
  It uses Boxer's executable-header detector to find Windows EXEs. The ordinary
  DOS launch panel's compatibility filter is unchanged.
- `BXWindowsProgramGroup` reads bounded little-endian offsets, Windows-1252
  strings, sparse item slots and working-directory extension records. It skips
  icons and rejects damaged offsets, strings and zero-length extension records.
  The format was cross-checked against the
  [ReactOS Program Manager reader](https://github.com/reactos/reactos/blob/master/base/shell/progman/grpfile.c)
  and real Congo groups; the new parser is implemented independently.
- Scanning runs off the main thread, after existing file scans. DOS short-name
  resolution and UI updates run on the main thread. Cancel and session shutdown
  cancel the scan; no scanning is added to normal game playback.
- `BXGamebox` atomically writes the selected launcher and reports write errors.
  The Windows executable path remains relative to the gamebox; the selected
  game uses a DOS path, including its CD drive letter. Existing launchers are
  preserved, and saving the same choice does not add duplicates.
- Shortcut selections also save their display name, group/slot identity, complete
  launch command and DOS working directory. The popup's action target stays alive
  until the sheet closes, including after its background scan finishes.
- Session startup and favorite-launcher execution pass an explicit working
  directory to the existing launch API. It validates that folder, changes into it,
  then invokes WIN.COM by full path without switching back to the Windows folder.
  Existing calls without a working directory keep their original behavior.
- `BXLauncherWindowsStartup` marks an explicit startup choice. `BXSession`
  honors a marked default ahead of stale recent-process arguments. Otherwise,
  closing the old Windows process could silently restore the wrong installer.
  Explicitly opening another program and restarting at the launch panel retain
  their existing behavior.
- The renderer, GPU selector, input timing, CPU scheduler and last-window quit
  fix are unchanged from the saved window-close build.

## Validation

`Tests/run-windows-program-check.sh APP LABEL` uses separate app preferences and
a copied Congo gamebox with a fresh identifier. It checks the compiled menu,
discovery of `D:\CONGO.EXE` inside the ISO and Windows EXEs on C:, Cancel without
metadata changes, saving, remembered selection, duplicate prevention, and a
fresh process launching the selected program despite deliberately stale installer
arguments. Both processes must exit normally when their windows close.

The shortcut tests additionally exercise the actual named Congo shortcut and a
synthetic shortcut to WRITE.EXE with a quoted document argument. They verify
saved command arguments, per-shortcut working folders, remembered identity and
that WIN.COM is invoked from Congo's actual working directory. Parser tests cover
the real binary group, sparse slots, quoted commands and malformed/truncated data.

The launch phase captures the guest display at 18, 60 and 120 seconds to inspect
first-run WinG calibration and subsequent startup. It is a startup smoke check,
not a gameplay or performance benchmark. Logs and copied game data remain in
ignored `build/`; no game or Windows files belong in the source archive.

The Release build and both `r1` and `r2` selector runs passed. In `r2`, WinG
calibration progressed at 18 and 60 seconds, and the 120-second capture showed
the game's Illumina Productions opening logo. This verifies startup, not a full
playthrough. The installed app was verified against the saved build in
`build/Saved-Releases/2026-10-17-windows-selector/`; the previous installed app is
`build/Backups/Boxer-before-performance-20261017-222750.app`.

### Shortcut build follow-up

The shortcut build passes `WindowsGroupParserTests` and the `shortcuts-r3` GUI
checks: raw EXEs remain listed, named Congo and synthetic Reader shortcuts are
selectable, quoted arguments and working folders are saved, Cancel leaves the
gamebox unchanged, the same shortcut is not duplicated, and its identity is
remembered. A runtime hook verifies that WIN.COM is invoked from `D:\` without
changing back into the Windows folder. The first GUI runs exposed a popup action
target lifetime bug; the final build retains it until the sheet closes.

The initial full startup capture returned to Program Manager after WinG
calibration. A subsequent launch exposed Congo's “Available digital sound device”
warning. In the isolated overlay, clearing only the `SystemStart` sound in WIN.INI
allowed a launch to proceed into the Viacom intro. This is consistent with a
Windows startup-sound conflict, rather than a missing game executable. The same
single setting is now cleared in Congo's base WIN.INI and existing overlay;
both originals are in `Congo-before-shortcuts-20261017/`. No game audio, driver,
CPU or rendering settings were changed.

The final diagnostic uses raw guest-frame captures, since capturing the Metal
view while its window is hidden returns a black image. A separate small status
window prevents hiding the emulator from triggering last-window termination.
`windows-shortcut-no-startup-chime-raw.log` records the successful 20-second
startup and natural process exit; the 20-second frame shows the game intro.
These checks establish launch behavior, not a full gameplay test. Optional test
environment variables `BOXER_PICKER_SECONDS` and `BOXER_PICKER_HIDE_WINDOW` support
short repeat startup checks after calibration. Diagnostic comparisons must use
the disposable test game and app, never the original gamebox.

The installed shortcut-enabled build and complete source snapshot are saved in
`build/Saved-Releases/2026-10-17-windows-shortcuts/` with checksums and build metadata.

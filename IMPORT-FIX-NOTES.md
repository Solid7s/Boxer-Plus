# Game import fixes — 2026-10-17

The user reported that imports started but skipped the installer or stalled.
Two bugs were reproduced in the installed Release build's import flow:

1. `BXImportSession` only entered the installer-selection stage under
   `BOXER_DEBUG`. Release builds called `skipInstaller` even after detecting a
   valid installer. The importer now offers the installer in both build types.
2. The import session overrides the normal program-start handler to present
   installation tips, but omitted the superclass's `canOpenURLs` update. The
   first installer launch could therefore fail with “Session is not ready” even
   though the DOS shell and source/destination drives were ready. Import-specific
   program-start and shell-return handlers now synchronize that readiness flag.

Both production fixes are confined to `Boxer/BXImportSession.m`. The GPU menu,
Windows shortcut selector, CPU settings, renderer, input timing, and scheduler
are outside this change.

## Validation

`Tests/run-import-check.sh` creates a separate signed test app, preferences
domain, games folder, and a generated DOS installer. The installer writes a
known executable to drive C, so the test confirms actual DOS execution and file
installation. It also checks selection cancellation/retry, finalization, and
normal exit. No existing gamebox or player save is used by the generated tests.

- `import-baseline-r2.log`: reproduced Release skipping a detected installer.
- `import-fixed-r3.log`: after restoring the chooser, captured the independent
  “Session is not ready” launch failure.
- `import-fixed-r4.log`: both fixes passed installer discovery, cancellation,
  execution, installed-file verification, completed gamebox, and normal exit.
- `import-preinstalled-r1.log`: a DOS folder without an installer imported and
  finalized successfully.

An earlier test compilation needed a dynamic delegate cast. The first launch
diagnostic timed out on the readiness error; failure exits now bypass emulator
shutdown handlers so timed-out test processes cannot linger during cleanup.

## Windows scope

This section describes the 2026-10-17 build. The subsequent Windows importer
integration is documented in [WINDOWS-IMPORT-FIX-2026-10-18.md](WINDOWS-IMPORT-FIX-2026-10-18.md).

The existing automatic importer excludes Windows executables from its installer
list and does not provision a Windows installation. It rejects discs with only
Windows executables, but a mixed disc containing DOS support utilities can pass
the scan and silently finish without running Windows setup. This policy predates
the fixes. The existing Windows 3.x chooser **can** detect and run Windows setup
programs in a prepared Windows gamebox. Al Unser's disc confirmed both behaviors;
see [WINDOWS-IMPORT-AL-UNSER-2026-10-18.md](WINDOWS-IMPORT-AL-UNSER-2026-10-18.md).
These fixes do not add an automatic Windows installer workflow or Windows 95/98
support.

## User-provided disc

Source: `/Volumes/Media SSD/ISOs/descent.iso`, 16,830,464 bytes, ISO9660 volume
`DESCENT`. Initial SHA-256:
`0997bec58777cc4b475a9fcb89215867ae9d273f06aaf344510734e27d8fbf2a`.

The image mounts read-only and contains `INSTALL.EXE` plus the `DESCENT` game
directory. macOS `hdiutil imageinfo` reports an internal metadata error on this
image, but read-only mounting succeeds and its ISO logical block size is valid.
The real installer successfully reached its drive and directory selection
screens using the fixed Release build. All test installation output is isolated
under `build/Import-descent-r1/`.

The full Descent import completed successfully: drive/directory selection,
installation, entering/exiting the setup utility, finalizing the gamebox, and
normal app exit. The installer displayed “Installation successful.” Twenty-three
installed files matched the disc byte-for-byte, including `DESCENTR.EXE`,
`DESCENT.HOG`, and `DESCENT.PIG`. The gamebox's bundled `D descent.iso` and the
original ISO both retained the initial SHA-256. The test-mounted disc was then
ejected. This verifies installation, not a full gameplay or audio test.

A second complete run, `import-descent-cold-r1.log`, started with the ISO
unmounted. Boxer mounted it read-only, offered the installer, handled selection
cancellation and rescanning, ran installation/setup, bundled the original ISO,
finished the gamebox, unmounted its disc, and exited normally. The bundled ISO
again matched the original hash. Test output is under
`build/Import-descent-cold-r1/`; the source ISO and existing games were unchanged.

The release app, full source snapshot, these notes, and passing logs are saved
under `build/Saved-Releases/2026-10-17-import-fix/`. Test game data is excluded
from the source archive. No sustained benchmark was run.

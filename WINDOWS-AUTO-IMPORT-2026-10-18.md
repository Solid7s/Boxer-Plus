# Automatic Windows setup — 2026-10-18

## Building with Windows support

Building Boxer+ with Windows 3.x support in Xcode requires your own legally
obtained copy of Windows 3.x. Supply the installation files in
`Resources/Windows311`, preserving the `WINDOWS/WIN.COM` path and any driver
folders. Windows system files are excluded from this source repository.
See [the directory instructions](Resources/Windows311/README.md).

## Import behavior

Starting a detected Windows installer prepares an independent Windows environment
for the new gamebox, then launches setup through WIN.COM. The preparation runs
in the background and supports cancellation and error recovery.

An existing, closed Windows gamebox can also supply the runtime. The copy
preserves saved-file changes, deletion markers, drivers and hidden files. The
source gamebox remains unchanged. At the end of installation, choose the installed
game or shortcut to save for the next launch.

DOS imports do not copy Windows. Finder metadata and source placeholders are
excluded from the guest C: drive. Renderer, input, GPU and CPU policy settings
are unchanged by the Windows import work.

## Verification

- Release compilation and strict code-signature verification passed.
- Al Unser Jr. Arcade Racing setup ran through automatic preparation and the
  existing-gamebox fallback. Tests covered Win32s setup, final launcher selection,
  cancellation, missing-runtime recovery, disc copying and independent gameboxes.
- Runtime and driver files were compared with the supplied test inputs. Original
  runtime and disc data stayed unchanged. The saved launcher targets
  `C:\ALUNSER\ALUNSER.EXE` through `C.harddisk/WINDOWS/WIN.COM`.
- A fresh launch reached the Al Unser title screen after WinG's display calibration.
  This establishes startup, not full gameplay or audio compatibility.
- DOS installer, preinstalled-folder and mixed-media scanner checks passed.
- Detailed local records are under `build/Saved-Releases/` and the corresponding
  `build/import-*.log` files.

## Separate shutdown observation

The fresh-launch test closed its window and delivered the application termination
notification, but the process then hung. Its helper's “closes normally” line
records that notification and does not establish process exit. A one-second
sample in `Windows-auto-runtime-launch/shutdown-sample.txt` showed the main
thread waiting in `BXKeyboardEventTap._stopTapping` for the event-tap thread,
while that thread was synchronously waiting on the main queue. The disposable
test process was stopped with SIGTERM after saving the sample. The original import
checks exited successfully on their own.

The keyboard-hook/thread code is unchanged by this restoration. This shutdown
race is recorded for a separate fix; it is not resolved by the Windows import changes.

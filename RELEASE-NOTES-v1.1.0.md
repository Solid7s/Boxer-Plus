# Boxer+ v1.1.0

This release publishes the current tested local Boxer+ build and its matching
application source, build helpers, test tools, examples, and implementation notes.

## Changes

- DOS ISO and folder importing starts the detected installer and completes
  gamebox creation, with cancellation and retry handling.
- Windows setup automatically receives a private copy of the Windows 3.11
  files bundled inside `Boxer+.app/Contents/Resources/Windows311`. Builds without
  that template can copy an existing Windows gamebox instead.
- Finishing a Windows installation lets you choose the installed executable or
  Windows shortcut. Shortcuts retain launch arguments and working directories.
- Saved Windows-file changes and deletion markers are preserved when copying
  an existing gamebox. Windows driver and `.PIF` files survive finalization.
- CPU menus provide Max Cycle CPU Usage percentages and Automatic Speed Limit.
  Supported Intel Macs can choose Integrated Intel GPU or Discrete GPU; the
  selector is disabled on hardware without both options.
- Retro Light adds a lightweight static scanline effect. The build retains the
  confirmed smooth mouse/input timing and original runtime sleep selection.
- Closing the last window requests application exit. See the shutdown limitation
  below.
- App version metadata is now 1.1.0. The Release build helper handles omitted
  optional arguments correctly with macOS's Bash 3.2.

## Download

`Boxer+.app.zip` contains an Intel x86_64 Release app with its Windows 3.11
template included. The running app reads Windows from its own bundle; the
project folder is not needed after compilation. Source control excludes local
Windows binaries, test gameboxes, game discs, build outputs, and backups.

The app is ad-hoc signed, not Developer ID signed or notarized. Testing was on
an Intel MacBook Pro running macOS 15.7.4. This download is not an ARM-native
build; Apple Silicon execution has not been validated.

## Validation

- Al Unser Jr. Arcade Racing: actual Windows ISO installation through both
  automatic-runtime and fallback paths, Win32s setup, final launcher selection,
  disc bundling, and a fresh launch reaching the title screen.
- Descent: actual DOS ISO installation completed successfully; all 23 installed
  disc files matched their sources in the preceding import validation.
- Generated DOS installer and preinstalled-folder tests; Windows-only setup
  recognition, uninstaller exclusion, and mixed-media DOS priority.
- All 466 bundled Windows/runtime-driver files were verified against the
  restored working template. Original template/disc data remained unchanged.
- Release compilation and strict code-signature validation. Packaging records
  and the ZIP checksum are saved locally with the release artifacts.

## Known limitations

- One fresh-launch test closed its window and began termination, then hung in a
  keyboard event-tap/main-thread deadlock. The import tests exited normally.
  The separate shutdown race remains unresolved; see
  [the recorded sample findings](WINDOWS-AUTO-IMPORT-2026-10-18.md#separate-shutdown-observation).
- The older v1.0 source includes special direct CUE/BIN importer handling that
  is absent from the current local snapshot. This release's import validation
  covers ISO images and folders. Direct CUE/BIN importing is not restored here.
- Windows 3.x/Win32s support does not imply Windows 95/98 support. The EXE
  classifier alone cannot guarantee compatibility with every Windows game.
- Startup/import checks are not full gameplay, audio, or performance validation.

## Build from source

Initialize the existing submodules with `git submodule update --init --recursive`,
restore your Windows template in `Resources/Windows311` if desired, and run
`./build-release.sh`. Set `DEVELOPER_DIR` for a non-default Xcode installation.
The build helper creates an optimized, ad-hoc signed app for the build Mac's
architecture. `./install-local.sh` backs up the previous local app when installing.

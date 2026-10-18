# Boxer+ v1.1.0

This release publishes the current tested local Boxer+ build and its matching
application source, build helpers, test tools, examples, and implementation notes.

## Changes

- DOS ISO, CUE/BIN and folder importing starts the detected installer and completes
  gamebox creation, with cancellation and retry handling.
- CUE imports read installers directly from the disc image, identify DOS and
  Windows setup programs, and preserve the cuesheet and its data/audio tracks
  together inside the gamebox. Missing track files are reported before setup.
- Windows imports prepare an independent Windows environment for each new
  gamebox, with support for copying an existing Windows gamebox.
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

`Boxer+.app.zip` contains an Intel x86_64 Release app. Source control excludes
Windows system files, test gameboxes, game discs, build outputs, and backups.

The app is ad-hoc signed, not Developer ID signed or notarized. Testing was on
an Intel MacBook Pro running macOS 15.7.4. This download is not an ARM-native
build; Apple Silicon execution has not been validated.

## Validation

- Crusader: No Remorse v1.23: installation from the supplied CUE, complete
  gamebox creation, a byte-for-byte verified bundled disc, and a fresh launch
  reaching the main menu.
- Generated raw BIN/mixed-mode disc: installer execution and gamebox creation;
  direct image scanning, Windows setup recognition, missing-track errors,
  and preservation/reopening of both data and audio tracks.
- Al Unser Jr. Arcade Racing: actual Windows ISO installation through both
  automatic-runtime and fallback paths, Win32s setup, final launcher selection,
  disc bundling, and a fresh launch reaching the title screen.
  Windows installation from a CUE also passed automatic and existing-gamebox setup.
- Descent: actual DOS ISO installation completed successfully; all 23 installed
  disc files matched their sources in the preceding import validation.
- Generated DOS installer and preinstalled-folder tests; Windows-only setup
  recognition, uninstaller exclusion, and mixed-media DOS priority.
- Windows import tests verified the copied runtime and driver files against
  their test inputs. Original runtime and disc data remained unchanged.
- Release compilation and strict code-signature validation. Packaging records
  and the ZIP checksum are saved locally with the release artifacts.

## Known limitations

- A keyboard event-tap/main-thread shutdown deadlock was observed after a Windows
  launch and one ISO import. Crusader, raw-BIN and Windows fallback CUE tests
  exited normally. The separate shutdown race remains unresolved; see
  [the recorded sample findings](https://github.com/Solid7s/Boxer-Plus/blob/v1.1.0/WINDOWS-AUTO-IMPORT-2026-10-18.md#separate-shutdown-observation).
- For a CUE/BIN set, select the `.cue` file and keep every referenced BIN/ISO/audio
  file at the location specified by that cuesheet until importing finishes.
  A standalone BIN without its cuesheet is not offered as an import source.
- Windows 3.x/Win32s support does not imply Windows 95/98 support. The EXE
  classifier alone cannot guarantee compatibility with every Windows game.
- Startup/import checks are not full gameplay, audio, or performance validation.

## Build from source

**Building with Windows 3.x support in Xcode requires your own legally obtained
copy of Windows 3.x.** Windows system files are not included in the source repository.
Place your Windows installation files in `Resources/Windows311` before building.

Initialize the existing submodules with `git submodule update --init --recursive`
and run `./build-release.sh`. Set `DEVELOPER_DIR` for a non-default Xcode installation.
The build helper creates an optimized, ad-hoc signed app for the build Mac's
architecture. `./install-local.sh` backs up the previous local app when installing.

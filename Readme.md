![Boxer](http://boxerapp.com/static/images/gloves_96.png)

# Boxer+ 1.1.0

DOS and Windows 3.x games on macOS, with updated imports, Windows shortcut
selection, CPU/GPU controls, and the Retro Light rendering option.

Download **Boxer+.app.zip** from the [v1.1.0 release](https://github.com/Solid7s/Boxer-Plus/releases/tag/v1.1.0),
extract it, and move Boxer+.app to Applications. This asset is an Intel x86_64
Release build, tested on macOS 15.7.4. It is ad-hoc signed and not notarized;
native Apple Silicon execution is not provided by this binary.

**Building with Windows 3.x support in Xcode requires your own legally obtained
copy of Windows 3.x.** Provide the Windows installation files in
`Resources/Windows311` before building, preserving the `WINDOWS/WIN.COM` path.
Windows system files are excluded from this source repository.
See the [v1.1.0 release](https://github.com/Solid7s/Boxer-Plus/releases/tag/v1.1.0) for validation and known limitations,
including the keyboard-hook quit hang.

CUE/BIN importing is supported: select the **.cue** file in Import New Game and
keep its referenced BIN, ISO and audio files together until importing finishes.
Boxer scans the disc directly and bundles its tracks into the finished gamebox.

#### Some notes on building Boxer

The Boxer Xcode project is designed to be a painless one-click build. Here's a quick rundown of how it's set up:

#### Build requirements

To build the Boxer project you will need macOS 10.14 or higher and XCode 11.3 or higher.

All necessary frameworks and other dependencies are included in the Boxer repo, or as git submodules, so the project itself is all you'll need.

After cloning, run:

```bash
git submodule update --init --recursive
```

#### Build Targets

The Boxer project has three targets:

- "Boxer": the standard Boxer emulator you know and love, as seen on http://boxerapp.com. This is almost certainly the one you'll want to use.

- "Boxer Standalone": a cut-down version of Boxer that wraps up a gamebox into a single unified app. Game importing and settings UIs have been stripped out of this version, and it will only launch the gamebox that bundled inside it. This target is not meant to be used on its own: instead it's a build component for…

- "Boxer Bundler": a graphical tool for converting gameboxes into standalone apps using its own self-contained copy of Boxer Standalone.

#### Build Configurations

The Boxer target has two build configurations. Release enables compiler optimization and is the configuration to use for playing games. Debug uses `-O0` / `-Onone`, additional checks and logging; its emulation performance and energy use are not representative of Release.

Run `./build-release.sh` to build and verify an optimized, locally signed app in `build/Release/Build/Products/Release/Boxer.app`. Set `DEVELOPER_DIR` if Xcode is installed outside the selected developer directory. The script builds for the current Mac's architecture and does not replace the installed app.

The script also removes the retired ordinary-sleep-only core patch from older working trees, restoring DOSBox's original runtime sleep selection. Run `./BuildSupport/apply-core-patches.sh` once before building directly in Xcode. Fresh submodule checkouts already have the correct timing code; `BuildSupport/dosbox-energy.patch` is retained only to recognize and undo that older patch.

**File → Import New Game** offers DOS and Windows setup programs. Windows imports prepare an independent Windows environment for each new gamebox. Finish setup, then choose the installed game or shortcut to save. The importer can also copy an existing, closed Windows gamebox. DOS imports do not copy Windows. This does not add Windows 95/98 emulation.

During a game, **Emulation → Max Cycle CPU Usage** offers 50%, 75% and 100% budgets, saved separately for each game. These percentages scale DOSBox's automatic CPU target in Maximum speed mode, not the whole Mac's CPU usage. Use a higher budget if a demanding game slows down; the CPU slider still provides fixed speeds for older games.

**Emulation → Automatic Speed Limit** adds a per-game ceiling to automatic mode. Choose a preset or **Use Current Speed** after checking a demanding scene; select **Unlimited** to remove the ceiling. This limits emulated CPU speed, not frame rate. Existing games retain their configured limit until you select a new one.

**View → Graphics Processor (Reopen Game)** offers **Discrete GPU** and **Integrated Intel GPU**. Discrete GPU is the default on supported Macs; your selection is remembered. Close and reopen the game to apply a change. Both choices are disabled on Apple Silicon Macs and Macs without both a built-in Intel integrated GPU and a separate built-in discrete GPU; those Macs continue using their available GPU. **View → Rendering Style → Retro Light** adds static scanlines with one shader pass. The original animated Retro effect remains available.

Closing the last window now quits Boxer. Closing an active game still shows its close confirmation unless you previously disabled that prompt; choosing **Cancel** keeps it running. If another window is open, Boxer stays open until that window is closed.

For compiler comparisons, use `BOXER_LTO=NO` or `BOXER_LTO=YES_THIN` with `./build-release.sh`. Optional positional arguments are the build directory, LTO mode, and cached Swift packages directory, in that order. Keep separately copied apps for A/B measurements.

The [Quiet example](Examples/DOSBox-Quiet.conf) provides a general CPU budget; the [Duke performance profile](Examples/Duke-Performance.conf) adds the tested 100,000-cycle ceiling for 320×200 playback. Active per-game settings live in the gamebox's `DOSBox Preferences.conf` and Boxer's user preferences, so uploading the source does not automatically change another user's games. Select the budget and speed limit from the Emulation menu after launching a game to update both locations.

The [Duke autolaunch example](Examples/Duke-Autolaunch.plist) records `C.harddisk/DUKE3D/DUKE3D.EXE` as the default program. Merge these fields into the gamebox's `Game Info.plist` while Boxer is closed; preserve the existing game identifier and any other launcher entries. This is a partial configuration example, not a replacement for the entire metadata file. A default launcher lets the gamebox start Duke without depending on that Mac's recent-program history.

#### Uploading these changes

For Windows 3.x gameboxes, use **Emulation → Choose Windows 3.x Program…** to
choose a named Windows shortcut or the game's executable, including one on a
mounted CD image. Shortcuts retain their arguments and working folder. Click
**Save for Next Launch**, then close and reopen the game. This requires Windows
to be installed in the gamebox.

Include the modified source and Xcode files along with `BuildSupport/`, `Examples/`, `Tests/`, and both shell scripts. Keep the existing submodule references and `.gitmodules`; a new checkout needs `git submodule update --init --recursive` before building.

The ignored `build/` directory contains generated apps, backups, benchmark logs and copied game/CD files. Exclude it when uploading or making a source ZIP. Git already excludes it through `.gitignore`; newly added source, scripts, examples and documentation still need to be added to your commit.

#### App requirements

Boxer and Boxer Standalone both run on macOS 10.14.4 and above, while Boxer Bundler runs on OS X 10.8 and above.

OSX 10.5 and PowerPC support has been removed from the Boxer master branch: if you need these, use the older "leopard_legacy" maintenance branch from http://github.com/alunbestor/Boxer/tree/leopard_legacy/.

#### Having trouble?

If you have any problems building the Boxer project, or questions about Boxer's code, please get in touch with me at abestor@boxerapp.com and I'll help out as best I can.

#### License

The project is licensed using [GPLv2](./LICENSE). Originally developed
by Alun Bestor and other contributors.

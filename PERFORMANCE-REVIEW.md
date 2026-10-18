# Boxer performance fixes — 2026-10-17

## Implemented

1. **Optimized playback build.** The installed Boxer+ was a Debug build whose
   compiler response files contained `-O0`, `BOXER_DEBUG`, and debug standard
   library hardening. Its `Boxer.debug.dylib` matched the old Xcode DerivedData
   product. The project now explicitly uses `-O2` for Release C/C++/Objective-C
   and retains Swift `-O`. Debug remains available for debugging. The Release
   build has a normal executable, without `Boxer.debug.dylib` or `__preview.dylib`.
   `build-release.sh` builds, signs and verifies it; `BuildSupport/Package.resolved`
   pins the tested Swift package versions. `install-local.sh` preserves the old
   application before replacing `/Applications/Boxer+.app`.

2. **Persistent per-game CPU budgets.** Emulation → Max Cycle CPU Usage offers
   50%, 75% and 100%. These use the existing DOSBox
   scheduler rather than changing emulated hardware timing. DOSBox's percentage
   scales its approximately 90% automatic CPU target; it is not a whole-machine
   utilization cap. Fixed speeds and fast-forward preserve the selected budget.
   Settings survive relaunches, including a fixed-speed configuration followed
   by switching back to automatic. Existing explicit cycle ceilings are retained.
   Automatic configuration strings include the percentage and optional limit;
   inactive-emulator saves use the recorded policy instead of default getters.
   Games without an explicit UI override retain their existing configuration.

3. **Render only necessary work.** Normal and smoothed rendering use MTKView
   invalidation. CRT keeps its frame-count animation while active and visible,
   and stops the timer while paused, hidden or occluded. Exposure, resizing,
   backing-scale changes, viewport animation and shader parameters invalidate
   the image. Fixed the viewport setter calling the `needsDisplay` getter.
   Changed scanlines are copied to a pending CPU buffer before DOSBox reuses its
   frame and dirty list. Ranges accumulate until presentation and only those
   rows are uploaded. Texture writes wait for the previous GPU submission to
   complete without blocking the emulation thread on a semaphore. A busy GPU
   preserves the pending update and completion schedules a retry. Offscreen
   filters and final presentation share one command buffer, with at most one
   frame in flight. Forced updates do not reuse a stale dirty list; interrupted
   pixel writes conservatively mark the entire source dirty.

The renderer follows Apple's [MTKView drawing-mode documentation](https://developer.apple.com/documentation/metalkit/mtkview/).
The existing Intel dynamic CPU core remains in use; this is not a replacement
emulator or an upgrade of the DOSBox-Staging submodule.

## Measured on this Mac

Intel MacBook Pro, macOS 15.7.4, AMD Radeon Pro 5500M, x86_64 builds.
Sequential Duke Nukem 3D Atomic Edition attract-mode probes used copied game
files, the complete CD image, independent game identifiers/preference domains,
and the current overlay's 320×200 video and audio configuration. No original
save files were changed. Dynamic core was verified in every run.

| Build / automatic setting | Mean process CPU | Mean automatic cycles | Presented frames/s |
| --- | ---: | ---: | ---: |
| Previously installed Debug / Maximum | 87.6% | 199,127 | not instrumented |
| Unchanged source Release (`-Os`) / Maximum | 79.2% | 275,915 | not instrumented |
| Updated Release (`-O2`) / Balanced | 70.5% | 224,900 | 52.0 |
| Updated Release (`-O2`) / Quiet | 52.4% | 97,965 | 53.8 |

These are short spot checks, using samples from approximately seconds 20–44
of the graphics-mode probe, after startup. Process CPU is CPU time / wall time;
100% represents one core. Presented frames/s is measured from actual GPU
submissions, not the game's simulation rate. Different demo timing, scene cost
and scheduler adjustments affect the comparison. Quiet used about 40% less
process CPU than the installed Debug build in this test and continued playing
the demo. This does not measure fan RPM, temperature, total system power, input
latency or every demanding scene. Audio devices initialized; subjective audio
quality and a complete interactive play-through still need user validation.

Duke's original `DOSBox Preferences.conf` is set to `cycles=max 50%` (Quiet).
Its previous file is preserved at
`build/Backups/Duke-DOSBox-Preferences-before-performance.conf`.
Use Balanced or Maximum from the Emulation menu if a demanding scene needs
more emulated CPU speed. Other gameboxes' CPU settings were not changed.

## Verification

- Release build succeeded; actual emulator compiler response files contain
  `-O2`. Signature verification with `codesign --verify --deep --strict` passed.
- Renderer integration suite passed against the compiled application: first
  frame, unchanged frames, pixel-accurate dirty-row coalescing, GPU backpressure,
  CRT animation, pause, shader controls while paused, occlusion/exposure,
  resizing, clearing and restoring a source. Sending 120 unchanged frames
  produced **zero additional draws and zero additional texture upload bytes**.
- CPU integration checks passed for menu state, percentage and limit
  serialization, fixed/automatic transitions, turbo, saving, restoring a
  per-game policy over fixed cycles, and saving after the emulator stops.
- Duke entered and stayed in graphics mode through the successful probes.
  Captures confirm the demo ran in both new modes. The first discarded probe
  omitted the CD and returned to the shell; it is excluded from all results.
- Shell scripts passed syntax checks; `git diff --check` passed.

Raw logs/captures: `build/renderer-tests.log`, `build/probe-debug-cd.log`,
`build/probe-release-original.log`, `build/probe-enhanced-balanced.log`,
`build/probe-enhanced-quiet.log`, `build/probe-policy-restore.log`, and
`build/performance-results.json`. Reproduction instructions are in
[Tests/README.md](Tests/README.md). Test apps and fixtures are deliberately
separate from the user's gamebox and are not included in the installed app.

## Remaining optional work

The selected AMD GPU still contributes to power use. A selectable integrated
GPU could be evaluated separately, particularly for normal scaling; external
displays and shader complexity need testing before changing device selection.
No GPU-selection or DOSBox CPU-core rewrite was made in this change.

## Installed result

The verified Release build was installed at `/Applications/Boxer+.app` on
2026-10-17. Its executable SHA-256 matches the tested build:
`5bd0e7ac316e318579684d83c7a11462ec09530257ad3789cedda0a79768fd0b`.
Post-install strict signature verification passed, and no Debug dylib remains.
The previous application is preserved at
`build/Backups/Boxer-before-performance-20261017-165826.app`.
Close Boxer before restoring that backup, if needed. The separate Duke
configuration backup listed above restores its prior maximum-speed setting.

## Duke gamebox startup correction

The original gamebox's `Game Info.plist` contained only its game identifier and
identifier type, with no default program or launchers. Startup therefore depended
on Boxer remembering a previously launched program in that Mac's preferences.
The gamebox now explicitly marks `C.harddisk/DUKE3D/DUKE3D.EXE` as its default
launcher, with the legacy default-program field pointing to the same file.
The executable path and plist syntax were verified, and the game identifier was
preserved. The original metadata is backed up under
`build/Backups/Duke-Game-Info-before-autolaunch-*.plist`.
Reusable metadata fields are in `Examples/Duke-Autolaunch.plist`; merge them
without replacing another gamebox's identifier. This is a gamebox configuration
change and does not replace or re-sign the installed application.

## Second performance pass — implementation

The five follow-up areas were GPU selection, game-specific speed ceilings,
host scheduling, filter cost, and compiler optimization. This pass preserves
the existing DOSBox engine and Intel dynamic CPU core.

### GPU selection

The old renderer requested `MTLCreateSystemDefaultDevice()`, which selected the
AMD Radeon Pro 5500M on this Mac. The renderer now prefers a non-removable
`isLowPower` device in both programmatic and archived-view initialization.
Single-GPU systems fall back to the system default. The main and standalone app
plists declare `NSSupportsAutomaticGraphicsSwitching`.

The View menu offers Energy Saving and High Performance. The setting takes
effect when a new game window is created; live device replacement would require
rebuilding all textures and pipelines. The renderer integration test verifies
Intel UHD 630 selection and the explicit system-GPU choice. This does not prove
that the discrete GPU powers down: displays and other applications can still
require it. GPU time and process CPU are not measurements of total system power.

Reference: [Apple's GPU selection sample](https://developer.apple.com/documentation/metal/selecting-device-objects-for-graphics-rendering).

### Per-game speed ceilings

The Emulation menu now exposes the existing automatic cycle ceiling: Unlimited,
50k, 75k, 100k, 150k, 200k, and Use Current Speed. The last option captures a
user-calibrated speed after testing a demanding scene. A lower ceiling applies
immediately in automatic mode, while fixed-speed and fast-forward policies remain
independent. Both the percentage and ceiling are saved with each game and in the
portable DOSBox configuration. No universal ceiling is silently applied to games.

### Scheduler and bridge overhead

A five-second sample of the old build found the `DelayPrecise` path repeatedly
sleeping for 100 microseconds and then yielding/spinning, plus AppKit pumping
from `Normal_Loop` and retain/autorelease traffic in the cancellation check.

- The host delay now uses ordinary OS sleep. The scheduler still catches up
  based on actual elapsed time; DOS device ticks, audio mixing and interrupt
  timing are unchanged.
- Both event-pump entry points use the existing 200 Hz limiter. The deadline is
  advanced before pumping so reentrant emulation cannot bypass it. Paused
  sessions continue processing AppKit events until resumed.
- Synchronous core-loop hooks use a borrowed singleton already retained by
  `BXEmulator.start`, avoiding per-dispatch retain/autorelease work. The public
  accessor keeps its original lifetime semantics; nested autorelease pools remain.
- The event-pump return value now follows the actual continuation check.
- `BOXER_LEGACY_SCHEDULER=1` restores the old polling/sleep behavior for A/B
  measurements. It is an opt-in diagnostic, read once per process.

The DOSBox source change is preserved in `BuildSupport/dosbox-energy.patch`.
The build helper applies it idempotently and stops if the submodule has an
incompatible revision. Upload that patch with the parent repository; the changed
submodule working tree alone is not portable.

### Retro Light

The new Retro Light style uses a single texture sample and a static scanline
effect, rendered directly at viewport size. Scanlines fade away when the output
is too small to resolve them. It uses no curvature, blur passes or temporal
animation, and unchanged frames do not redraw. Existing Retro retains its
appearance and animation. Metal already handled the other styles without DOSBox
software scaling, so no redundant CPU-scaler rewrite was needed.

### Compiler experiment and measurements

The release helper accepts `BOXER_LTO=NO`, `YES_THIN`, or `YES` (also its second
positional argument). ThinLTO is compared at the same fixed emulated speed;
automatic mode would otherwise spend efficiency gains on more emulated cycles.
No unsafe floating-point flags or CPU-specific instruction requirements were added.
Reference: [Clang ThinLTO documentation](https://clang.llvm.org/docs/ThinLTO.html).

Completed validation and measured results for this pass are recorded below.
The first long baseline's log was invalidated by editing its running shell
wrapper, so it is excluded. It was not repeated before benchmarking ended at
the user's request. An initial test-only audio interposer
also recursed through `dlsym`; it was corrected to use dyld's original direct
binding. Neither discarded run changed the installed application or user saves.

The completed compiler comparison used separate 180-second runs, fixed 100,000
cycles, Original rendering and Intel graphics, with the first 20 seconds excluded:

| Build | Mean process CPU | Presentations/s | Sampled empty audio queues | GPU errors |
| --- | ---: | ---: | ---: | ---: |
| Ordinary `-O2` Release | 48.56% | 49.88 | 0 | 0 |
| `-O2` with ThinLTO | 47.11% | 53.76 | 0 | 0 |

This is about 3% less CPU in one pair, but differing scene timing and GPU clock
behavior make it inconclusive. Both builds passed the renderer suite. ThinLTO
remains an explicit build option; ordinary Release stays the default. No PGO
profile is shipped from this single-game workload. The raw comparison is in
`build/round2-compiler-results.json`; presentation counts are not simulation FPS.

The final Release build's ceiling trials used Original rendering and Intel
graphics. Each ran for 90 seconds, excluding the first 20 seconds from averages:

| Automatic policy | Mean process CPU | Presentations/s | Sampled empty audio queues |
| --- | ---: | ---: | ---: |
| Quiet, 75,000 ceiling | 40.70% | 56.54 | 0 |
| Quiet, 100,000 ceiling | 48.68% | 59.29 | 0 |
| Quiet, 150,000 ceiling | 52.09% | 57.31 | 0 |
| Balanced, 100,000 ceiling | 50.68% | 56.36 | 0 |

Quiet with a 100,000 ceiling is the candidate Duke profile: it leaves more
headroom than 75,000, while the higher settings did not help this demo workload.
Scene timing varies, so these are spot checks rather than a precise ranking for
every combat scene. `Examples/Duke-Performance.conf` records this 320×200 profile.

The final Release build's shader trials used fixed 100,000 cycles and Intel
graphics, with 90-second runs and the first 20 seconds excluded:

| Rendering style | Mean process CPU | Presentations/s | GPU milliseconds/frame | Sampled empty audio queues |
| --- | ---: | ---: | ---: | ---: |
| Retro | 48.21% | 55.20 | 7.37 | 4 |
| Retro Light | 48.33% | 58.72 | 1.57 | 0 |

Retro Light used about 79% less GPU execution time per completed frame in this
sample. Neither run reported GPU errors. Empty-queue samples indicate possible
audio starvation, not a precise count of audible glitches. These measurements
do not establish fan speed, temperature, total power, or performance in every
scene. The user's existing rendering preference was Original, not Retro.

### Validation status when benchmarking ended

Benchmarking ended at the user's request on 2026-10-17. The final acceptance
runner had completed successfully by the process check; no benchmark runner or
test app remained running. No further benchmarks were started.

The final ordinary Release build passed renderer integration checks, automatic
speed policy and persistence checks, pause/resume event processing, all four
ceiling trials, both shader trials, and normal-core compatibility probes for
Ultima Underworld and Epic Pinball (including its launcher handoff to EP1).
Results are preserved in `build/*final1*.log`. The planned repeated 10-minute
before/after comparison was not run, so sustained thermal improvement remains
unverified.

The completed build is at
`build/ReleaseBaseline/Build/Products/Release/Boxer.app`. At this stopping point
it has not replaced `/Applications/Boxer+.app`, and the original Duke game
configuration has not been changed to the candidate 100,000-cycle ceiling.
All source changes, the portable DOSBox patch, the example profile, and test
scripts remain saved in this project.

### Saved release — 2026-10-17

The tested build is preserved independently of Xcode's build output in
`build/Saved-Releases/2026-10-17-performance/Boxer+.app`, with a ZIP archive,
these performance notes, and `BUILD-INFO.json` recording SHA-256 checksums.
The copied app passed strict code-signature verification and its executable
matches the tested build. Executable SHA-256:
`a7e62c7934e40d490d0c0ac2d07e3937d0c56923a2ab72d7abf13140c05cb56e`.
Saving this release did not start additional benchmarks or replace the installed
app. The saved artifacts are under the existing ignored `build/` directory.

### Installed saved release — 2026-10-17

The saved performance build now replaces `/Applications/Boxer+.app`.
The installer verified its code signature, and the installed executable
SHA-256 matches the saved release recorded above. The previous app is
preserved at `build/Backups/Boxer-before-performance-20261017-203116.app`.
Game files and preferences were not changed during installation.
No new benchmark was run.

### Restored preceding app — 2026-10-17

At the user's request, `/Applications/Boxer+.app` was restored from
`build/Backups/Boxer-before-performance-20261017-203116.app`, the version
installed immediately before the latest performance update. Signature
verification passed and the installed executable matches that backup:
`5bd0e7ac316e318579684d83c7a11462ec09530257ad3789cedda0a79768fd0b`.
The replaced performance build is retained in the saved release folder
and `build/Backups/Boxer-before-performance-20261017-204951.app`.
No Boxer process was running at restoration, so the temporary input
observer was no longer active. Source changes, games, and preferences
were preserved. No benchmark was run.

### Explicit GPU menu release — 2026-10-17

The newer performance build now offers the actual GPU names under
**View → Graphics Processor (Reopen Game)**. On this Mac, the choices are
**AMD Radeon Pro 5500M (Performance)** and
**Intel(R) UHD Graphics 630 (Energy Saving)**. Selection is remembered globally
using `useHighPerformanceGPU`; close and reopen the game to apply a change.
New installations default to the built-in discrete GPU when one is available.
Existing saved choices are respected. A Mac with one available GPU uses its
default device and disables the unavailable alternative.

The selector explicitly finds the built-in discrete or integrated Metal device,
rather than assuming that the system default always means the performance GPU.
This release keeps the newer scheduler and other second-pass improvements.
The SimTower latency investigation remains documented in
`SIMTOWER-MOUSE-LAG-PLAN.md`; selecting AMD has not yet been shown to fix its lag.

The ordinary Release build succeeded, and the compiled menu/renderer checks
passed on both AMD Radeon Pro 5500M and Intel UHD Graphics 630. Checks cover
device selection, labels, checkmarks, saved settings, rendering after selection,
and keeping existing renderers on their original device. The existing renderer
functional checks also passed. No game benchmark or mouse-latency measurement
was run. Logs: `build/release-gpu-menu.log` and `build/renderer-gpu-menu.log`.

The installed `/Applications/Boxer+.app` matches the saved release executable:
`8460587f3ff73752ba6e8e7e9aab1e18fc899ac144003a69a1e40c81b80f1d7c`.
AMD is selected in the real user preferences; the previous value (`0`, Intel)
is recorded in the release manifest. The preceding app is preserved at
`build/Backups/Boxer-before-performance-20261017-210243.app`.

The app, ZIP, matching source snapshot, checksums, and validation log are saved
in `build/Saved-Releases/2026-10-17-gpu-menu/`. The source snapshot includes the
working source and nested repository contents, with a per-file manifest;
build products, games, Git history, and cached Swift package checkouts are
excluded. Swift package versions remain pinned by the project. This snapshot
matches the new GPU-menu build; it does not recover the missing exact source
snapshot for the older restored app.

### Input timing restoration — 2026-10-17

The GPU selection and fixed-speed/larger-window comparison did not resolve
the user's regular SimTower mouse stutter. The newer build now restores the
previous main-loop AppKit polling and DOSBox's runtime sleep selection. Extra
idle-callback polls retain their original 200 Hz limiter. The GPU menu, dirty-row
renderer, Release optimization, CPU budget/ceiling controls, and Retro Light
remain. The retired core patch is reversed automatically on older working trees;
fresh submodules need no core modification.

The Release build and short queued-motion, pause/resume, capture, and button
checks passed. In comparable small-window probes, steady queue delay p99 was
5.59 ms with the preceding GPU-menu build and 1.88 ms after timing restoration.
This measures the event queue, not total mouse-to-screen latency. The user also
reported smoother real movement in the new small test window, then confirmed
the installed build was "beautifully smooth" in their normal SimTower session.
No sustained or thermal benchmark was run,
so any CPU/power tradeoff from restoring the timing paths remains unmeasured.

Detailed results, failed test-setup attempts, and comparison limitations are in
`SIMTOWER-MOUSE-LAG-PLAN.md`. The verified app and matching source are saved in
`build/Saved-Releases/2026-10-17-input-timing/`; its manifest records installation
status and checksums. The executable SHA-256 is
`ed8ee9a6adac89bed87ec8f3eb51965e6c60a8161881556041f0517c7cd12ed8`.

### Confirmed smooth baseline saved — 2026-10-17

At the user's request, the confirmed app and matching source are preserved in
`build/Saved-Releases/2026-10-17-confirmed-smooth/`. The installed executable
matches the saved app checksum above. This is the accepted baseline for future
changes: the restored main-loop polling and sleep selection, GPU menu, and
other retained performance improvements. SimTower was confirmed at 640×480,
with AMD selected, automatic CPU at 100%, and no automatic cycle ceiling.
The dated release includes the app ZIP, source archive and per-file manifest,
build information, investigation notes, and validation logs. Saving it does
not rebuild, replace, or interrupt the running app.

### Quit after the last window closes — 2026-10-17

The user reported that closing the window left Boxer running. The application
delegate deliberately returned NO from its last-window termination callback
unless another Boxer with the same bundle identifier was running. It now returns
YES, letting AppKit quit after the final window closes. The no-document quit
path also now checks `self.documents.count == 0`, instead of comparing the array
object to nil. Normal close confirmation, cancellation, settings synchronization,
and cleanup remain in place.

The Release build and lifecycle checks passed. The preceding confirmed-smooth
app reproduced the issue (`window-close-baseline-r1.log`). The updated app passed
cancel/accept, emulator cancellation, settings persistence, and natural process
exit (`window-close-fixed-r2.log`). A second check verified that another window
keeps the app alive until that final window closes (`window-close-companion-r1.log`).
The initial fixed-r1 test used the emulator setter instead of the session setter
for its saved speed limit; its persistence assertion was a test setup error,
corrected before the passing checks. The saved preferences were also verified
on disk after normal exit.

Only `Boxer/Application Delegate/BXAppController.m` changes production behavior
relative to the user-confirmed smooth source. Mouse timing, CPU scheduling,
rendering, GPU selection, and game settings are unchanged. The accepted baseline
remains in `build/Saved-Releases/2026-10-17-confirmed-smooth/`. This update is saved
with matching source and validation logs in
`build/Saved-Releases/2026-10-17-window-close/`; its manifest records the checksums,
installation status, and previous-app backup. No new performance benchmark was run.

### GPU menu labels and hardware availability — 2026-10-17

**View → Graphics Processor (Reopen Game)** now uses **Discrete GPU** and
**Integrated Intel GPU**. Both choices are enabled only when Metal provides
distinct, non-removable devices for a low-power Intel integrated GPU and a
discrete GPU. The existing system-default fallback is not treated as a second
device. Apple Silicon, including an Intel build running under Rosetta, and Macs
without both built-in GPU types have both choices disabled and unchecked. The
selection action also refuses to change the stored preference on those Macs.
GPU selection still applies when reopening a game; existing saved choices and
the renderer's available-device fallback are retained.

Validation: the Release build and compiled menu/renderer checks passed on this
Intel MacBook Pro, with successful rendering on Intel UHD Graphics 630 and AMD
Radeon Pro 5500M. Eight simulated device configurations exercise disabled menu
items and refusal to overwrite either saved preference, including Apple Silicon,
Intel-only, discrete-only, external-GPU alternatives, and missing devices.
This is simulated coverage of other hardware, not a physical Apple Silicon test.

The first renderer run exited during its occlusion check because the earlier
last-window quit fix was now active. The test harness now keeps a companion
window open and requires the final completion marker, so an early normal app
exit cannot be mistaken for a complete pass. The full repeat passed; logs are
`build/release-gpu-menu-availability.log` and
`build/renderer-gpu-menu-availability-r2.log`. No gameplay benchmark was run.
The app, source, notes, and logs are saved in
`build/Saved-Releases/2026-10-17-gpu-menu-availability/`.

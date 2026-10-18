# Performance regression checks

`./Tests/run-import-check.sh APP LABEL installer` exercises the compiled import
flow using a generated DOS COM installer and an isolated games folder. It checks
leaving Welcome, installer discovery, cancelling/retrying the selection, launching
the installer through its UI button, writing an actual program to drive C,
finalizing the gamebox, and normal app exit. `preinstalled` checks a game folder
that needs no installer. Each run uses a fresh app and preference domain.

For an interactive disc check, use `iso /absolute/path/to/game.iso` as arguments
three and four. The source is mounted read-only and output stays under
`build/Import-LABEL/Games`. The current guest screen is saved as `installer.png`.
Append strings to `commands.json` in that test folder to send guest-only input:
`enter`, `escape`, `up`, `down`, or literal text. After the installer exits,
`finish` finalizes the import. ISO checks time out after three minutes; generated
fixture checks after forty seconds. The helper does not install Windows or make
Windows-only installer media importable.

`./Tests/run-windows-program-check.sh APP LABEL` checks the Windows program
selector in an isolated Congo copy. It covers the compiled menu, ISO and
hard-disk discovery, named Program Manager shortcuts, quoted arguments, working
folders, Cancel, saved launchers, repeated selection, stale prior arguments and
normal app exit. A test hook verifies the DOS working folder before WIN.COM runs.
`WindowsGroupParserTests.m` also checks real group records and malformed input.
The second process captures startup at 18, 60
and 120 seconds, allowing first-run WinG calibration to finish. See
[`WINDOWS-PROGRAM-SELECTOR.md`](../WINDOWS-PROGRAM-SELECTOR.md).

Build with `./build-release.sh`. The tests launch separate, ad-hoc signed app
copies under `build/` with independent preference domains. The game probe gives
every gamebox copy a fresh identifier, so it cannot open the original save-state
overlay. Do not play or close the test windows during a probe.

`./Tests/run-renderer-tests.sh path/to/Boxer.app` loads `RendererSmoke.m` into a
copy of that app and exercises the actual compiled Metal renderer. It checks
unchanged frames, dirty-row coalescing and pixel contents, GPU backpressure,
temporal CRT animation, pause, shader controls, occlusion, exposure, resizing,
and clearing/replacing the source. It needs a visible macOS desktop and Metal.
It also exercises the compiled Graphics Processor menu: Discrete GPU and
Integrated Intel GPU labels, the discrete default, saved selection, checkmarks,
and rendering on both built-in GPUs when available. Simulated device inventories
check that both choices are disabled on Apple Silicon, Intel-only, discrete-only,
external-GPU-only alternatives, and missing-device configurations, and that
disabled actions cannot overwrite the saved choice. Switching applies to new
game windows; an existing renderer retains its device. These checks do not
measure mouse latency or replace testing on physical Apple Silicon hardware.

`./Tests/run-mouse-queue-probe.sh APP LABEL [fixed|max] [large|small]` runs a
brief SimTower input diagnostic in separate app/game copies. The defaults are
fixed 25,000 cycles and a 1046×835 view; small uses 640×480. Both use AMD/performance
graphics and Original rendering. The game starts for 18 seconds, then a worker
posts 500 markers about 8 ms apart through the production AppKit event pump.
At dispatch, a test hook routes relative movement to the real input controller.
It does not bypass the queue by calling the emulated mouse directly. A marker
is necessary because AppKit discards fabricated mouse events without the
WindowServer's tracking metadata. Real hardware delivery/coalescing is not tested.

The probe records queue delay, changed-frame gaps, and submission gaps. The
current probe waits for asynchronous activation before capturing the mouse and
also verifies that a timer resumes a paused emulation loop. The
steady queue summary excludes the first 64 markers to separate initial resize
work from ongoing movement. Raw ordered queue samples and logs stay in `build/`.
These are diagnostics, not an end-to-end latency measurement: changed frames
can include animation, GPU submission is not presentation, and the guest PS/2
callback is not timestamped. Do not interact with the test window when collecting
comparisons. Interactive feedback should be recorded separately.

`./Tests/run-window-close-check.sh APP LABEL [game|companion]` checks normal app
termination using a copied SimTower and isolated preferences. It cancels the
first close prompt, verifies that the game remains running, then accepts the
second close. `game` requires the app process to exit; `companion` keeps another
window open, checks that the process stays alive, then closes the final window.
Both check emulator cancellation and saved session settings. Success requires
natural AppKit termination; only a failure or timeout forcibly exits the test.
The confirmed-smooth baseline reproduces the old behavior by staying open after
its final window closes. These are short lifecycle checks, not benchmarks.

Prepare Duke once with:

```sh
python3 Tests/prepare-duke-fixture.py '/path/to/Duke.boxer' --config '/path/to/current/DUKE3D.CFG'
```

The optional `--config` matches the settings in the game's current save-state
overlay. Include the complete gamebox: Atomic Edition checks for its CD.
Then run probes sequentially, with no builds running in the background:

```sh
./Tests/run-game-probe.sh path/to/Boxer.app unique-label 75 1
./Tests/run-game-probe.sh path/to/Boxer.app another-label 50 0
./Tests/run-game-probe.sh path/to/Boxer.app restore-check 0 2
```

The third argument is the automatic CPU budget (0 leaves the configured value).
The fourth enables policy tests: 1 exercises serialization, menu state,
fixed/automatic transitions, turbo, limits and saving during gameplay; 2 tests
loading saved settings over a fixed-speed configuration and saving after the
emulator stops. Mode 2 exits before gameplay.

Normal probes require Duke to enter and remain in graphics mode, capture a
frame, and record process CPU time and actual emulated cycles for 44 seconds.
New builds also record submitted frames and upload bytes. Logs and captures
are written under `build/`. Use a new label on each run. CPU percentages are
process CPU time divided by wall time (100% is one core), not fan speed or total
machine power. Compare the same demo phase; startup/title screens differ in
workload. Check audio and controls interactively before treating this as a
complete play-through test.

## Second-pass checks

`./Tests/run-round2-checks.sh STAGE APP RUN-ID [COMPARISON-APP]` runs isolated
stages sequentially. Use a fresh run ID. Available stages:

- `acceptance`: renderer, smoke, limits, shaders and compatibility in sequence.

- `renderer`: performance/energy-saving GPU selection, normal/Retro/Retro Light rendering,
  dirty rows, pause, visibility, resize and GPU completion errors.
- `smoke`: speed-limit menu presets, capturing current speed, immediate clamping,
  persisted settings, fixed/automatic/turbo transitions, pause/resume, and reload.
- `limits`: 90-second Duke runs with 75k, 100k and 150k automatic ceilings.
  Also compares Balanced (75%) with a 100k ceiling against Quiet.
- `shaders`: 90-second Retro and Retro Light runs at the same fixed 100k speed.
- `compiler`: 180 seconds each for two otherwise-identical apps at fixed 100k speed;
  pass the ThinLTO app as argument four.
- `sustained`: 600 seconds each for `build/Boxer-Before-Round2.app` and the candidate.
  The candidate uses Quiet with a 100k ceiling; the reference uses Quiet alone.
  Optional arguments four and five override the candidate budget and ceiling.
- `compatibility`: bundled Underworld and Epic Pinball demos using the normal
  CPU core. Pinball's launcher hands off to the separate `EP1` table program.

The game probe accepts `BOXER_TEST_SECONDS`, `BOXER_TEST_LIMIT`, `BOXER_TEST_FIXED`,
`BOXER_TEST_STYLE` (0 original, 1 smoothed, 2 Retro, 3 Retro Light) and
`BOXER_TEST_HIGH_GPU=YES`. The timing-restoration build pumps input on each main
emulation tick and uses the original runtime sleep selection. The earlier
`BOXER_LEGACY_SCHEDULER` diagnostic switch applies only to the older second-pass
and GPU-menu builds; the current source no longer reads it. Extra DOS idle-loop
polls retain their original 200 Hz limiter.

Logs include GPU device, completed submissions, cumulative GPU execution time,
drawable wait time, host event pumps and process context switches. A test-only
SDL observer records queued audio bytes, samples of empty queues, and non-silent
PCM, queue depth and the device's playback status. It leaves the audio data
unchanged. Empty-queue samples are a diagnostic,
not a precise count of audible glitches; startup and deliberate pauses can empty
the queue. Listening and playing remain necessary to evaluate audio and controls.

Use `python3 Tests/summarize-performance.py build/probe-LABEL.log ...` to summarize
logs after 20 seconds of warmup. GPU timing is execution time, not power. These
measurements do not establish fan RPM or temperature changes.

`./Tests/run-windows-installer-check.sh APP LABEL WINDOWS_GAMEBOX ISO [DOS_PROGRAM]`
copies an existing Windows gamebox's C drive/configuration into a disposable
gamebox with a new identity, adds the supplied ISO as D, and tests the existing
Windows chooser and fresh-process launch. The default program is `D:\SETUP.EXE`.
It captures `build/Windows-LABEL/guest.png` once per second. Append guest keyboard
commands to that folder's `commands.json` array: `enter`, `escape`, `tab`, arrow
names, ordinary text, or `close`. It has a five-minute safety timeout. Dispatch
checks alone do not prove installation or gameplay; inspect screenshots and
installed files. Guest writes use Boxer's shadow state under the new test UUID.
See `WINDOWS-IMPORT-AL-UNSER-2026-10-18.md` for the real-disc results.

`./Tests/run-import-check.sh APP LABEL windows ISO WINDOWS_GAMEBOX` exercises
the fallback importer, disabling the automatic runtime source for the test
and using a disposable gamebox template with saved-file/deletion
markers. It tests runtime-panel cancellation, missing-runtime recovery, hidden
files, independent identity, and cancellation in the final startup chooser.
For the Al Unser fixture, the `finish` command selects the installed game and
completes import. The five-minute timeout bounds this interactive installation
check. `windows-scan` tests Windows-only detection and mixed-media DOS priority
without requiring Windows or game data. See `WINDOWS-IMPORT-FIX-2026-10-18.md`.

`./Tests/run-import-check.sh APP LABEL windows-auto ISO` exercises the default
Windows import with a runtime supplied for the test build. It checks that no runtime
chooser appears, verifies copied Windows/driver files, and uses the same Al Unser
installation and finish-program selection checks. DOS modes also verify that
Windows is not copied into DOS gameboxes.

Windows import tests require a legally obtained copy of Windows 3.x supplied
by the person building and testing the app.

Do not edit a running shell script, run simultaneous game probes, or compile
while collecting comparison measurements. Disposable apps/gameboxes and logs
stay under the ignored `build/` directory.

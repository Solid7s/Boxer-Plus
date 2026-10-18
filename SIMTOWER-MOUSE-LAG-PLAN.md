# SimTower mouse lag: review and proposed fix

Initial review, 2026-10-17. The user clarified that the newer build feels laggy when
moving the mouse in SimTower. This document is a plan, not an implemented fix.
No app, production code, game configuration, or preferences were changed during
the initial review. Subsequent checks and the configuration comparison are
recorded at the end of this document.

## Baseline and limits of the comparison

The installed, restored app is the first performance-pass Release build:
`5bd0e7ac316e318579684d83c7a11462ec09530257ad3789cedda0a79768fd0b`.
The newer saved build is:
`a7e62c7934e40d490d0c0ac2d07e3937d0c56923a2ab72d7abf13140c05cb56e`.

The project working tree contains the newer source. Git HEAD predates both
performance passes, so the entire working-tree diff is NOT the difference
between these two apps. The first-pass notes and retained binary symbols confirm
that the restored app already has the pending-pixel/dirty-row renderer. That
renderer must not be incorrectly classified as entirely new in the second pass.
There is no separately verified exact source snapshot for the restored app.

## Findings, ranked for this symptom

| Priority | Change or interaction | Evidence and implication |
| --- | --- | --- |
| 1 | Main emulation loop now polls AppKit through a 200 Hz limiter | `Boxer/BXCoalface.h:26` remaps `GFX_Events` to `boxer_MaybeProcessEvents`; `Boxer/BXCoalface.mm:39` imposes a 5 ms minimum between polls. Previously that entry point pumped directly. This is a clear new opportunity for input delay, not proof of the reported lag. |
| 2 | Default GPU changed from the system default to the integrated GPU | `Boxer/Metal Rendering/BXMetalRenderingView.m:71` prefers `isLowPower`. The earlier system-default choice selected the AMD Radeon Pro 5500M; newer tests selected Intel UHD 630. The saved preference currently selects Energy Saving. This can change cursor-frame delivery even if guest mouse input works. |
| 3 | Scheduler now always uses ordinary sleep unless the legacy diagnostic is enabled | `DOSBox-Staging/src/dosbox.cpp:388` bypasses the previous runtime choice of `DelayPrecise`. `include/timer.h:86` uses `sleep_for`; the precise helper uses short sleeps and yields. Sleep overruns could affect event processing and guest timing; their actual extent has not been measured in SimTower. |
| 4 | Deferred drawing and GPU completion share the main thread with event processing | `BXMetalRenderingView.m:239` acquires a drawable and submits rendering; completion schedules work back to the main queue. The new polling schedule/GPU may interact with this existing design. Investigate only after separating the first three changes. |

The mouse route is AppKit event dispatch → `BXInputController.mouseMoved:` →
`BXEmulatedMouse.movedTo:by:onCanvas:whileLocked:` → DOSBox's mouse/PS2 callback
→ Windows updates its cursor image → the renderer presents the changed frame.
SimTower's bundled Windows configuration uses its PS/2 mouse driver.
The DOSBox mouse code already has a 5 ms guest event limiter and merges repeated
pending motion events (`src/ints/mouse.cpp:196–226`). That code was not changed.
Host-side batching can interact with it, but two 5 ms intervals do not establish
a measured total latency or explain severe lag by themselves.

Ordinary sleep and long main-thread work also merit scrutiny because
`increaseticks()` caps a catch-up batch at 20 ms after advancing `ticksLast`
(`src/dosbox.cpp:241–249`). A sufficiently long stall can therefore affect guest
progress, not only how often the host draws. No such stall has yet been proven
in the reported SimTower session.

### Lower-priority explanations

- SimTower's portable configuration remains `cycles=fixed 25000`. Its stored
  automatic budget is currently 75%, with an unlimited automatic ceiling. That
  automatic budget should not affect fixed mode; verify the live mode during
  future reproduction rather than increasing its speed to mask a regression.
- Rendering is Original (`renderingStyle=0`), so Retro Light is not executing.
- The saved newer build uses ordinary Release optimization, not ThinLTO. Both
  compared releases use the first-pass compiler optimization.
- Mouse sensitivity/motion conversion, Windows mouse driver, and the DOSBox
  mouse event frequency were not changed by the performance passes.
- Successful capture after reopening only established that locking and clicks
  worked in that session. It did not establish that movement was responsive or
  prove that the remaining lag was a focus problem.

## Why the earlier tests missed this

The performance probes counted GPU submissions and sampled CPU/GPU usage over
seconds. Average submissions per second are neither game simulation speed nor
the delay from an input event to an image appearing on the display.

`Tests/MouseCaptureSmoke.m:81` called the emulated mouse directly for its motion
step. Its clicks used `NSApp sendEvent:` directly as well. Those checks exercised
capture/button behavior but bypassed normal host event-queue waiting. They do
not test the new polling limiter's effect on real mouse movement. Screenshots
taken a second later cannot establish low input latency.

The isolated SimTower checks used a 640×480 view; the actual observed game
window used a 1046×783 input view. Future comparisons must use the same window,
actual backing-pixel size, display/refresh rate, rendering style, and game state.
The existing Duke shader results are not evidence about SimTower input latency.

## Proposed sequence

### 1. Preserve reproducible versions before implementation

Keep the restored app as the reference and the newer app as the regression
candidate. Save the complete current source state, root and submodule changes,
build settings, dependency revisions, and an app checksum before any fixes.
Exclude games, ROMs, test fixtures, and unrelated personal settings. Any
reconstructed earlier source must be labelled as reconstructed until validated;
do not claim it is the missing exact source snapshot.

### 2. Isolate the cause with brief interactive comparisons

Use a copied SimTower game/overlay at fixed 25,000 cycles and Original rendering.
Reproduce slow sweeps, quick direction changes, dragging, and clicking after
switching back from another app. Start with the real window size and keep power
source, display, and mouse settings consistent. Compare the following, stopping
the search when a reproducible difference identifies the relevant subsystem:

| App/variant | GPU | Scheduling |
| --- | --- | --- |
| Restored app | Previous system-default choice | Previous behavior |
| Newer app, unchanged | Integrated | New behavior |
| Newer app, graphics comparison | System default, using its existing High Performance option | New behavior |
| Newer app, scheduling comparison | Integrated | `BOXER_LEGACY_SCHEDULER=1` |
| Newer app, combined comparison if needed | System default | Legacy diagnostic |

These are proposed short input checks, not a new sustained benchmark campaign.
The legacy switch changes BOTH sleep selection and polling, so a successful
legacy comparison cannot identify which of them caused the problem. If it
helps, split those controls in a diagnostic build and compare them independently.
Verify the actual selected GPU rather than relying only on its menu label.

### 3. Apply the smallest confirmed correction

- **If polling is responsible:** restore the earlier polling behavior for the
  active session first. Then evaluate bounded, faster handling while the mouse
  is captured, preserving correct pause/resume, focus, and shutdown behavior.
  Idle savings must not defer active mouse input. Preserve motion deltas and
  button ordering; do not blindly discard old events.
- **If sleep selection is responsible:** restore the previous runtime timing
  choice. Consider a measured deadline-based sleep strategy only afterward;
  changing all delays to busy waits would undo the energy goal.
- **If GPU selection is responsible:** restore the system-default GPU as the
  default and retain Energy Saving as an explicit option. Do not force AMD on
  single-GPU machines or assume live GPU switching is safe.
- **If rendering still delays the cursor:** trace drawable acquisition,
  completion-to-retry delay, and changed cursor rows. Keep dirty-row accumulation
  and safe texture ownership. There is also a shared edge case worth testing:
  when `nextDrawable` returns nil, the code releases the semaphore without
  scheduling its own retry; a static game may need a bounded retry on recovery.
  This is a code risk, not a demonstrated cause of this report.

Do not change SimTower's Windows driver, introduce a cosmetic host cursor, raise
fixed cycles, or remove all first-pass improvements without causal evidence.

### 4. Validate responsiveness, then efficiency

Instrument event timestamp → dispatch → guest mouse callback → changed cursor
frame → presentation, using a consistent monotonic timebase. Record median and
95th/99th percentile delays plus long gaps during continuous movement. Feed
motion through the host event queue instead of calling the emulator directly.
Use real presentation timing where available; label event-to-submit measurements
as proxies, since GPU completion is not proof the screen has updated. Keep logs
buffered so instrumentation does not create the stalls being measured.

Compare against the restored app using equivalent input and confirm that cursor
movement feels equally responsive to the user. Check correct click/drag behavior,
focus recovery, and no lost movement or audio disruption. Regression checks
should cover a DOS mouse game such as Duke and another available Windows game.
Only after responsiveness matches should CPU usage, idle rendering savings, and
GPU cost decide which optimizations to retain. No unmeasured percentage speedup
or fan/temperature improvement should be claimed.

### 5. Package the verified result

Save source and compiled app together with a manifest linking the exact source,
dependencies, settings, tests, and executable checksum. Preserve the restored
reference app. Implementation and replacing the installed app are outside this
planning-only review.

## Follow-up: smoother movement in a resized test window

After the explicit GPU-menu release, the user reported that changing GPU and
using unlimited CPU at 100% did not fix the stutter. During an isolated SimTower
check, the user then reported that their **own mouse movement** became smoother
in the enlarged test window. They confirmed this was not just observing an
automatic mouse sweep. At that point no production code had been changed.

That test copy used the current GPU-menu executable, fixed 25,000 cycles,
normal CPU core, AMD graphics, Original rendering, a fresh game identifier and
preference domain, and a view resized to 1046×835. The ordinary game at this point
had `cycles=max`, a 100% automatic budget with no ceiling, Intel selected for
the next window, and a saved 1046×783 frame. Several variables differ, including
the absence of the ordinary game's saved overlay in the test copy. This report
does not isolate resizing, CPU mode, GPU, focus, or saved state as the cause.

### Brief queued-input checks

`Tests/MouseQueueProbe.m` and `Tests/run-mouse-queue-probe.sh` now measure worker
marker → AppKit queue → dispatch → real input controller. The input controller
then executes its unchanged relative-mouse path. Synthetic markers are necessary
because fabricated mouse events lack WindowServer tracking metadata. This is a
queue diagnostic, not a test of hardware delivery or complete input-to-screen
latency. It also records changed guest frame and GPU submission intervals.

Early probe attempts `current-r1` through `current-r3` did not deliver generated
movement and must not be used as timing evidence. This was a test-routing error.
The user could still move the real mouse in those windows. `current-r4` delivered
all 500 generated movements, but still overlapped game startup. Later probes wait
18 seconds before the movement sequence. No sustained benchmark was resumed.

| Probe | CPU / view | Steady queue delay p95 / p99 | Submission gap p95 / p99 |
| --- | --- | --- | --- |
| `max-large-r6` | Unlimited / 1046×835 | 5.44 / 6.08 ms | 22.92 / 26.71 ms |
| `max-small-r7` | Unlimited / 640×480 | 5.23 / 5.59 ms | 22.61 / 27.52 ms |

Both runs delivered all 500 markers and all 500 relative motions. The steady
queue summary excludes the first 64 markers (about half a second). Initial
large-window resizing caused a transient queue backlog; including that startup
backlog would falsely describe ongoing motion. Fixed-speed large-window run
`fixed-large-r5` also delivered all 500 movements, but predates the raw-sample
and separate steady-summary additions. These spot checks did not reproduce a
large ongoing queue-delay difference between window sizes or prove a scheduler
regression. No scheduler rollback was applied.

### Regular-game comparison setup

The ordinary SimTower configuration and relevant GPU/window/game preferences
were backed up to `build/Backups/SimTower-before-mouse-setup-20261017/`.
Its CPU configuration was restored to `cycles=fixed 25000` (normal core), AMD
was selected, and a 1046×835 frame was saved at an on-screen position. SimTower
was then opened normally in `/Applications/Boxer+.app`, without an injected
library, automatic movement, or automatic exit. The user's 100% automatic
budget and unlimited ceiling remain saved but do not control fixed mode.
Game files and saved-game overlays were not edited.

The user then reported that the regular game was **still stuttery** with this
setup. This comparison did not fix the issue and must not be presented as a
solution. `Examples/SimTower-Fixed-Speed.conf` records only the compared CPU
settings. The user's original settings remain backed up.

### Timing restoration candidate

Following the unsuccessful settings comparison, the main `GFX_Events` entry
point was restored to direct `boxer_processEvents` calls. Only additional polls
from DOS idle callbacks retain the pre-existing 200 Hz limiter. The core now
again chooses `DelayPrecise` or `Delay` using its original runtime check, instead
of always using ordinary sleep. The build helper reverses the retired energy
patch on existing trees and accepts already-correct fresh submodules.

The GPU menu, compiler optimizations, renderer improvements, automatic CPU
budget/ceiling controls, and Retro Light remain. The corrected cancellation
return value and borrowed emulator reference are also retained. The diagnostic
`BOXER_LEGACY_SCHEDULER` override is removed: the release itself now uses the
restored timing paths. This is a targeted rollback of the two suspect timing
changes, not proof that either individually caused the user's stutter.

The Release build succeeded. In the small-window unlimited-CPU comparison,
`restored-small-r9` delivered all 500 queued motions and passed pause/resume:

| Build | Steady queue median / p95 / p99 | Submission gap p95 / p99 |
| --- | --- | --- |
| GPU-menu build (`max-small-r7`) | 2.73 / 5.23 / 5.59 ms | 22.61 / 27.52 ms |
| Restored timing (`restored-small-r9`) | 0.54 / 1.20 / 1.88 ms | 17.66 / 18.17 ms |

These are short spot checks, with both timing changes applied together, not a
hardware-to-display latency measurement or a sustained benchmark. The earlier
`restored-small-r8` attempt failed capture because activation was not complete;
its partial-motion data is not acceptance evidence. The probe now waits for
activation before locking and fails explicitly if it cannot capture. The
existing `mouse-input-timing-r1` check also passed capture, button press, and
release on the new build.

The user independently reported that their own movement was definitely smoother
in the small test window while the timing-restoration build was running. Window
size and timing both differ from the previous regular-game setup, so this does
not isolate which change explains the perceived improvement. After installation,
the user confirmed that their regular SimTower session was "beautifully smooth"
in the smaller window.

The app, matching source snapshot, validation logs, and checksums are preserved
under `build/Saved-Releases/2026-10-17-input-timing/`. Installation status and
the preceding app backup are recorded in that folder's `BUILD-INFO.json`.
No new renderer or mouse-coordinate-conversion changes were made. The original
restored app and the preceding GPU-menu release remain available as references.

### Confirmed baseline — 2026-10-17

The confirmed build and matching source are saved separately in
`build/Saved-Releases/2026-10-17-confirmed-smooth/` at the user's request. The
installed executable matches the saved release checksum. SimTower is using a
640×480 window and AMD graphics; its original `cycles=max`, 100% automatic
CPU budget, and unlimited automatic ceiling were restored before the successful
regular-game check. The temporary fixed-25,000 comparison is not the accepted
configuration. Preserve this app/source pair before future performance changes.

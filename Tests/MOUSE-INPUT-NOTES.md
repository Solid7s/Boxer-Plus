# SimTower mouse investigation — 2026-10-17

The user reported that clicking SimTower no longer captured the mouse after
installing the performance build, although the original Boxer+ worked.
No production input or emulation code has been changed during this investigation.

An eleven-second functional check with independent copies of SimTower and Boxer
passed on both the installed performance build (`mouse-current-r2.log`) and the
original app backup from 16:58 (`mouse-original-r1.log`). The check exercises
click-to-capture through the real window responder chain, button press/release,
and guest cursor movement. It does not measure performance. The initial r1 check
incorrectly toggled an already captured mouse; its failure is a test setup error,
not evidence of an emulator regression.

The real installed app was subsequently reopened with `MouseInputObserver.m`
loaded as a temporary diagnostic library. Its app bundle and game preferences
were not modified. In the user's normal 1046×783 game window, clicks reached
Boxer and `CGAssociateMouseAndMouseCursorPosition(false)` returned success (0).
The app reported active mouse support and successful locking. Other clicks
arrived while the app was inactive and its window was not key, when Boxer's
existing `canLockMouse` guard disallows capture. These observations suggest a
focus/startup issue but do not establish the cause of the user's original report.

Raw diagnostics and window images are under ignored `build/`. The passive
observer records mouse-button/window-focus and capture-call results, not keyboard
input. It is not linked into the release and is removed by quitting Boxer and
reopening it normally.

The user confirmed that mouse movement and clicking work in the reopened real
SimTower session. Keep the current installed build; no production code change
was needed to restore input in this session. The cause of the initial failure
remains unconfirmed, so this is a successful recovery after reopening, not a
verified code fix. The diagnostic session can end when the user quits Boxer
normally, without interrupting their game.

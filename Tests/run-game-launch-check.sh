#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Users/sung/Downloads/Xcode.app/Contents/Developer}"
source_app="$1"
label="$2"
program="$3"
[[ "$label" =~ ^[a-z0-9-]+$ ]] || exit 1
test_root="$PWD/build/Game-$label"
test ! -e "$test_root"
test -f "$program"
mkdir -p "$test_root"
ditto "$source_app" "$test_root/Boxer.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier net.washboardabs.boxer.game-$label" "$test_root/Boxer.app/Contents/Info.plist"
codesign --force --deep --sign - "$test_root/Boxer.app"
xcrun clang -fobjc-arc -fmodules -dynamiclib -framework Cocoa -framework MetalKit \
    -I Boxer -I 'Boxer/DOS window' -I Boxer/Rendering -I DOSBox-Staging/include \
    -I 'Other Sources/ADBToolkit' -I 'Other Sources/ADBToolkit/Fullscreen' \
    Tests/GameLaunchSmoke.m -o "$test_root/GameLaunchSmoke.dylib"
BOXER_LAUNCH_ROOT="$test_root" BOXER_LAUNCH_PROGRAM="$program" DYLD_INSERT_LIBRARIES="$test_root/GameLaunchSmoke.dylib" \
    "$test_root/Boxer.app/Contents/MacOS/Boxer" -ApplePersistenceIgnoreState YES -SUEnableAutomaticChecks NO \
    -suppressCloseAlert YES -pauseWhileInactive NO -startupAction 0 > "$test_root/results.log" 2>&1
rg '^PASS:|^FAIL:' "$test_root/results.log"
printf 'PASS: game test process exited successfully\n'

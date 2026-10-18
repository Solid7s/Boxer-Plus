#!/bin/bash
# Eleven-second functional input check, with isolated app and game copies.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Users/sung/Downloads/Xcode.app/Contents/Developer}"
source_app="$1"
label="$2"
[[ "$label" =~ ^[a-z0-9-]+$ ]] || exit 1
test_app="$PWD/build/Boxer-Mouse-$label.app"
test_game="$PWD/build/SimTower-Mouse-$label.boxer"
test ! -e "$test_app"
test ! -e "$test_game"
ditto "$source_app" "$test_app"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier net.washboardabs.boxer.mouse-$label" "$test_app/Contents/Info.plist"
codesign --force --deep --sign - "$test_app"
ditto '/Users/sung/DOS Games/SimTower.boxer' "$test_game"
python3 - "$test_game" <<'PY'
import pathlib, plistlib, sys, uuid
path = pathlib.Path(sys.argv[1]) / 'Game Info.plist'
info = plistlib.loads(path.read_bytes())
info['BXGameIdentifier'] = str(uuid.uuid4()).upper()
path.write_bytes(plistlib.dumps(info))
PY
xcrun clang -fobjc-arc -fmodules -dynamiclib -framework Cocoa -framework MetalKit \
    -I Boxer -I 'Boxer/DOS window' -I Boxer/Rendering \
    -I 'Other Sources/ADBToolkit' -I 'Other Sources/ADBToolkit/Fullscreen' \
    Tests/MouseCaptureSmoke.m -o build/MouseCaptureSmoke.dylib
BOXER_TEST_GAME="$test_game" BOXER_MOUSE_CAPTURE="$PWD/build/mouse-$label" \
    DYLD_INSERT_LIBRARIES="$PWD/build/MouseCaptureSmoke.dylib" \
    "$test_app/Contents/MacOS/Boxer" -ApplePersistenceIgnoreState YES -SUEnableAutomaticChecks NO -pauseWhileInactive NO \
    > "build/mouse-$label.log" 2>&1

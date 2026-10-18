#!/bin/bash
# Check actual process exit after window close; all data/preferences are isolated.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Users/sung/Downloads/Xcode.app/Contents/Developer}"
source_app="$1"
label="$2"
mode="${3:-game}"
[[ "$label" =~ ^[a-z0-9-]+$ ]] || exit 1
[[ "$mode" == game || "$mode" == companion ]] || exit 1
test_app="$PWD/build/Boxer-Close-$label.app"
test_game="$PWD/build/SimTower-Close-$label.boxer"
test ! -e "$test_app"
test ! -e "$test_game"
ditto "$source_app" "$test_app"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier net.washboardabs.boxer.close-$label" "$test_app/Contents/Info.plist"
codesign --force --deep --sign - "$test_app"
ditto '/Users/sung/DOS Games/SimTower.boxer' "$test_game"
python3 - "$test_game" <<'PY'
import pathlib, plistlib, re, sys, uuid
game = pathlib.Path(sys.argv[1])
path = game / 'Game Info.plist'
info = plistlib.loads(path.read_bytes())
info['BXGameIdentifier'] = str(uuid.uuid4()).upper()
path.write_bytes(plistlib.dumps(info))
config = game / 'DOSBox Preferences.conf'
config.write_text(re.sub(r'^cycles=.*$', 'cycles=fixed 25000', config.read_text(), flags=re.M))
PY
xcrun clang -fobjc-arc -fmodules -dynamiclib -framework Cocoa -framework MetalKit \
    -I Boxer -I 'Boxer/DOS window' -I Boxer/Rendering \
    -I 'Other Sources/ADBToolkit' -I 'Other Sources/ADBToolkit/Fullscreen' \
    Tests/WindowCloseSmoke.m -o build/WindowCloseSmoke.dylib
BOXER_TEST_GAME="$test_game" BOXER_CLOSE_MODE="$mode" DYLD_INSERT_LIBRARIES="$PWD/build/WindowCloseSmoke.dylib" \
    "$test_app/Contents/MacOS/Boxer" -ApplePersistenceIgnoreState YES -SUEnableAutomaticChecks NO \
    -pauseWhileInactive NO -suppressCloseAlert NO -startupAction 0 \
    > "build/window-close-$label.log" 2>&1
rg '^PASS:|^FAIL:|^Accepting' "build/window-close-$label.log"
rg -q '^PASS: normal app termination' "build/window-close-$label.log"
printf 'PASS: Boxer process exited normally\n'

#!/bin/bash
# Brief input timing check; never use the original app/game or preference domain.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Users/sung/Downloads/Xcode.app/Contents/Developer}"
source_app="$1"
label="$2"
cycles="${3:-fixed}"
window_size="${4:-large}"
[[ "$cycles" == fixed || "$cycles" == max ]] || exit 1
[[ "$window_size" == large || "$window_size" == small ]] || exit 1
[[ "$label" =~ ^[a-z0-9-]+$ ]] || exit 1
test_app="$PWD/build/Boxer-Queue-$label.app"
test_game="$PWD/build/SimTower-Queue-$label.boxer"
test ! -e "$test_app"
test ! -e "$test_game"
ditto "$source_app" "$test_app"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier net.washboardabs.boxer.queue-$label" "$test_app/Contents/Info.plist"
codesign --force --deep --sign - "$test_app"
ditto '/Users/sung/DOS Games/SimTower.boxer' "$test_game"
python3 - "$test_game" "$cycles" <<'PY'
import pathlib, plistlib, re, sys, uuid
game = pathlib.Path(sys.argv[1])
path = game / 'Game Info.plist'
info = plistlib.loads(path.read_bytes())
info['BXGameIdentifier'] = str(uuid.uuid4()).upper()
path.write_bytes(plistlib.dumps(info))
config = game / 'DOSBox Preferences.conf'
cycles = 'fixed 25000' if sys.argv[2] == 'fixed' else 'max'
config.write_text(re.sub(r'^cycles=.*$', 'cycles='+cycles, config.read_text(), flags=re.M))
PY
xcrun clang -fobjc-arc -fmodules -dynamiclib -framework Cocoa -framework MetalKit -framework QuartzCore \
    -I Boxer -I 'Boxer/DOS window' -I Boxer/Rendering \
    -I 'Other Sources/ADBToolkit' -I 'Other Sources/ADBToolkit/Fullscreen' \
    Tests/MouseQueueProbe.m -o build/MouseQueueProbe.dylib
BOXER_TEST_GAME="$test_game" BOXER_QUEUE_WINDOW="$window_size" \
    BOXER_QUEUE_SAMPLES="$PWD/build/mouse-queue-$label.json" DYLD_INSERT_LIBRARIES="$PWD/build/MouseQueueProbe.dylib" \
    "$test_app/Contents/MacOS/Boxer" -ApplePersistenceIgnoreState YES -SUEnableAutomaticChecks NO \
    -pauseWhileInactive NO -useHighPerformanceGPU YES -renderingStyle 0 \
    > "build/mouse-queue-$label.log" 2>&1
rg 'START |QUEUE_TO_INPUT|CHANGED_FRAME_GAPS|SUBMIT_GAPS|RESULT |PASS:|FAIL:' "build/mouse-queue-$label.log"

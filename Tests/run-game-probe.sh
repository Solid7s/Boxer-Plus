#!/bin/bash
# Run a Duke attract-mode probe using copied game data and a new ID.
# BOXER_TEST_SECONDS optionally extends the default 44-second run.
# Arguments: app, label, budget (0 keeps conf), policy-test (0/1).
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Users/sung/Downloads/Xcode.app/Contents/Developer}"
source_app="$1"
label="$2"
[[ "$label" =~ ^[a-z0-9-]+$ ]] || exit 1
test_app="$PWD/build/Boxer-Probe-$label.app"
test_game="$PWD/build/Duke-$label.boxer"
mkdir -p build
ditto "$source_app" "$test_app"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier net.washboardabs.boxer.probe-$label" "$test_app/Contents/Info.plist"
codesign --force --deep --sign - "$test_app"
python3 - "$test_game" <<'PY'
import os, pathlib, plistlib, shutil, sys, uuid
target = pathlib.Path(sys.argv[1])
source = pathlib.Path(os.environ.get('BOXER_TEST_SOURCE', 'build/Duke Benchmark.boxer'))
if target.exists():
    raise SystemExit('Use a fresh probe label to keep runs independent.')
shutil.copytree(source, target)
info_path = target / 'Game Info.plist'
info = plistlib.loads(info_path.read_bytes())
info['BXGameIdentifier'] = str(uuid.uuid4()).upper()
info_path.write_bytes(plistlib.dumps(info))
if os.environ.get('BOXER_TEST_CORE'):
    conf = target / 'DOSBox Preferences.conf'
    with conf.open('a') as output:
        output.write('\n[cpu]\ncore=' + os.environ['BOXER_TEST_CORE'] + '\ncycles=fixed 10000\n')
PY
xcrun clang -fobjc-arc -fmodules -dynamiclib -framework Cocoa -framework MetalKit \
    -F Frameworks -framework SDL2 \
    -I Boxer -I 'Boxer/DOS window' -I Boxer/Rendering \
    -I 'Other Sources/ADBToolkit' -I 'Other Sources/ADBToolkit/Fullscreen' \
    Tests/GamePerformance.m -o build/GamePerformance.dylib
BOXER_TEST_GAME="$test_game" BOXER_TEST_BUDGET="${3:-0}" BOXER_TEST_POLICY="${4:-0}" \
    BOXER_TEST_CAPTURE="$PWD/build/$label.png" \
    DYLD_INSERT_LIBRARIES="$PWD/build/GamePerformance.dylib" \
    "$test_app/Contents/MacOS/Boxer" -ApplePersistenceIgnoreState YES -SUEnableAutomaticChecks NO -pauseWhileInactive NO \
    -useHighPerformanceGPU "${BOXER_TEST_HIGH_GPU:-NO}" \
    > "build/probe-$label.log" 2>&1
cat "build/probe-$label.log"

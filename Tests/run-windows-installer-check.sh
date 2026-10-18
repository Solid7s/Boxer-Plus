#!/bin/bash
# Uses a private copy of an existing Windows installation, never the source gamebox.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Users/sung/Downloads/Xcode.app/Contents/Developer}"
source_app="$1"
label="$2"
source_game="$3"
source_iso="$4"
program="${5:-D:\\SETUP.EXE}"
[[ "$label" =~ ^[a-z0-9-]+$ ]] || exit 1
test -f "$source_iso"
test -f "$source_game/C.harddisk/WINDOWS/WIN.COM"
test_root="$PWD/build/Windows-$label"
test ! -e "$test_root"
mkdir -p "$test_root/Test.boxer"
ditto "$source_app" "$test_root/Boxer.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier net.washboardabs.boxer.windows-installer-$label" "$test_root/Boxer.app/Contents/Info.plist"
codesign --force --deep --sign - "$test_root/Boxer.app"
ditto "$source_game/C.harddisk" "$test_root/Test.boxer/C.harddisk"
ditto "$source_iso" "$test_root/Test.boxer/D Disc.iso"
ditto "$source_game/DOSBox Preferences.conf" "$test_root/Test.boxer/DOSBox Preferences.conf"
python3 - "$test_root/Test.boxer" <<'PY'
import pathlib, plistlib, sys, uuid
path = pathlib.Path(sys.argv[1]) / 'Game Info.plist'
path.write_bytes(plistlib.dumps({'BXGameIdentifier': str(uuid.uuid4()).upper(), 'BXGameIdentifierType': 1, 'BXLaunchers': []}))
PY
xcrun clang -fobjc-arc -fmodules -dynamiclib -framework Cocoa -framework MetalKit \
    -I Boxer -I 'Boxer/DOS window' -I Boxer/Rendering -I DOSBox-Staging/include \
    -I 'Other Sources/ADBToolkit' -I 'Other Sources/ADBToolkit/Fullscreen' \
    Tests/WindowsInstallerSmoke.m -o build/WindowsInstallerSmoke.dylib
for phase in choose launch; do
    BOXER_WINDOWS_TEST_ROOT="$test_root" BOXER_WINDOWS_PROGRAM="$program" BOXER_WINDOWS_PHASE="$phase" \
        DYLD_INSERT_LIBRARIES="$PWD/build/WindowsInstallerSmoke.dylib" "$test_root/Boxer.app/Contents/MacOS/Boxer" \
        -ApplePersistenceIgnoreState YES -SUEnableAutomaticChecks NO -pauseWhileInactive NO \
        -suppressCloseAlert YES -startupAction 0 > "$test_root/$phase.log" 2>&1
    rg '^PASS:|^FAIL:' "$test_root/$phase.log"
    rg -q '^PASS: Windows test closes normally$' "$test_root/$phase.log"
done

#!/bin/bash
# Test against a private copy of Congo, never the original game or app preferences.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Users/sung/Downloads/Xcode.app/Contents/Developer}"
source_app="$1"
label="$2"
[[ "$label" =~ ^[a-z0-9-]+$ ]] || exit 1
test_app="$PWD/build/Boxer-Windows-$label.app"
test_game="$PWD/build/Congo-Windows-$label.boxer"
test ! -e "$test_app"
test ! -e "$test_game"
ditto "$source_app" "$test_app"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier net.washboardabs.boxer.windows-$label" "$test_app/Contents/Info.plist"
codesign --force --deep --sign - "$test_app"
ditto '/Users/sung/DOS Games/Congo - Descent into Zinj.boxer' "$test_game"
python3 - "$test_game" <<'PY'
import pathlib, plistlib, struct, sys, uuid
path = pathlib.Path(sys.argv[1]) / 'Game Info.plist'
info = plistlib.loads(path.read_bytes())
info['BXGameIdentifier'] = str(uuid.uuid4()).upper()
info['BXLaunchers'] = []
path.write_bytes(plistlib.dumps(info))
# A small synthetic Program Manager group tests argument preservation without
# changing the real game's shortcuts or installing any new executable.
b = bytearray(60)
b[:4] = b'PMCC'
struct.pack_into('<HH', b, 32, 1, 36)
def string(value):
    offset = len(b)
    b.extend(value.encode('cp1252') + bytes([0]))
    return offset
struct.pack_into('<H', b, 54, string('Reader test'))
struct.pack_into('<H', b, 56, string(r'write.exe "C:\CONGO\README.WRI"'))
struct.pack_into('<H', b, 6, len(b))
b.extend(struct.pack('<HHH4s', 0x8000, 0xffff, 10, b'PMCC'))
folder = b'C:\\CONGO' + bytes([0])
b.extend(struct.pack('<HHH', 0x8101, 0, 6 + len(folder)) + folder)
b.extend(struct.pack('<HHH', 0xffff, 0xffff, 0))
(path.parent / 'C.harddisk/WINDOWS/BXTEST.GRP').write_bytes(b)
PY
xcrun clang -fobjc-arc -fmodules -framework Foundation -I Boxer \
    Boxer/BXWindowsProgramGroup.m Tests/WindowsGroupParserTests.m -o build/WindowsGroupParserTests
./build/WindowsGroupParserTests "$test_game/C.harddisk/WINDOWS/CONGO.GRP"
xcrun clang -fobjc-arc -fmodules -dynamiclib -framework Cocoa -framework MetalKit \
    -I Boxer -I 'Boxer/DOS window' -I Boxer/Rendering \
    -I 'Other Sources/ADBToolkit' -I 'Other Sources/ADBToolkit/Fullscreen' \
    Tests/WindowsProgramSmoke.m -o build/WindowsProgramSmoke.dylib
for phase in choose launch; do
    BOXER_TEST_GAME="$test_game" BOXER_PICKER_PHASE="$phase" DYLD_INSERT_LIBRARIES="$PWD/build/WindowsProgramSmoke.dylib" \
        "$test_app/Contents/MacOS/Boxer" -ApplePersistenceIgnoreState YES -SUEnableAutomaticChecks NO \
        -pauseWhileInactive NO -suppressCloseAlert YES -startupAction 0 \
        > "build/windows-program-$label-$phase.log" 2>&1
    rg '^PASS:|^FAIL:' "build/windows-program-$label-$phase.log"
    rg -q '^PASS: normal window close exits the app' "build/windows-program-$label-$phase.log"
done

#!/bin/bash
# The importer writes only into a fresh generated fixture and preferences domain.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Users/sung/Downloads/Xcode.app/Contents/Developer}"
source_app="$1"
label="$2"
mode="${3:-installer}"
[[ "$label" =~ ^[a-z0-9-]+$ ]] || exit 1
[[ "$mode" == installer || "$mode" == preinstalled || "$mode" == iso || "$mode" == windows || "$mode" == windows-auto || "$mode" == windows-scan ]] || exit 1
iso_path="${4:-}"
if [[ "$mode" == iso || "$mode" == windows || "$mode" == windows-auto ]]; then test -f "$iso_path"; fi
test_root="$PWD/build/Import-$label"
test_app="$test_root/Boxer.app"
test ! -e "$test_root"
mkdir -p "$test_root/Source" "$test_root/Games"
ditto "$source_app" "$test_app"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier net.washboardabs.boxer.import-$label" "$test_app/Contents/Info.plist"
if [[ "$mode" == windows && -d "$test_app/Contents/Resources/Windows311" ]]; then
    # Exercise the fallback using only the disposable app; keep the runtime intact.
    mv "$test_app/Contents/Resources/Windows311" "$test_root/Excluded-Windows311"
fi
if [[ "$mode" == windows-auto ]]; then test -f "$test_app/Contents/Resources/Windows311/WINDOWS/WIN.COM"; fi
codesign --force --deep --sign - "$test_app"
python3 - "$test_root/Source" "$mode" <<'PY'
from pathlib import Path
import struct
import sys
source = Path(sys.argv[1])
game = bytes.fromhex('b8 00 4c cd 21')  # DOS process exit.
if sys.argv[2] == 'windows-scan':
    # Structurally valid Win16 headers exercise the compiled classifier/scanner.
    b = bytearray(1024); b[:2] = b'MZ'
    struct.pack_into('<H', b, 24, 64); struct.pack_into('<I', b, 60, 128); b[128:130] = b'NE'
    (source/'SETUP.EXE').write_bytes(b); (source/'UNINST.EXE').write_bytes(b)
elif sys.argv[2] == 'installer':
    # Small real DOS installer: creates C:\GAME.COM, writes its payload, exits.
    code = bytearray.fromhex('b4 3c 31 c9 ba 00 00 cd 21 89 c3 b4 40 b9 05 00 ba 00 00 cd 21 b4 3e cd 21 b8 00 4c cd 21')
    filename = b'C:\\GAME.COM\0'
    struct.pack_into('<H', code, 5, 0x100 + len(code))
    struct.pack_into('<H', code, 17, 0x100 + len(code) + len(filename))
    (source / 'INSTALL.COM').write_bytes(code + filename + game)
else:
    (source / 'GAME.COM').write_bytes(game)
(source / 'README.TXT').write_text('Disposable Boxer import fixture.\n')
PY
if [[ "$mode" == windows ]]; then
    template="${5:?Provide a Windows gamebox for this test}"
    ditto "$template/C.harddisk" "$test_root/Template.boxer/C.harddisk"
    ditto "$template/DOSBox Preferences.conf" "$test_root/Template.boxer/DOSBox Preferences.conf"
    python3 - "$test_root" <<'PYFIXTURE'
from pathlib import Path
import plistlib, sys, uuid
root = Path(sys.argv[1]); identifier = str(uuid.uuid4()).upper()
(root/'Template.boxer/Game Info.plist').write_bytes(plistlib.dumps({'BXGameIdentifier':identifier, 'BXGameIdentifierType':1}))
state = Path.home()/'Library/Application Support/Boxer/Gamebox States'/identifier/'Current.boxerstate/C.harddisk'
(state/'WINDOWS').mkdir(parents=True)
(state/'WINDOWS/BXIMPORT.TXT').write_text('shadow runtime marker')
(root/'Template.boxer/C.harddisk/DELETE.ME').write_text('base file deleted in shadow')
(state/'DELETE.ME.deleted').touch()
(root/'Template.boxer/C.harddisk/.WINHIDDEN').write_text('hidden runtime data')
(root/'Empty.boxer/C.harddisk').mkdir(parents=True)
(root/'Empty.boxer/Game Info.plist').write_bytes(plistlib.dumps({'BXGameIdentifier':str(uuid.uuid4()).upper(), 'BXGameIdentifierType':1}))
PYFIXTURE
fi
xcrun clang -fobjc-arc -fmodules -dynamiclib -framework Cocoa -framework MetalKit \
    -I Boxer -I 'Boxer/DOS window' -I Boxer/Rendering -I DOSBox-Staging/include \
    -I 'Other Sources/ADBToolkit' -I 'Other Sources/ADBToolkit/Fullscreen' \
    Tests/ImportSmoke.m -o build/ImportSmoke.dylib
BOXER_IMPORT_ROOT="$test_root" BOXER_IMPORT_MODE="$mode" BOXER_IMPORT_ISO="$iso_path" DYLD_INSERT_LIBRARIES="$PWD/build/ImportSmoke.dylib" \
    "$test_app/Contents/MacOS/Boxer" -ApplePersistenceIgnoreState YES -SUEnableAutomaticChecks NO \
    -pauseWhileInactive NO -startupAction 0 > "build/import-$label.log" 2>&1
rg '^PASS:|^FAIL:|^Import progress:' "build/import-$label.log"
rg -q '^PASS: completed import closes normally$' "build/import-$label.log"

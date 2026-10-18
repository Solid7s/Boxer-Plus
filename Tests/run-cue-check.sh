#!/bin/bash
# Synthetic discs contain only generated test programs; no commercial game files.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Users/sung/Downloads/Xcode.app/Contents/Developer}"
source_app="$1"
label="$2"
[[ "$label" =~ ^[a-z0-9-]+$ ]] || exit 1
test_root="$PWD/build/Cue-$label"
test ! -e "$test_root"
mkdir -p "$test_root/Source/TOOLS" "$test_root/Bundled"
python3 - "$test_root" <<'PY'
from pathlib import Path
import struct, sys
root = Path(sys.argv[1]); source = root/'Source'
game = bytes.fromhex('b8 00 4c cd 21')
code = bytearray.fromhex('b4 3c 31 c9 ba 00 00 cd 21 89 c3 b4 40 b9 05 00 ba 00 00 cd 21 b4 3e cd 21 b8 00 4c cd 21')
filename = b'C:\\GAME.COM\0'
struct.pack_into('<H', code, 5, 0x100 + len(code))
struct.pack_into('<H', code, 17, 0x100 + len(code) + len(filename))
(source/'INSTALL.COM').write_bytes(code + filename + game)
(source/'TOOLS/NESTED.COM').write_bytes(game)
b = bytearray(1024); b[:2] = b'MZ'
struct.pack_into('<H', b, 24, 64); struct.pack_into('<I', b, 60, 128); b[128:130] = b'NE'
(source/'SETUP.EXE').write_bytes(b); (source/'UNINST.EXE').write_bytes(b)
PY
hdiutil makehybrid -iso -default-volume-name BOXER_TEST -o "$test_root/data.iso" "$test_root/Source" > "$test_root/image-build.log" 2>&1
python3 - "$test_root" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1]); iso = (root/'data.iso').read_bytes()
assert len(iso) % 2048 == 0
with (root/'track.bin').open('wb') as stream:
    for offset in range(0, len(iso), 2048):
        stream.write(b'\0' + b'\xff'*10 + b'\0' + b'\0\x02\0\x01')
        stream.write(iso[offset:offset+2048]); stream.write(bytes(288))
(root/'audio.bin').write_bytes(bytes(2352*75))
cooked = 'FILE "data.iso" BINARY\n  TRACK 01 MODE1/2048\n    INDEX 01 00:00:00\n'
raw = 'FILE "track.bin" BINARY\n  TRACK 01 MODE1/2352\n    INDEX 01 00:00:00\n'
audio = 'FILE "audio.bin" BINARY\n  TRACK 02 AUDIO\n    INDEX 01 00:00:00\n'
for name, text in {'cooked': cooked, 'raw': raw, 'mixed': raw+audio,
                   'missing': raw+audio.replace('audio.bin', 'missing.bin'), 'invalid': 'not a cuesheet\n'}.items():
    (root/(name+'.cue')).write_text(text)
PY
ditto "$source_app" "$test_root/Boxer.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier net.washboardabs.boxer.cue-$label" "$test_root/Boxer.app/Contents/Info.plist"
codesign --force --deep --sign - "$test_root/Boxer.app"
xcrun clang -fobjc-arc -fmodules -dynamiclib -undefined dynamic_lookup -framework Cocoa \
    -I Boxer -I 'Other Sources/ADBToolkit' Tests/CueImportSmoke.m -o "$test_root/CueImportSmoke.dylib"
BOXER_CUE_ROOT="$test_root" DYLD_INSERT_LIBRARIES="$test_root/CueImportSmoke.dylib" \
    "$test_root/Boxer.app/Contents/MacOS/Boxer" -ApplePersistenceIgnoreState YES -SUEnableAutomaticChecks NO \
    -startupAction 0 > "$test_root/results.log" 2>&1
cat "$test_root/results.log"

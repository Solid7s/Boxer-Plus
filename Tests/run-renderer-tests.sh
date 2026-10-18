#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Users/sung/Downloads/Xcode.app/Contents/Developer}"
source_app="${1:-build/Release/Build/Products/Release/Boxer.app}"
test_app="$PWD/build/Boxer-Renderer-Test.app"
mkdir -p build
ditto "$source_app" "$test_app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier net.washboardabs.boxer.renderer-test' "$test_app/Contents/Info.plist"
codesign --force --deep --sign - "$test_app"
xcrun clang -fobjc-arc -fmodules -dynamiclib -framework Cocoa -framework MetalKit \
    -I 'Boxer/Metal Rendering' -I Boxer/Rendering \
    Tests/RendererSmoke.m -o build/RendererSmoke.dylib
DYLD_INSERT_LIBRARIES="$PWD/build/RendererSmoke.dylib" \
    "$test_app/Contents/MacOS/Boxer" -ApplePersistenceIgnoreState YES -SUEnableAutomaticChecks NO \
    2>&1 | tee build/renderer-test-latest.log
if ! rg -q '^PASS: GPU selection, first frame, unchanged frames, dirty rows, coalescing, busy GPU, CRT Light, CRT, pause, shader controls, occlusion, resize, clear/resume$' build/renderer-test-latest.log; then
    printf 'Renderer test ended before completing all checks.\n' >&2
    exit 1
fi

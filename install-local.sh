#!/bin/bash
# Install only a verified Release product, preserving the previous app.
set -euo pipefail
cd "$(dirname "$0")"
app="${1:-build/Release/Build/Products/Release/Boxer.app}"
test -x "$app/Contents/MacOS/Boxer"
test ! -e "$app/Contents/MacOS/Boxer.debug.dylib"
codesign --verify --deep --strict "$app"
if pgrep -x Boxer >/dev/null; then
    printf 'Close Boxer before replacing the installed app. No files changed.\n' >&2
    exit 1
fi
backup="$PWD/build/Backups/Boxer-before-performance-$(date +%Y%m%d-%H%M%S).app"
stage="/Applications/.Boxer-performance-$$.app"
destination='/Applications/Boxer+.app'
mkdir -p build/Backups
ditto "$app" "$stage"
codesign --verify --deep --strict "$stage"
if [[ -e "$destination" ]]; then
    mv "$destination" "$backup"
fi
if ! mv "$stage" "$destination"; then
    if [[ -e "$backup" ]]; then mv "$backup" "$destination"; fi
    exit 1
fi
codesign --verify --deep --strict "$destination"
printf 'Installed: %s\nPrevious app: %s\n' "$destination" "$backup"

#!/bin/bash
# Build a local, ad-hoc signed Release app. Never install a Debug product.
set -euo pipefail
cd "$(dirname "$0")"
./BuildSupport/apply-core-patches.sh

if [[ -z "${DEVELOPER_DIR:-}" && -d /Users/sung/Downloads/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Users/sung/Downloads/Xcode.app/Contents/Developer
fi

build_dir="${1:-${BOXER_BUILD_DIR:-$PWD/build/Release}}"
mkdir -p Boxer.xcworkspace/xcshareddata/swiftpm
if [[ ! -f Boxer.xcworkspace/xcshareddata/swiftpm/Package.resolved ]]; then
    cp BuildSupport/Package.resolved Boxer.xcworkspace/xcshareddata/swiftpm/Package.resolved
fi
build_args=(-workspace Boxer.xcworkspace -scheme 'Boxer CI'
    -configuration Release -derivedDataPath "$build_dir")
packages_dir="${3:-${BOXER_PACKAGES_DIR:-}}"
if [[ -n "$packages_dir" ]]; then
    build_args+=(-clonedSourcePackagesDirPath "$packages_dir")
fi
lto="${2:-${BOXER_LTO:-}}"
if [[ -n "$lto" ]]; then
    case "$lto" in
        NO|YES_THIN|YES) build_args+=("LLVM_LTO=$lto") ;;
        *) printf 'BOXER_LTO must be NO, YES_THIN or YES.\n' >&2; exit 1 ;;
    esac
fi

xcrun xcodebuild "${build_args[@]}" \
    -disableAutomaticPackageResolution -jobs "${BOXER_BUILD_JOBS:-4}" \
    ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY=- \
    ENABLE_DEBUG_DYLIB=NO build

app="$build_dir/Build/Products/Release/Boxer.app"
test -x "$app/Contents/MacOS/Boxer"
test ! -e "$app/Contents/MacOS/Boxer.debug.dylib"
codesign --verify --deep --strict "$app"
printf '\nRelease app: %s\n' "$app"

#!/bin/bash
# Sequential tests only: do not build or run another emulator during benchmarks.
set -euo pipefail
cd "$(dirname "$0")/.."
stage="${1:?Choose renderer, smoke, limits, shaders, compatibility, compiler, or sustained}"
app="${2:-build/ReleaseBaseline/Build/Products/Release/Boxer.app}"
run_id="${3:-$(date +%Y%m%d-%H%M%S)}"
[[ "$run_id" =~ ^[a-z0-9-]+$ ]] || exit 1
prefix="round2-$stage-$run_id"
probe() {
    ./Tests/run-game-probe.sh "$1" "$prefix-$2" "${3:-50}" "${4:-0}" > "build/run-$prefix-$2.log" 2>&1
    rg '^PASS:' "build/probe-$prefix-$2.log"
}
case "$stage" in
    acceptance)
        for check in renderer smoke limits shaders compatibility; do
            "$0" "$check" "$app" "$run_id"
        done
        ;;
    renderer)
        ./Tests/run-renderer-tests.sh "$app" > "build/renderer-$prefix.log" 2>&1
        tail -1 "build/renderer-$prefix.log"
        ;;
    smoke)
        BOXER_TEST_SECONDS=60 BOXER_TEST_LIMIT=100000 probe "$app" policy 50 1
        probe "$app" restore 0 2
        ;;
    limits)
        for limit in 75000 100000 150000; do
            BOXER_TEST_SECONDS=90 BOXER_TEST_LIMIT="$limit" probe "$app" "$limit"
        done
        BOXER_TEST_SECONDS=90 BOXER_TEST_LIMIT=100000 probe "$app" balanced-100000 75
        ;;
    shaders)
        for style in 2 3; do
            BOXER_TEST_SECONDS=90 BOXER_TEST_FIXED=100000 BOXER_TEST_STYLE="$style" probe "$app" "$style"
        done
        ;;
    compatibility)
        BOXER_TEST_SOURCE='Resources/Sample Games/Underworld Demo.boxer' BOXER_TEST_PROCESS=UWDEMO BOXER_TEST_CORE=normal probe "$app" underworld 0
        BOXER_TEST_SOURCE='Resources/Sample Games/Epic Pinball Demo.boxer' BOXER_TEST_PROCESS=PINBALL,EP1 BOXER_TEST_CORE=normal probe "$app" pinball 0
        ;;
    compiler)
        compare="${4:?Pass the otherwise-identical ThinLTO app as argument 4}"
        BOXER_TEST_SECONDS=180 BOXER_TEST_FIXED=100000 probe "$app" normal
        BOXER_TEST_SECONDS=180 BOXER_TEST_FIXED=100000 probe "$compare" thinlto
        ;;
    sustained)
        BOXER_TEST_SECONDS=600 probe build/Boxer-Before-Round2.app before
        BOXER_TEST_SECONDS=600 BOXER_TEST_LIMIT="${5:-100000}" probe "$app" after "${4:-50}"
        ;;
    *) printf 'Unknown stage: %s\n' "$stage" >&2; exit 1 ;;
esac

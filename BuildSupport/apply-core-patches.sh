#!/bin/bash
# Migrate an existing checkout away from the retired ordinary-sleep-only patch.
# Fresh submodules already have the original runtime sleep selection.
set -euo pipefail
cd "$(dirname "$0")/.."
patch_file="$PWD/BuildSupport/dosbox-energy.patch"
if git -C DOSBox-Staging apply --reverse --check "$patch_file" 2>/dev/null; then
    git -C DOSBox-Staging apply --reverse "$patch_file"
    printf 'Restored the core runtime sleep selection.\n'
    exit 0
fi
if ! git -C DOSBox-Staging apply --check "$patch_file"; then
    printf 'DOSBox core differs from the expected revision. Review BuildSupport/dosbox-energy.patch before building.\n' >&2
    exit 1
fi
# The old patch would apply: the core is already in its original state.

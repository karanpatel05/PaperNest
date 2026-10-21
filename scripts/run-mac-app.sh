#!/usr/bin/env bash
# Builds and opens the dev Mac app against a throwaway library seeded with
# the synthetic samples, so manual checks never touch a real library.
#
# Usage: scripts/run-mac-app.sh [library-dir] [-- extra app arguments]
#   e.g. scripts/run-mac-app.sh /tmp/pn-dev -- -AppleLanguages "(fr)"
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh

LIBRARY="/tmp/papernest-dev-library"
if [[ $# -gt 0 && "$1" != "--" ]]; then LIBRARY="$1"; shift; fi
[[ "${1:-}" == "--" ]] && shift

./scripts/build-mac-app.sh
if [[ ! -e "$LIBRARY/Library.sqlite" ]]; then
    swift run --scratch-path "$SCRATCH" papernest-seed "$LIBRARY" \
        Samples/*.pdf Samples/*.jpg Samples/*.png --password sample
fi
open -n "$DIST/PaperNest.app" --args -PaperNestLibraryPath "$LIBRARY" "$@"
echo "Opened $DIST/PaperNest.app with library $LIBRARY"

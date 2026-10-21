#!/usr/bin/env bash
# Runs the package test suite.
#
# With full Xcode selected, `swift test` finds Swift Testing on its own.
# With only Command Line Tools (verified with CLT 26.2):
# - Testing.framework lives outside the default search path, so framework
#   and rpath flags are added explicitly;
# - the `_Testing_Foundation` cross-import overlay ships without its
#   .swiftmodule, so any file importing both Foundation and Testing fails
#   unless cross-import overlays are disabled for the test build.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh

DEV_DIR="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
EXTRA=()
if [[ "$DEV_DIR" == *CommandLineTools* ]]; then
    F="$DEV_DIR/Library/Developer/Frameworks"
    EXTRA=(
        -Xswiftc -F -Xswiftc "$F"
        -Xlinker -F -Xlinker "$F"
        -Xlinker -rpath -Xlinker "$F"
        -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays
    )
fi

# `${EXTRA[@]+...}` because macOS's bash 3.2 treats an empty array as unset under `set -u`.
exec swift test --scratch-path "$SCRATCH" ${EXTRA[@]+"${EXTRA[@]}"} "$@"

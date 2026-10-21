#!/usr/bin/env bash
# Runs the iOS UI tests (Apps/iOS/UITests) headless in the Simulator. Seeds
# the library the tests open, regenerates the Xcode project, then runs
# `xcodebuild test`. Nothing is shown on screen.
#
# Usage: scripts/ui-test-ios.sh [simulator-udid]
#   Defaults to the "PaperNest iPhone Duo" simulator, else the first
#   available iPhone.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh

DEVICE="${1:-}"
if [[ -z "$DEVICE" ]]; then
    DEVICE="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = [d for runtime in json.load(sys.stdin)["devices"].values() for d in runtime]
named = [d for d in devices if d["name"].startswith("PaperNest")]
phones = [d for d in devices if "iPhone" in d["name"]]
print((named or phones)[0]["udid"] if (named or phones) else "")')"
fi
[[ -n "$DEVICE" ]] || { echo "no iPhone simulator available" >&2; exit 69; }

# Must match CropUITests.libraryPath.
LIBRARY="/tmp/papernest-uitest-library"
rm -rf "$LIBRARY"
FIXTURES="$(mktemp -d)"
cp Samples/whiteboard-300dpi.png "$FIXTURES/Crop target.png"
swift run --scratch-path "$SCRATCH" papernest-seed "$LIBRARY" "$FIXTURES/Crop target.png"
rm -rf "$FIXTURES"

xcodegen generate --quiet
xcodebuild test -project PaperNest.xcodeproj -scheme PaperNest-iOS \
    -destination "platform=iOS Simulator,id=$DEVICE" \
    -derivedDataPath "$SCRATCH/xcodeproj"

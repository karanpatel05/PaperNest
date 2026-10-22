#!/usr/bin/env bash
# Runs the iOS UI tests (Apps/iOS/UITests) headless in the Simulator. Seeds
# the library the tests open, regenerates the Xcode project, then runs
# `xcodebuild test`. Nothing is shown on screen.
#
# Usage: scripts/ui-test-ios.sh [simulator-udid] [extra xcodebuild args…]
#   Defaults to the "PaperNest iPhone Duo" simulator, else the first
#   available iPhone. Extra args go to xcodebuild, e.g. on an iPad:
#   scripts/ui-test-ios.sh <ipad-udid> -only-testing:PaperNest-iOSUITests/AppUITests/testMarkupWithFingerDrawingSavesAStroke
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh

DEVICE="${1:-}"
shift || true
if [[ -z "$DEVICE" ]]; then
    DEVICE="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = [d for runtime in json.load(sys.stdin)["devices"].values() for d in runtime]
named = [d for d in devices if d["name"].startswith("PaperNest")]
phones = [d for d in devices if "iPhone" in d["name"]]
print((named or phones)[0]["udid"] if (named or phones) else "")')"
fi
[[ -n "$DEVICE" ]] || { echo "no iPhone simulator available" >&2; exit 69; }

# Must match AppUITests.libraryPath.
LIBRARY="/tmp/papernest-uitest-library"
rm -rf "$LIBRARY"
FIXTURES="$(mktemp -d)"
cp Samples/whiteboard-300dpi.png "$FIXTURES/Crop target.png"
swift run --scratch-path "$SCRATCH" papernest-seed "$LIBRARY" "$FIXTURES/Crop target.png"
# Document-tools tests use separate disposable libraries, so their copies
# cannot change the counts and ordering expected by existing UI tests.
for TOOLS_LIBRARY in /tmp/papernest-file-tools-uitest-library /tmp/papernest-file-tools-layout-library; do
    rm -rf "$TOOLS_LIBRARY"
    swift run --scratch-path "$SCRATCH" papernest-seed "$TOOLS_LIBRARY" "$FIXTURES/Crop target.png"
done
# The file-item test needs something that cannot become pages.
printf 'quarterly figures\n' > "$FIXTURES/Budget notes.txt"
FILES_LIBRARY=/tmp/papernest-file-items-library
rm -rf "$FILES_LIBRARY"
swift run --scratch-path "$SCRATCH" papernest-seed "$FILES_LIBRARY" "$FIXTURES/Budget notes.txt"

# A missing synthetic original exercises the preview error and its dismissal.
MISSING_FILE_LIBRARY=/tmp/papernest-missing-file-preview-library
rm -rf "$MISSING_FILE_LIBRARY"
cp -R "$FILES_LIBRARY" "$MISSING_FILE_LIBRARY"
python3 - "$MISSING_FILE_LIBRARY/Assets" <<'PY'
from pathlib import Path
import sys
for asset in Path(sys.argv[1]).rglob('*.bin'):
    asset.unlink()
PY

# The text-recognition test reads words printed on a real sample page.
cp Samples/multilingual-letter.pdf "$FIXTURES/OCR target.pdf"
OCR_LIBRARY=/tmp/papernest-ocr-library
rm -rf "$OCR_LIBRARY"
swift run --scratch-path "$SCRATCH" papernest-seed "$OCR_LIBRARY" "$FIXTURES/OCR target.pdf"

# The Tools screen test merges two documents of its own.
cp Samples/whiteboard-300dpi.png "$FIXTURES/Tools A.png"
cp Samples/whiteboard-300dpi.png "$FIXTURES/Tools B.png"
TOOLS_SCREEN_LIBRARY=/tmp/papernest-tools-screen-library
rm -rf "$TOOLS_SCREEN_LIBRARY"
swift run --scratch-path "$SCRATCH" papernest-seed "$TOOLS_SCREEN_LIBRARY" "$FIXTURES/Tools A.png" "$FIXTURES/Tools B.png"

# The split test needs one document with several pages.
cp Samples/multilingual-letter.pdf "$FIXTURES/Split target.pdf"
SPLIT_LIBRARY=/tmp/papernest-file-tools-split-library
rm -rf "$SPLIT_LIBRARY"
swift run --scratch-path "$SCRATCH" papernest-seed "$SPLIT_LIBRARY" "$FIXTURES/Split target.pdf"
rm -rf "$FIXTURES"

xcodegen generate --quiet
xcodebuild test -project PaperNest.xcodeproj -scheme PaperNest-iOS \
    -destination "platform=iOS Simulator,id=$DEVICE" \
    -derivedDataPath "$SCRATCH/xcodeproj" ${1+"$@"}

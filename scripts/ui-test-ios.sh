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
# The file-item test needs something that does not become pages. Text files
# do since 2026-11-15; a web page does not, and Quick Look still shows its words.
printf 'quarterly figures\n' > "$FIXTURES/Budget notes.html"
FILES_LIBRARY=/tmp/papernest-file-items-library
rm -rf "$FILES_LIBRARY"
swift run --scratch-path "$SCRATCH" papernest-seed "$FILES_LIBRARY" "$FIXTURES/Budget notes.html"

# Office files laid out as pages on iPhone and iPad (OfficeImportUITests). The
# Simulator cannot write Word or Excel, so they are made here: Word by
# textutil from RTF, Excel as a hand-built minimal workbook. All synthetic.
OFFICE=/tmp/papernest-office-fixtures
rm -rf "$OFFICE" && mkdir -p "$OFFICE"
{ printf '{\\rtf1\\ansi{\\fonttbl\\f0 Helvetica;}\\f0\\fs28 {\\b Project proposal}\\par\\fs22 Prepared for the quarterly review.\\par '
  for i in $(seq 1 120); do printf 'Line %d of the proposal, long enough to wrap across the page width.\\par ' "$i"; done
  printf '}'; } > "$OFFICE/proposal.rtf"
textutil -convert docx "$OFFICE/proposal.rtf" -output "$OFFICE/Proposal.docx"
textutil -convert doc "$OFFICE/proposal.rtf" -output "$OFFICE/Legacy proposal.doc"
{ printf '{\\rtf1\\ansi{\\fonttbl\\f0 Helvetica;}\\f0\\fs22 '
  for i in $(seq 1 2400); do printf 'Paragraph %d of a long report, written to run to many pages.\\par ' "$i"; done
  printf '}'; } > "$OFFICE/long.rtf"
textutil -convert docx "$OFFICE/long.rtf" -output "$OFFICE/Long report.docx"
rm "$OFFICE/proposal.rtf" "$OFFICE/long.rtf"
printf 'PK\003\004 not really a spreadsheet' > "$OFFICE/Broken.xlsx"
python3 - "$OFFICE/Budget.xlsx" <<'PY_XLSX'
import sys, zipfile
ns = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
rels = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
parts = {
    "[Content_Types].xml": '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/></Types>',
    "_rels/.rels": f'<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="{rels}/officeDocument" Target="xl/workbook.xml"/></Relationships>',
    "xl/workbook.xml": f'<?xml version="1.0" encoding="UTF-8"?><workbook {ns} xmlns:r="{rels}"><sheets><sheet name="Budget" sheetId="1" r:id="rId1"/></sheets></workbook>',
    "xl/_rels/workbook.xml.rels": f'<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="{rels}/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="{rels}/sharedStrings" Target="sharedStrings.xml"/></Relationships>',
    "xl/sharedStrings.xml": f'<?xml version="1.0" encoding="UTF-8"?><sst {ns} count="3" uniqueCount="3"><si><t>Item</t></si><si><t>Amount</t></si><si><t>Paper</t></si></sst>',
    "xl/worksheets/sheet1.xml": f'<?xml version="1.0" encoding="UTF-8"?><worksheet {ns}><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row><row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2"><v>1234.5</v></c></row></sheetData></worksheet>',
}
with zipfile.ZipFile(sys.argv[1], "w", zipfile.ZIP_DEFLATED) as z:
    for name, body in parts.items():
        z.writestr(name, body)
PY_XLSX

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

# Text markup has its own real OCR source, independent of the search test.
cp Samples/multilingual-letter.pdf "$FIXTURES/Markup target.pdf"
MARKUP_LIBRARY=/tmp/papernest-text-markup-library
rm -rf "$MARKUP_LIBRARY"
swift run --scratch-path "$SCRATCH" papernest-seed "$MARKUP_LIBRARY" "$FIXTURES/Markup target.pdf"

# Saved-mark controls have an independent library per locale.
for MARKUP_LOCALE in en fr es; do
    CONTROLS_LIBRARY="/tmp/papernest-markup-controls-$MARKUP_LOCALE"
    rm -rf "$CONTROLS_LIBRARY"
    cp -R "$MARKUP_LIBRARY" "$CONTROLS_LIBRARY"
done

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

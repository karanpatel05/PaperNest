#!/usr/bin/env bash
# Builds a runnable, ad-hoc-signed PaperNest.app from the Swift package,
# for development on machines with only Command Line Tools. Release builds
# come from the Xcode project (see README "Xcode project").
#
# Usage: scripts/build-mac-app.sh [debug|release] [--sandbox]
#   --sandbox  sign with Apps/Mac/PaperNest.entitlements (App Sandbox on);
#              the library then lives in the app's container.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh

CONFIG="debug"
SANDBOX=0
for arg in "$@"; do
    case "$arg" in
        debug|release) CONFIG="$arg" ;;
        --sandbox) SANDBOX=1 ;;
        *) echo "unknown argument: $arg" >&2; exit 64 ;;
    esac
done

swift build --scratch-path "$SCRATCH" -c "$CONFIG" --product PaperNestMac
BIN_DIR="$(swift build --scratch-path "$SCRATCH" -c "$CONFIG" --show-bin-path)"

APP="$DIST/PaperNest.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PaperNestMac" "$APP/Contents/MacOS/PaperNest"
# Resource bundles go in Contents/Resources; PaperNestUI's ResourceBundle
# looks there first (SwiftPM's default accessor would look at the .app root,
# which breaks code signing).
cp -R "$BIN_DIR/PaperNest_PaperNestUI.bundle" "$APP/Contents/Resources/"
cp -R Apps/Mac/Resources/*.lproj "$APP/Contents/Resources/"
# The Xcode target gets its icon from Apps/Shared/Assets.xcassets, which
# nothing compiles here; this bundle carries the .icns instead. Both come
# out of scripts/make-app-icon.py, so they cannot drift.
cp Apps/Mac/PaperNest.icns "$APP/Contents/Resources/"

# Placeholder identifier: replace via Config/Base.xcconfig for real builds.
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.example.papernest.dev</string>
    <key>CFBundleName</key><string>PaperNest</string>
    <key>CFBundleDisplayName</key><string>PaperNest</string>
    <key>CFBundleExecutable</key><string>PaperNest</string>
    <key>CFBundleIconFile</key><string>PaperNest</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>fr</string><string>es</string></array>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
PLIST

# iCloud Drive's file provider can attach Finder info to bundles in this
# folder; codesign rejects bundles carrying such attributes.
xattr -cr "$APP"
if [[ $SANDBOX -eq 1 ]]; then
    codesign --force --sign - --entitlements Apps/Mac/PaperNest.entitlements "$APP"
else
    codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP ($CONFIG$([[ $SANDBOX -eq 1 ]] && echo ', sandboxed'))"

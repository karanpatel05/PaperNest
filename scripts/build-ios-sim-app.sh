#!/usr/bin/env bash
# Builds the real iPhone/iPad app (PaperNest-iOS from the XcodeGen project)
# for the iOS Simulator and prints its path. The Xcode build carries the
# Simulator entitlements that iOS requires before it hands picked files to
# the app; a hand-assembled bundle does not, and file picking then fails.
#
# Usage: scripts/build-ios-sim-app.sh
# Then: xcrun simctl install <device> <printed path>
#       xcrun simctl launch <device> com.example.papernest
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh

xcodegen generate --quiet
xcodebuild -project PaperNest.xcodeproj -scheme PaperNest-iOS -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$SCRATCH/xcodeproj" -configuration Debug build -quiet

APP="$DIST/ios-simulator/PaperNest.app"
rm -rf "$APP"
mkdir -p "$(dirname "$APP")"
cp -R "$SCRATCH/xcodeproj/Build/Products/Debug-iphonesimulator/PaperNest.app" "$APP"
echo "Built $APP (bundle id $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist"))"

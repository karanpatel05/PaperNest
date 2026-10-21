#!/usr/bin/env bash
# Builds an iOS Simulator PaperNest.app from the Swift package, for running
# in the iOS Simulator without the generated Xcode project. Needs full Xcode.
# Release and device builds come from the Xcode project (project.yml).
#
# Usage: scripts/build-ios-sim-app.sh
# Then, for example (the script prints the app's path):
#   xcrun simctl install booted <printed path>
#   xcrun simctl launch booted com.example.papernest.dev
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh

DERIVED="$SCRATCH/xcode"
xcodebuild -scheme PaperNestPhone -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED" -configuration Debug build -quiet
PRODUCTS="$DERIVED/Build/Products/Debug-iphonesimulator"

APP="$DIST/ios-simulator/PaperNest.app"
rm -rf "$APP"
mkdir -p "$APP"
cp "$PRODUCTS/PaperNestPhone" "$APP/PaperNest"
# iOS bundles are flat: resource bundles sit at the app root, where both
# SwiftPM's accessor and PaperNestUI's ResourceBundle look.
cp -R "$PRODUCTS/PaperNest_PaperNestUI.bundle" "$APP/"
cp -R Apps/iOS/Resources/*.lproj "$APP/"

# Expand the Xcode build variables in the real Info.plist; placeholder
# identifier as in Config/Base.xcconfig, with a .dev suffix.
sed -e 's/$(EXECUTABLE_NAME)/PaperNest/' \
    -e 's/$(PRODUCT_BUNDLE_IDENTIFIER)/com.example.papernest.dev/' \
    -e 's/$(PRODUCT_NAME)/PaperNest/' \
    -e 's/$(MARKETING_VERSION)/0.1.0/' \
    -e 's/$(CURRENT_PROJECT_VERSION)/1/' \
    Apps/iOS/Info.plist > "$APP/Info.plist"
plutil -insert MinimumOSVersion -string 17.0 "$APP/Info.plist"
plutil -insert UIDeviceFamily -json '[1,2]' "$APP/Info.plist"
plutil -insert CFBundleSupportedPlatforms -json '["iPhoneSimulator"]' "$APP/Info.plist"

xattr -cr "$APP"
codesign --force --sign - --timestamp=none "$APP"
echo "Built $APP"

# PaperNest

A native document scanner and notebook app for iPhone, iPad and Mac: scan paper on iPhone, organize and annotate on iPad, then edit, organize and export on Mac. English, French and Spanish.

"PaperNest" is a placeholder working name, not a cleared trademark. Branding lives in `Sources/PaperNestCore/Brand.swift` and `Config/Base.xcconfig`.

**Status:** milestone M0 is done and M1 is partly done. The shared code and tests pass on macOS, and the iPhone UI has been checked in the Simulator from screenshots. See [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) for status and [docs/TEST_MATRIX.md](docs/TEST_MATRIX.md) for evidence. This is not production-ready.

## Layout

| Path | What |
|---|---|
| `Package.swift` | Swift package with all shared code, tests, a dev Mac executable and the sample generator |
| `Sources/PaperNestCore` | Domain model, page geometry, sort keys, branding |
| `Sources/PaperNestStore` | SQLite metadata store, content-addressed asset files, migrations, recovery |
| `Sources/PaperNestImport` | PDF/JPEG/PNG import, validation, password-protected PDFs |
| `Sources/PaperNestRender` | Page rendering (vector PDF, upright images, filters) |
| `Sources/PaperNestExport` | PDF, JPEG, PNG and ZIP export |
| `Sources/PaperNestUI` | Shared SwiftUI views, view models, localization (en/fr/es) |
| `Apps/Mac` | Native macOS app entry point, Info.plist, entitlements |
| `Apps/iOS` | iPhone/iPad app entry point and Info.plist (not yet compiled) |
| `project.yml` | XcodeGen spec for the iOS and macOS app targets |
| `Tests/` | Swift Testing suites and synthetic fixtures (`Tests/Support`) |
| `Samples/` | Synthetic sample documents (regenerate with `swift run papernest-samples Samples`) |
| `docs/` | Spec, architecture, plan, test matrix, Apple setup, release checklist, handoff |

## Requirements

- macOS 14 or later to run the Mac app. Development so far used macOS 26.6.2 on Apple silicon.
- Swift 6 toolchain. Command Line Tools 26.2 (Swift 6.2.3) is enough for the package, its tests and the dev Mac app.
- Full Xcode for the iOS/iPadOS app, simulators, sanitizers, StoreKit testing, archives and String Catalog tooling. Verified with Xcode 27.1.
- Deployment targets are iOS/iPadOS 17.0 and macOS 14.0, set by `CKSyncEngine` and the Observation framework. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#platform-and-deployment-targets).

No third-party dependencies. Everything uses Apple frameworks and the system SQLite.

## Document tools

In **All Documents** or a folder, use **Select** to choose several documents, then **More** for merge, duplicate, color label, move or delete. Merge opens a sheet where you name the new document and arrange the source documents. A document’s **⋯** menu also offers **Duplicate**, **Extract Pages**, and **Color Label**. Extraction copies the pages you select in their original order. The source documents remain unchanged and the new documents remain editable.

The broader feature request from the nine reference photos is tracked in [the expansion roadmap](docs/FEATURE_EXPANSION.md). General file storage, archives, richer PDF editing, OCR/conversions, cloud providers, media, browser and VPN are future workstreams.

## Build and test

The scripts keep build output in `~/Library/Caches/PaperNest/build-<hash>`, not in the checkout (`scripts/env.sh`). This checkout lives on an iCloud-synced Desktop, where iCloud adds attributes that make `codesign` fail and syncs hundreds of MB of build output. For ad-hoc SwiftPM commands use `scripts/swift.sh <command> …`, for example `scripts/swift.sh build`.

```bash
./scripts/test.sh
```

This runs every test suite. Add `--sanitize=thread` or `--sanitize=address` for sanitizer runs (Xcode only). With only Command Line Tools selected, the script adds the framework search paths that Swift Testing needs (see the comments inside it). If Xcode is installed but its license isn't accepted yet, prefix commands with `DEVELOPER_DIR=/Library/Developer/CommandLineTools`.

```bash
./scripts/build-mac-app.sh
```

This builds an ad-hoc-signed development `PaperNest.app` and prints its path under `~/Library/Caches/PaperNest/`. Add `release` for an optimized build or `--sandbox` to sign with the App Sandbox entitlements. To run it, `run-mac-app.sh` builds the app, seeds a throwaway library with the samples (the first time) and opens it, so your real data is never touched:

```bash
./scripts/run-mac-app.sh /tmp/papernest-dev-library
```

The `-PaperNestLibraryPath` argument only works in debug builds. Otherwise the library lives in `~/Library/Application Support/PaperNest/Library`, inside the app's container when sandboxed.

```bash
scripts/swift.sh run papernest-samples Samples
```

This regenerates the synthetic sample documents.

```bash
scripts/swift.sh run papernest-seed /tmp/papernest-dev-library Samples/*.pdf Samples/*.png Samples/*.jpg --password sample
```

This imports files into a library folder through the real importer, so a dev app or Simulator run starts with content. Add `--crop x,y,w,h` (fractions of the original) to crop every imported page.

### iOS UI tests

```bash
./scripts/ui-test-ios.sh
```

This seeds `/tmp/papernest-uitest-library`, regenerates the Xcode project and runs the `PaperNest-iOSUITests` XCUITests headless in the Simulator. Pass a simulator UDID to choose the device.

### iOS Simulator app

```bash
./scripts/build-ios-sim-app.sh
```

This regenerates the Xcode project, builds the `PaperNest-iOS` app for the Simulator and prints its path. (A hand-assembled bundle lacks the entitlements section the Files picker needs.) Install and launch it with `xcrun simctl install <device> <printed path>` and `xcrun simctl launch <device> com.example.papernest`. Debug builds accept `-PaperNestDebugOpenItem <document name>`, `-PaperNestDebugShowExport YES` and `-PaperNestDebugShowCrop YES` to open screens without tapping, and `-AppleLanguages "(fr)"` to switch language. Screenshots of a dual-display simulator need `--display=primary`.

## Xcode project

The Xcode project is generated from `project.yml` and is not checked in:

```bash
brew install xcodegen
xcodegen generate
open PaperNest.xcodeproj
```

Schemes: `PaperNest-iOS` (iPhone and iPad, one target) and `PaperNest-macOS` (native AppKit/SwiftUI app, not Catalyst). Both share the bundle identifier `$(PAPERNEST_BUNDLE_ID)` so they can be sold as one universal purchase.

To check that the shared code compiles for iOS without the app project:

```bash
xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build
```

## Signing placeholders

`Config/Base.xcconfig` uses the placeholder `com.example.papernest` and an empty team. Put real values in `Config/Signing.local.xcconfig`, which is git-ignored:

```
PAPERNEST_BUNDLE_ID = com.yourcompany.papernest
PAPERNEST_TEAM_ID = ABCDE12345
```

The remaining manual Apple setup (App IDs, iCloud container, StoreKit products) is listed in [docs/APPLE_SETUP.md](docs/APPLE_SETUP.md).

## Supported platforms

| Platform | State |
|---|---|
| macOS 14+ (native) | Builds and runs (dev bundle). Import, library, page edits and export are covered by automated tests. The UI has not been visually verified yet. |
| iOS 17+ (iPhone) | The Xcode project's `PaperNest-iOS` builds for the Simulator; shared code also compiles for devices. 0 warnings. Library, document and export screens verified in the Simulator (screenshots in `docs/screenshots/`). Taps and camera not yet exercised. |
| iPadOS 17+ | Compiles (same target). Layout not verified: the installed runtime has no iPad simulator. |

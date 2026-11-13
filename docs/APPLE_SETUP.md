# Apple setup still required

Everything here is manual, and it all needs your Apple Developer account. Claude can't do these steps and doesn't do them on your behalf. Nothing has been registered, purchased or uploaded.

## 0. This Mac

1. Finish installing Xcode. Xcode 27.1 is in `/Applications`.
2. Accept the license and run first-launch setup. Both need your admin password:
   ```bash
   sudo xcodebuild -license accept
   ```
   ```bash
   sudo xcodebuild -runFirstLaunch
   ```
3. Check that Xcode is selected: `xcode-select -p` should print `/Applications/Xcode.app/Contents/Developer`.
4. Install an iOS Simulator runtime: Xcode > Settings > Components.
5. Install XcodeGen, then generate the project:
   ```bash
   brew install xcodegen
   ```
   ```bash
   xcodegen generate
   ```

## 1. Identity

- Pick the real bundle identifier, for example `com.yourcompany.papernest`. iOS and macOS **must use the same one** for universal purchase.
- Create `Config/Signing.local.xcconfig` (it's git-ignored) with:
  ```
  PAPERNEST_BUNDLE_ID = com.yourcompany.papernest
  PAPERNEST_TEAM_ID = ABCDE12345
  ```
- Certificates, Identifiers & Profiles: register the App ID with these capabilities:
  - **iCloud** (CloudKit), once M2 starts
  - **In-App Purchase**
- Confirm the product name "PaperNest" is available and cleared. It's a placeholder.

## 2. iCloud / CloudKit (M2)

The code is in place and iCloud is **off in every build until these steps are done**. Until then the app has no
iCloud entitlement, never creates a `CKContainer`, and Settings says sync is not available in this build.

**In the developer portal (or Xcode → Signing & Capabilities), once:**

1. Certificates, Identifiers & Profiles → Identifiers → **iCloud Containers** → add `iCloud.<bundle id>`. With the
   current local identity that is `iCloud.com.karanpatel.papernest.dev48u7v37436`. Container IDs cannot be deleted
   or renamed, so use the real bundle ID before doing this for a release.
2. On the **App ID** for the bundle ID, enable **iCloud** (CloudKit, with that container ticked) and **Push
   Notifications**. iOS and macOS share the bundle ID, so this is one App ID.
3. Let Xcode regenerate the provisioning profiles (automatic signing does it the first time each target is built
   from the Xcode UI, or `xcodebuild -allowProvisioningUpdates`).

**In this repository:** add three lines to `Config/Signing.local.xcconfig` (git-ignored), then `xcodegen generate`:

```
PAPERNEST_ICLOUD_CONTAINER = iCloud.$(PAPERNEST_BUNDLE_ID)
PAPERNEST_IOS_ENTITLEMENTS = Apps/iOS/PaperNest.iCloud.entitlements
PAPERNEST_MAC_ENTITLEMENTS = Apps/Mac/PaperNest.iCloud.entitlements
```

That gives both apps `icloud-services = CloudKit`, the container, `aps-environment` (silent pushes), and on the Mac
`network.client`. `UIBackgroundModes = remote-notification` is already in the iOS Info.plist.

**The schema.** In the Development environment CloudKit creates record types as the app first saves them, so run
the app once on a signed-in device with sync on and make one of everything (a folder, a notebook with a stroke, an
imported PDF, a file item, a saved signature). The types are `Folder`, `Item`, `Page`, `PageObject`, `Signature`
in zone `PaperNestLibrary`, and `Original` in zone `PaperNestOriginals`. Nothing is queried, so **no indexes are
needed**. The fields `name`, `payload`, `strokes`, `fileName` and `assetName` are written as *encrypted* fields;
that choice cannot be changed for a field once the schema is in Production.

**Production.** App Store and TestFlight builds use the Production environment, which starts **empty**: nothing
syncs for real users until the schema is deployed. CloudKit Console → the container → Deploy Schema Changes →
review → deploy. Production only ever gains types and fields; it cannot drop or rename them. This is an explicit
release step that needs your approval. Claude will not deploy it.

**Testing** needs at least two devices (or a device and a Mac) signed in to the same Apple Account, each running a
build with the three lines above. The two-device checklist is in TEST_MATRIX.

## 3. App Store Connect (M5)

- Create the app records for iOS and macOS under the same bundle ID (universal purchase).
- Create **one subscription group** containing two auto-renewable subscriptions: Pro Monthly and Pro Annual. Choose the product IDs yourself; the code reads them from configuration, never hard-coded.
- Proposed prices (configuration proposals only):

  | Plan | US | Canada |
  |---|---|---|
  | Monthly | $3.99 | CA$5.49 |
  | Annual | $24.99 | CA$34.99 |
  | Introductory first annual term (optional) | $19.99 | CA$26.99 |

- Localize the subscription display names and descriptions in English, French and Spanish.
- Create Sandbox testers. For StoreKit local testing, a `.storekit` file will be added in M5.
- Paid Apps agreement, tax and banking: done by you in App Store Connect.

## 4. Pages that must exist before release

These are real URLs you host. The app won't ship placeholder links:

- Support page
- Privacy policy
- Terms of use, or Apple's standard EULA
- A private feedback channel, such as an email address or form

## 5. Release-time declarations

- App Privacy questionnaire in App Store Connect. `Apps/Shared/PrivacyInfo.xcprivacy` is a draft listing no tracking, no collected data, file timestamps (C617.1) and UserDefaults (CA92.1). Re-check it against Apple's current required-reason API list.
- Export compliance (`ITSAppUsesNonExemptEncryption`). The app uses only OS-provided encryption, but you make this declaration.
- Age rating and content descriptions.

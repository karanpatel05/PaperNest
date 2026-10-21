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

- Create the container `iCloud.<bundle id>` and attach it to the App ID.
- Add these entitlements to both apps; `Apps/Mac/PaperNest.entitlements` has them commented out:
  - `com.apple.developer.icloud-container-identifiers`
  - `com.apple.developer.icloud-services` = `CloudKit`
  - `com.apple.security.network.client` (Mac)
- Enable the iCloud capability for both targets in `project.yml`.
- Develop against the **Development** environment. Deploying the schema to **Production** is an explicit release step that needs your approval. Claude will not deploy it.
- Testing needs at least two devices (or a device plus a Mac) signed into the same test Apple Account.

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

# First-launch welcome

Owner request: design the initial page for first-time downloaders. Implement a native SwiftUI welcome before Home, once per installation, with one Get started action. Reuse the approved palette: indigo #5264FF, violet #9667FF, ice #F8F9FF, white #FFFFFF, dark #141623. System rounded title, system body, left-aligned readable copy. A stack of ruled paper is the focal illustration; three unboxed rows explain scanning/import, notes/markup, and organization. Phone stacks vertically; wide windows pair illustration and content; accessibility sizes stack and scroll. CTA stays reachable below scroll content. No signup, subscription, camera permission or Vault/VPN promise.

Implementation: localized WelcomeView; RootView persisted completion with debug-only isolated keys and bypass for existing UI tests; en/fr/es keys; focused first-launch/dismiss/relaunch tests plus large type screenshot. Verify units, Mac build, phone and iPad. Preserve Claude backend work.

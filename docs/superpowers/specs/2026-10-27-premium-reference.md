Owner clarification after this brief: Vault and VPN are deferred to the next version. Preserve functional app capabilities; do not add fake protection or collaboration.

# CODEX MASTER PROMPT — PAPER NEST PREMIUM UI/UX REDESIGN

You are a senior Apple UI/UX designer and expert SwiftUI engineer specializing in premium iOS, iPadOS, and macOS applications.

Your task is to redesign my existing **Paper NEST** application to reproduce the supplied reference image as closely as possible.

**Reference image:** `DesignReferences/paper-nest-reference.png`

## 1. Critical instructions

- First inspect my entire existing Paper NEST repository.
- Read `README.md`, `AGENTS.md`, project plans, architecture documents, implementation notes, and any handoff files before making changes.
- Identify existing screens, features, navigation, models, persistence, and services.
- Preserve existing working functionality.
- Do not rebuild the application from scratch unless absolutely necessary.
- Use the reference image as the primary visual design specification.
- Recreate the actual application interfaces shown inside the devices, not the surrounding advertising poster.
- Do not replace working functionality with static mockups.
- Use native SwiftUI and Apple's platform APIs.
- Support iPhone, iPad, and Mac with one consistent visual design system.
- Implement the redesign directly in the existing project, not as a disconnected sample project.

## 2. Design language — match reference exactly

Create a futuristic but professional productivity interface inspired by the reference.

**Visual characteristics:**
- Premium Apple-native aesthetics
- Soft lavender, icy blue, white, and subtle pastel gradients
- Frosted-glass panels and translucent surfaces
- Rounded cards with delicate borders
- Soft, realistic shadows
- Spacious layouts with consistent alignment
- SF Symbols with colorful gradient backgrounds
- SF Pro typography
- Smooth navigation transitions
- Subtle interactive animations
- Elegant hover, focus, and pressed states
- Beautiful light and dark mode support

Suggested design tokens:

| Element | Style |
|---|---|
| Primary accent | `#5264FF` |
| Secondary accent | `#9667FF` |
| Main background | `#F8F9FF` |
| Sidebar background | `#F0F2FF` |
| Card background | White with subtle translucency |
| Main text | `#171B30` |
| Secondary text | `#858BA3` |
| Card radius | 16–20 pt |
| Button radius | 12–16 pt |

Treat these as starting values. Visually refine them against the reference image.

## 3. macOS dashboard — exact visual structure

Recreate the Mac interface in the picture.

### Left sidebar

Place the Paper NEST logo and app name at the top.

Navigation items in this order:

1. Home
2. Notes
3. Documents
4. Scan & OCR
5. Vault
6. VPN
7. Shared
8. Favorites
9. Recents
10. Trash

Use matching SF Symbol icons.

The selected item should have a soft indigo/lavender highlight.

Under navigation, show the Folders section with an add button.

Folder colors and names:

- Personal — coral
- Work — red/orange
- Study — yellow
- Finance — green
- Health — blue
- Travel — purple
- Recipes — pink
- Ideas — violet

Sidebar should be responsive, polished, and collapsible where appropriate.

### Top toolbar

Include:

- Centered global search bar
- Keyboard shortcut hint `⌘K`
- User profile avatar
- Rounded gradient `+ New` button

### Welcome area

Display:

**Good Evening, [User Name]**

Subtitle: "Stay organized, secure and productive."

Greeting should change depending on time of day.

### Quick-action cards

Create six cards in one row when sufficient screen width is available:

1. New Note — orange
2. Scan Document — blue
3. Import File — green
4. New Folder — yellow
5. Vault — purple
6. VPN — blue

Each card should include:
- Large rounded colorful icon
- Bold feature name
- Small descriptive subtitle
- Subtle shadow
- Hover effect
- Functional click action

Match their layout, sizing, alignment, and spacing to the reference.

### Recent documents

Below quick actions, add a Recent section with filter tabs:

`All | Notes | Documents | Images | Vault | Shared`

Include `See All` on the right.

Display documents in a responsive thumbnail grid.

Each document card should have:
- Visual preview or thumbnail
- Name
- Type and size, where applicable
- Relative modification time
- Rounded corners
- Subtle shadow
- Hover animation
- Context menu

Use existing document data. If the project does not contain real user documents, use clearly identified preview data only for SwiftUI previews.

## 4. iPhone home screen

Recreate the mobile interface shown in the reference.

### Header

- Beautiful dark blue to muted purple gradient
- Paper NEST logo
- App title
- Settings icon
- Search bar

### Quick actions

Display six actions in a compact 4+2 layout where width permits:

First row:
- Note
- Scan
- Import
- Folder

Second row:
- Vault
- VPN

Use the matching pastel icon colors.

### Recent files

Display vertically stacked document rows with:
- Thumbnail
- Document title
- Secondary metadata
- Relative time
- Subtle row separators

### VPN status widget

Place a compact VPN connection card near the bottom of the home screen.

Include:
- VPN status
- Selected location
- Connection toggle
- Shield/globe icon
- Correct connected/disconnected styling

Never falsely display an active VPN connection.

### Bottom navigation

Create a premium tab bar with:

`Home | Folders | + | Shared | Search`

The center `+` button must be a floating, circular blue-purple gradient action button.

Tapping it opens a beautiful creation menu.

Use safe-area-aware placement and modern SwiftUI transitions.

## 5. Secure Vault screen

Reproduce the secure vault screen in the lower section of the reference image.

Create a premium secure storage dashboard with:

- Large violet lock symbol
- Protection information banner
- Beautiful folder cards
- New secure folder button
- Search and sort
- Secure document preview

Default organizational categories:

- ID Documents
- Bank Statements
- Medical Records
- Private Notes

Security requirements:

- Face ID / Touch ID authentication where supported
- Secure access controls
- Appropriate lock-on-background behavior
- Encryption using appropriate Apple security APIs
- Never expose private thumbnails while locked
- Do not store sensitive documents unencrypted
- Do not advertise encryption that is not actually implemented

Reuse existing security architecture if available.

## 6. VPN screen

Recreate the VPN screen from the reference.

Design a premium security dashboard featuring:

- Large glowing shield/globe illustration
- Connection status heading
- Large connect/disconnect control
- Selected server/location card
- Country flag
- Security status indicators
- Connection information
- Settings icon

Support visually distinct states:
- Disconnected
- Connecting
- Connected
- Disconnecting
- Error

Use smooth state transitions.

IMPORTANT: Inspect existing VPN services first. If no real VPN implementation exists, build the polished UI and a clearly separated integration layer without pretending VPN traffic is protected. Do not claim a connection is encrypted or the user's IP is hidden unless verified through an actual VPN service.

Use Apple's Network Extension APIs only when appropriate entitlements and a real supported VPN configuration are available.

## 7. Additional feature screens

Follow the same design system for the other features.

**Notes:** Modern rich-text note editor, formatting tools, attachments, handwriting integration where supported, and folder organization.

**Documents:** Grid/list switching, file previews, PDF opening, sorting, searching, and contextual actions.

**Scan & OCR:** Premium live camera interface, document-edge detection, perspective correction, image enhancement, multipage scanning, OCR, and PDF saving using supported Apple frameworks.

**Folders:** Color-coded folders, item counts, sorting, and elegant nested navigation.

**Collaboration:** Shared documents, avatars, invitation controls, comments, and collaboration activity, integrated with existing services.

Keep all existing functionality connected and operational.

## 8. iPadOS layout

Create a dedicated adaptive iPad experience.

Use:
- Sidebar-based navigation
- Multi-column document browser
- Spacious dashboard
- Larger preview cards
- Appropriate landscape/portrait adaptations
- Apple Pencil integration where existing architecture supports it
- Native multitasking compatibility

Do not simply stretch the iPhone interface.

## 9. Architecture

Build reusable SwiftUI components such as:

- `PaperNestDesignSystem`
- `PaperNestSidebar`
- `DashboardView`
- `QuickActionCard`
- `RecentDocumentCard`
- `GlobalSearchBar`
- `FolderCard`
- `VaultDashboardView`
- `VPNDashboardView`
- `VPNStatusCard`
- `PaperNestTabBar`
- `DocumentPreviewCard`

Adapt names and structure to existing project conventions. Avoid duplicating components that already exist.

Maintain clean separation between:
- UI presentation
- Navigation
- Application state
- Persistence
- Security
- VPN integration
- Existing business logic

Centralize colors, typography, spacing, radii, and shadows.

## 10. Animation and interaction

Add tasteful animations:

- Cards gently lift on hover
- Buttons have subtle spring feedback
- Tabs transition smoothly
- Sheets animate elegantly
- Grid items load naturally
- Search presents smoothly
- Vault locking/unlocking has premium visual feedback
- VPN connection status uses restrained animated feedback

Respect Reduce Motion and accessibility preferences.

Target fluid performance on supported Apple devices.

## 11. Pixel-level visual validation

This is extremely important.

Do not stop after producing a basic functional layout.

Compare the implemented UI to the supplied reference image.

Pay attention to:
- Exact visual hierarchy
- Relative spacing
- Card dimensions
- Icon sizes
- Icon background gradients
- Border radii
- Shadows
- Typography weights
- Overall color harmony
- Alignment
- Document grid density
- Sidebar proportions
- Mobile bottom bar placement

Iterate until the implementation visually matches the supplied reference as closely as practical.

Use screenshots from simulators and previews when available for visual comparison.

## 12. Existing feature preservation

Before changing code:

1. Inventory the existing app architecture.
2. Identify all functional screens.
3. Record important data flows and dependencies.
4. Make a concise implementation plan.
5. Implement the redesign incrementally.
6. Preserve current data and app functionality.
7. Run builds and fix compiler errors.
8. Verify navigation and major actions.
9. Add or update relevant UI tests.
10. Document any remaining blockers.

Do not arbitrarily delete existing code, migrations, storage logic, or features.

Do not introduce third-party dependencies unless there is a clear need and no appropriate built-in solution.

## 13. Definition of done

The task is complete when:

- The Mac UI closely matches the reference.
- The iPhone UI closely matches the reference.
- iPad has a tailored responsive layout.
- Vault and VPN are visible and properly integrated.
- The navigation works.
- Existing functionality is preserved.
- The design works in light and dark mode.
- The UI adapts to Dynamic Type and accessibility settings.
- The project builds successfully for all configured supported platforms, or remaining platform-specific blockers are explicitly reported.
- There are no unexplained placeholder actions or falsely represented security states.

## FINAL INSTRUCTION

**Do not just describe the UI. Actually modify the Paper NEST project files and implement this design.**

Begin by inspecting the repository and the reference image.

Work methodically, implement components, validate the results, and continue until the requested redesign is complete or a genuine technical blocker prevents further work.

My highest priority is reproducing the visual quality and layout of the reference while preserving the existing app's functionality.
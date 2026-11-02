# Premium reference implementation

## Inventory
RootView owns adaptive NavigationSplitView; LibraryModel holds per-window scopes, navigation, import and sidebar summaries. LibraryView supplies grid/list, search, batch actions, context menus and disposable file previews. LibraryPresentations owns scanner/importer/settings/tools. NotebookCreationSheet creates actual store-backed notebooks. DocumentView owns existing annotation, PencilKit, OCR and export workflows. LibrarySession publishes committed changes; LibraryStore remains sole metadata authority. Theme and ItemCell are the shared visual seams. No vault, VPN, identity/avatar, rich text or collaboration backend exists. Do not invent those states or alter Claude’s core/export work.

## Sequence
1. Centralize reference colors, materials, radii and motion-aware card interaction.
2. Replace home content with functional dashboard: gradient phone header, creation shortcuts, real recent rows; wide dashboard with greeting and thumbnail grid. Keep existing sidebar/library flows and identifiers.
3. Owner clarification: omit Vault and VPN for this version. Do not add pretend Shared/accounts, sample locations, fake folders or sensitive file ingestion.
4. Apply matching cards/sidebar/library surfaces without changing document actions. Localize every new string in en/fr/es.
5. Run bounded units, Mac build and targeted iPhone/iPad navigation/screenshots. Inspect screenshots against reference; record failures and genuine service/device blockers.

## Existing audit debt
Previous polish: 360 units and Mac passed; localized phone/iPad annotation flows passed. iPad automated audit still fails Dynamic Type/Style contrast/comment clipping. Final maximum-type run failed after thick-width tap dismissed the sheet; investigate test hit targeting before declaring that flow passed. No native Mac/VoiceOver/device camera verification available. Logs: /private/tmp/papernest-polish-*.log.

## Acceptance
Real library items open; creation/import/folder actions work; no fabricated security state; localized labels fit, desktop and phone differ appropriately; no compiler warnings. Service integration and real-device checks are explicit blockers rather than claimed complete.

Owner clarification 2026-10-27: leave Vault and VPN for the next version. They are omitted from current navigation/actions; no status placeholders ship. Shared collaboration also lacks a service. No invented profiles or default folders are added.

## Checkpoint — 2026-10-27

UI implementation and localization are saved, uncommitted. Latest full units411 pass, Mac build clean. Localized real notebook creation, library navigation, folder creation, iPad same-scope return/search and largest-type home interactions passed. Screenshots inspected. **Still open:** iPad rotation request does not change the app window to landscape; wide sidebar Documents hyphenates at largest type; native Mac interaction, VoiceOver and real camera need tools/device. Prior annotation audit failures remain. See TEST_MATRIX for logs and exact scope. Do not mistake this for completion of rich text, collaboration, profiles or the entire reference brief. Next work should diagnose orientation/window sizing and remaining accessibility findings before adding feature surfaces. All files released; nothing staged or committed.

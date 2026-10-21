# Product spec

The brief is `CLAUDE_CODE_PROMPT.md`. This file records how features behave and the product decisions made while building them. A status label marks anything not yet built.

## Positioning

PaperNest is a scanner and notebook for people who capture paper on iPhone, organize and annotate on iPad, and finish on Mac. The priorities are scan quality, reliable storage, responsive writing, simple navigation and honest behavior. Matching every feature of Adobe Scan, CamScanner or Goodnotes is not a launch goal. The branding and interface are original.

Launch markets are the United States and Canada. English, French and Spanish ship together on all three platforms.

## Library

- An item is a **document** (scans and imports) or a **notebook** (written pages; may mix in scans and PDF pages).
- Items have a name, an optional folder, a favorite flag and dates. Tags exist in the data model but have no UI yet.
- Names never collide within a folder. A second "Receipt" becomes "Receipt 2". The comparison ignores case and accents, so "Résumé" and "resume" count as the same name.
- Sidebar scopes are All Documents, Favorites and Recently Deleted. Folder UI is planned.
- **Recently Deleted:** deleting moves an item there. It stays recoverable for **30 days**, then is purged at the next launch after expiry. Delete Permanently asks for confirmation. Originals shared with another item are kept.
- **Search:** titles, matched by word prefix and ignoring accents ("releve" finds "Relevé"). OCR text and typed notes will be added to the same index in M4. Handwriting is not searchable and is never described as searchable.

## Import

- Supported types are PDF, JPEG and PNG. The type is detected from the file's bytes, not its extension.
- PDFs stay vector PDFs. Pages are never rasterized on import, so text stays selectable.
- **Password-protected PDFs:** the user is asked for the password, and a wrong password can be retried. After unlocking, the library keeps an unlocked copy and the password is never stored. The prompt tells the user this.
- **PDFs with author restrictions** (copying or printing disabled) are declined with an explanation. Export would otherwise remove the author's restrictions.
- Damaged, truncated, empty, unreadable and unsupported files are rejected with a per-file reason. In a batch import the other files still import.
- Duplicate content is stored once, but each import creates its own item.
- Images are stored upright by applying their EXIF orientation. When an image carries no trustworthy resolution (phone cameras write 72 dpi), its page is sized so the long edge is 11 in.
- Mac: File > Import (⌘O), drag and drop onto the library, and Edit > Paste (files, PDF, PNG and TIFF; TIFF is converted to PNG). Continuity Camera import is planned.
- iPhone/iPad: the VisionKit document camera handles automatic and manual capture, edge detection, perspective correction and multi-page sessions. Unsupported devices see a disabled Scan button and can still import. *Status: implemented, not compiled.*

## Page editing (non-destructive)

- Rotate left or right, Grayscale, Black & White (automatic global threshold), brightness, contrast, and Revert to Original.
- Reorder by dragging thumbnails or with ⌥⌘↑/↓. Delete pages. Add pages from files after the selected page.
- Every edit can be undone and redone, and is saved before it appears in the UI. The original file is never changed, and the history of previous transforms is kept.
- Deleted pages can be restored with Undo until the app quits. They are removed permanently at the next launch.
- **Crop:** a rectangle drawn over the page as it is shown (rotated, uncropped), with corner and edge handles, drag-to-move, a thirds guide and Reset. It's stored relative to the original, so it stays right if the page is rotated later, and export matches the editor. Crops smaller than 5% of a side aren't possible. Mac: Page > Crop… (⌘K) and the toolbar; iPhone: the bottom toolbar. Undoable like every edit. VoiceOver reads the crop as "70% wide by 75% tall" and offers Reset. Resizing with VoiceOver isn't supported yet.
- Rescan is planned (M1 remainder).

## Export

Export never changes the library. Users choose the format, the pages (all, current or a range) and the format's options, then save with the system save panel or share.

- **PDF:** pages appear in the order shown. Imported PDF pages keep their vector content and selectable text. Pages with a filter are exported as images. Paper size can be Original, US Letter or A4. Content is always scaled to fit and **never cropped**, and the paper turns to match landscape pages. Image quality is Best (lossless), Balanced (JPEG, up to 300 dpi) or Smaller File (JPEG, up to 150 dpi). The final file size is shown after export. No target file size is promised.
- **JPEG/PNG:** one image per page at 72, 150, 200 or 300 dpi, with adjustable JPEG quality. Pages are rendered onto white, so dark ink on transparent originals survives JPEG export. Multiple pages go into a ZIP or separate files, named `Name-001.jpg` and so on in page order.
- Characters that are unsafe in filenames are replaced. Empty names fall back to "Document".
- Planned: TXT (M4), basic DOCX in an editable-text variant and a page-images variant (M4), and searchable PDF (M4).
- Known limitation: links, form fields and annotations inside imported PDFs are not guaranteed to survive export.

## Free and Pro (to be built in M5)

Pro is one subscription covering iPhone, iPad and Mac (universal purchase). Prices are configured in App Store Connect and never hard-coded. The paywall displays prices supplied by StoreKit.

| Free | Pro |
|---|---|
| Unlimited local scans and imports | Everything in Free |
| Crop, rotate, basic filters | Batch OCR and searchable PDF |
| PDF/JPEG/PNG export, no watermark | TXT and basic DOCX export |
| All three interface languages | Advanced PDF tools |
| 3 notebooks (a configurable product assumption) | Unlimited notebooks |
| | Additional annotation tools |
| | iCloud sync |

Proposed launch prices (configuration proposals, not market facts): US $3.99 per month or $24.99 per year; Canada CA$5.49 per month or CA$34.99 per year. An optional introductory first annual term is US$19.99 / CA$26.99. The app shows only offers StoreKit actually returns for the customer. There is no lifetime or weekly plan.

When Pro expires, documents stay viewable and ordinary export keeps working. New premium operations stop, and nothing is deleted or locked away. A route to download existing iCloud documents remains available.

Restore Purchases and Manage Subscription are always reachable. The paywall shows the renewal price, term and offer conditions, plus links to support, privacy and terms pages. Release is blocked until those pages exist.

## Sync (to be built in M2)

Sync is optional, uses the user's private iCloud database, and needs no separate account. It is eventual, never instantaneous. Edits work offline. Unmergeable concurrent edits produce a conflict copy instead of silently overwriting. It uses the user's own iCloud storage, never "unlimited" storage. Sync is not a backup, and export remains the backup path.

## Privacy

Documents are processed on the device. There are no ads, no tracking and no analytics SDK. Document content, images, handwriting and account identifiers are never logged. Tests and screenshots use synthetic documents. Encryption beyond the platform's file protection is not claimed.

## Reviews and feedback

The app gives nothing in exchange for ratings, and review prompts are never gated on sentiment. A private feedback channel is planned, separate from App Store reviews.

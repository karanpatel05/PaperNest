# OCR and Signature Panels Implementation Plan

**Goal:** Implement the owner-approved three-platform mockups without replacing processing or storage.
**Architecture:** New OCR selection view calls the existing DocumentModel/Vision/store pipeline with explicit page IDs and supported languages. Signature retains SignatureDraft and placement preview. Shared panel header, scrolling cards and footer adapt to inspector or sheet.
**Spec:** Owner-approved OCR and Signature sample boards in this chat, 2026-11-15.
**Tech Stack:** SwiftUI, Vision, existing LibraryStore; Swift 6.

- [x] Add tested range-selection parsing and a recognition overload accepting page IDs/languages, preserving default caller behavior and subscription enforcement.
- [x] Add OCR panel with supported-language choices, all/current/range selection, thumbnails, validation, progress and honest results; route it to wide inspector / phone sheet.
- [x] Restyle Signature with compact header, white drawing card, bordered Save and pinned Place; preserve IDs, drafts, Pro gates, positioning and error handling.
- [x] Localize additions in English/French/Spanish, run focused workflow/localization tests, build Mac/iOS and exercise panels via XCUITest.
- [x] Record actual results in TEST_MATRIX and release claims.

Review focus: invalid/out-of-bounds/empty ranges; zero language selection; selecting only requested pages; duplicate recognition requests; saved signature re-selection/placement and retained drafts on write failure. No data migrations or new stores. No changes to the product brief.

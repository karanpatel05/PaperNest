# Spacious Home Implementation Plan

**Goal:** Apply the approved Home samples to iPhone, iPad and Mac, using Option A as stated in chat.
**Architecture:** Reuse DashboardView, existing Home components and LibraryModel/store-backed data. Keep navigation and Profile sheets. Search submits to the existing library search. No persistence or subscription changes.
**Tech Stack:** SwiftUI, Swift 6, existing semantic Theme and L10n.
**Spec:** Owner approved the Home comparison and dedicated iPad board in this chat. Spacious A: one greeting, actual brand in sidebar/phone header, profile top right, search, compact actions, recent previews, folder cards. Retain phone Home/Notes/Scan/Files tabs, iPad Scan action, no Scan on Mac, no Tools hub or mock data.

- [x] Restyle header/search/actions and responsive recent/folder cards; preserve context actions.
- [x] Add localized search labels and UI regression for search, profile, real recent content and folder navigation.
- [x] Build Mac/iOS, run focused tests and native/simulator interaction checks.
- [x] Record results and release file claims.

Review: long names and empty library, wide/narrow windows, accessibility text, en/fr/es, search destination scope, no duplicated brand/title, no fake folders or account data. Existing library retains its table, sorting and selection behavior.

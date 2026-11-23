import Foundation
import Observation
import PaperNestCore
import PaperNestStore
import PaperNestSync
import SwiftUI

/// The open document's bookmarks, as the editor shows and changes them.
///
/// The library is the authority: every change here is a store call that has
/// committed before the list on screen moves, and the list is always read
/// back from the store rather than patched in memory.
@MainActor @Observable
final class ReaderBookmarks {
    private(set) var bookmarks: [Bookmark] = []
    var isShowingList = false
    /// Set when a change could not be saved.
    var isShowingFailure = false

    @ObservationIgnored private var itemID: ItemID?
    @ObservationIgnored private var session: LibrarySession?
    private var store: LibraryStore? { session?.environment?.store }

    /// Says which document this is for. Done once the editor is on screen,
    /// so the editor can own the model before it knows its own session.
    func attach(to itemID: ItemID, in session: LibrarySession) {
        self.itemID = itemID
        self.session = session
    }

    func bookmark(on pageID: PageID?) -> Bookmark? {
        guard let pageID else { return nil }
        return bookmarks.first { $0.pageID == pageID }
    }

    func isBookmarked(_ pageID: PageID?) -> Bool { bookmark(on: pageID) != nil }

    /// What a bookmark is called: the name it was given, or its page's
    /// number as the pages stand now.
    static func title(of bookmark: Bookmark, in pages: [Page]) -> String {
        if !bookmark.name.isEmpty { return bookmark.name }
        return pageTitle(of: bookmark, in: pages) ?? ""
    }

    /// "Page 3", from where the bookmark's page is now. Nil if it is gone.
    static func pageTitle(of bookmark: Bookmark, in pages: [Page]) -> String? {
        pages.firstIndex { $0.id == bookmark.pageID }.map { L10n.bookmarkPage($0 + 1) }
    }

    /// Reads the bookmarks as they are saved.
    ///
    /// Only a list that differs is published. This runs every time anything
    /// in the library changes, and the title menu is drawn from the list: an
    /// unchanged list handed over again would rebuild the navigation bar for
    /// nothing, each time, starting with the moment the document opens.
    func load() async {
        guard let store, let itemID else { return }
        if let saved = try? await store.bookmarks(of: itemID), saved != bookmarks { bookmarks = saved }
    }

    /// Marks the page, or takes its mark away if it has one.
    func toggle(on pageID: PageID?) async {
        guard let pageID else { return }
        if let existing = bookmark(on: pageID) {
            await remove(existing)
        } else {
            await change { try await $0.addBookmark(on: pageID) }
        }
    }

    func rename(_ bookmark: Bookmark, to name: String) async {
        await change { try await $0.renameBookmark(bookmark.id, to: name) }
    }

    func remove(_ bookmark: Bookmark) async {
        await change { try await $0.removeBookmark(bookmark.id) }
    }

    /// One saved change: the store first, then what is on screen, then every
    /// other window showing this document.
    private func change(_ body: (LibraryStore) async throws -> Void) async {
        guard let store else { return }
        do {
            try await body(store)
        } catch {
            isShowingFailure = true
        }
        await load()
        session?.didChange()
    }
}

// MARK: - Reaching the bookmarks from the menu bar

struct ReaderBookmarksKey: FocusedValueKey {
    typealias Value = ReaderBookmarks
}

extension FocusedValues {
    /// The focused document's bookmarks, for the Page menu.
    var readerBookmarks: ReaderBookmarks? {
        get { self[ReaderBookmarksKey.self] }
        set { self[ReaderBookmarksKey.self] = newValue }
    }
}

extension EnvironmentValues {
    /// The bookmarks of the document being read, for the mark on its pages.
    @Entry var readerBookmarks: ReaderBookmarks?
}

// MARK: - In the editor

extension View {
    /// Keeps the bookmarks current, and presents their list and any failure.
    func documentBookmarks(_ bookmarks: ReaderBookmarks, model: DocumentModel,
                           select: @escaping (PageID) -> Void) -> some View {
        modifier(DocumentBookmarksPresentation(bookmarks: bookmarks, model: model, select: select))
    }
}

private struct DocumentBookmarksPresentation: ViewModifier {
    @Bindable var bookmarks: ReaderBookmarks
    let model: DocumentModel
    let select: (PageID) -> Void

    func body(content: Content) -> some View {
        content
            .environment(\.readerBookmarks, bookmarks)
            // Read again after every committed change, in this window or
            // another: a deleted page takes its bookmark out of the list.
            .task(id: model.session.changeToken) {
                bookmarks.attach(to: model.itemID, in: model.session)
                await bookmarks.load()
            }
            .sheet(isPresented: $bookmarks.isShowingList) {
                BookmarksSheet(bookmarks: bookmarks, model: model, select: select)
            }
            .alert(L10n.genericErrorTitle, isPresented: $bookmarks.isShowingFailure) {
                Button(L10n.ok, role: .cancel) {}
            } message: {
                Text(L10n.bookmarkFailed)
            }
    }
}

/// The title menu's two entries: mark this page, and see every mark.
struct BookmarkMenuItems: View {
    let bookmarks: ReaderBookmarks
    let model: DocumentModel
    /// Runs an action once anything being typed on the page is finished.
    let finishThen: (@escaping () -> Void) -> Void

    var body: some View {
        let marked = bookmarks.isBookmarked(model.selectedPageID)
        Button {
            let page = model.selectedPageID
            finishThen { Task { await bookmarks.toggle(on: page) } }
        } label: {
            Label(marked ? L10n.bookmarkRemove : L10n.bookmarkAdd, systemImage: marked ? "bookmark.slash" : "bookmark")
        }
        .disabled(model.selectedPage == nil)
        Button { finishThen { bookmarks.isShowingList = true } } label: {
            Label(L10n.bookmarkList, systemImage: "book")
        }
        .disabled(model.pages.isEmpty)
    }
}

/// The mark on a bookmarked page: a ribbon at its top corner. It takes no
/// touches, so it is never in the way of a pen or a selection.
struct PageBookmarkRibbon: View {
    let pageID: PageID
    @Environment(\.readerBookmarks) private var bookmarks

    var body: some View {
        if bookmarks?.isBookmarked(pageID) == true {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 26))
                .foregroundStyle(Color(.sRGB, red: 0.86, green: 0.2, blue: 0.22))
                .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                .padding(.trailing, 14)
                .offset(y: -3)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityLabel(L10n.bookmarkMarked)
                .accessibilityIdentifier("page-bookmark-ribbon")
        }
    }
}

// MARK: - The list

/// Every bookmark in the document: go to one, rename one, remove one, and
/// mark or unmark the page being read.
struct BookmarksSheet: View {
    @Bindable var bookmarks: ReaderBookmarks
    let model: DocumentModel
    let select: (PageID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var renaming: Bookmark?
    @State private var renameText = ""

    private var isRenaming: Binding<Bool> {
        Binding { renaming != nil } set: { if !$0 { renaming = nil } }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L10n.bookmarkTitle)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { toggleCurrent }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.done) { dismiss() }
                            .accessibilityIdentifier("bookmarks-done")
                    }
                }
        }
        // Bookmarks are the one thing in the library iCloud is not sent. With
        // sync on, the list says so rather than letting it be assumed.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.session.sync?.isEnabled == true {
                Text(L10n.bookmarkLocalOnly)
                    .font(.app(.footnote)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
                    .accessibilityIdentifier("bookmarks-local-only")
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, idealWidth: 420, minHeight: 320, idealHeight: 420)
        #endif
        .alert(L10n.bookmarkRenameTitle, isPresented: isRenaming, presenting: renaming) { bookmark in
            TextField(L10n.renamePlaceholder, text: $renameText)
            Button(L10n.cancel, role: .cancel) {}
            Button(L10n.ok) {
                let name = renameText
                Task { await bookmarks.rename(bookmark, to: name) }
            }
        } message: { _ in
            Text(L10n.bookmarkRenameMessage)
        }
    }

    /// Marks or unmarks the page being read, from inside the list.
    private var toggleCurrent: some View {
        let marked = bookmarks.isBookmarked(model.selectedPageID)
        return Button {
            let page = model.selectedPageID
            Task { await bookmarks.toggle(on: page) }
        } label: {
            Label(marked ? L10n.bookmarkRemove : L10n.bookmarkAdd, systemImage: marked ? "bookmark.fill" : "bookmark")
        }
        .disabled(model.selectedPage == nil)
        .accessibilityIdentifier("bookmarks-toggle-current")
        .accessibilityValue(marked ? L10n.selectionOn : L10n.selectionOff)
    }

    @ViewBuilder
    private var content: some View {
        if bookmarks.bookmarks.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "bookmark").font(.largeTitle).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(L10n.bookmarkEmpty).font(.app(.headline))
                Text(L10n.bookmarkEmptyDetail)
                    .font(.app(.subheadline)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("bookmarks-empty")
        } else {
            List {
                ForEach(Array(bookmarks.bookmarks.enumerated()), id: \.element.id) { index, bookmark in
                    row(bookmark, at: index)
                }
            }
        }
    }

    private func row(_ bookmark: Bookmark, at index: Int) -> some View {
        let title = ReaderBookmarks.title(of: bookmark, in: model.pages)
        let page = ReaderBookmarks.pageTitle(of: bookmark, in: model.pages)
        return HStack(spacing: 8) {
            Button {
                select(bookmark.pageID)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "bookmark.fill").foregroundStyle(Theme.accent).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: title).multilineTextAlignment(.leading)
                        if !bookmark.name.isEmpty, let page {
                            Text(verbatim: page).font(.app(.caption)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("bookmark-row-\(index)")
            .accessibilityLabel(title)
            .accessibilityValue(page ?? "")
            Menu {
                Button {
                    renameText = bookmark.name
                    renaming = bookmark
                } label: { Label(L10n.rename, systemImage: "pencil") }
                Button(role: .destructive) {
                    Task { await bookmarks.remove(bookmark) }
                } label: { Label(L10n.bookmarkRemove, systemImage: "bookmark.slash") }
            } label: {
                Image(systemName: "ellipsis.circle").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            #if os(macOS)
            // A Mac draws a menu as a bordered pull-down with an arrow by
            // default, which is a lot of button for one small glyph per row.
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            #endif
            .accessibilityLabel(L10n.bookmarkActions(title))
            .accessibilityIdentifier("bookmark-row-menu-\(index)")
        }
        #if os(iOS)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await bookmarks.remove(bookmark) }
            } label: { Label(L10n.bookmarkRemove, systemImage: "bookmark.slash") }
        }
        #endif
    }
}

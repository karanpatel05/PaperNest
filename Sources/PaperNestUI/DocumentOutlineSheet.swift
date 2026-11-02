import PaperNestCore
import PaperNestRender
import SwiftUI

/// A document's own table of contents, for jumping to a section.
///
/// **Read from the file, not built here.** `PageRenderer.outline(for:)` gathers
/// what the PDF itself declares and drops any entry whose page is gone, so an
/// entry points at a page the document still shows. Entries keep the author's
/// order and nesting, which means a reordered document's contents will not
/// ascend — that is a true description of the file rather than a re-sort, and
/// inventing an order here would be a worse answer than the real one.
struct DocumentOutlineSheet: View {
    /// The document itself rather than a copy of its pages.
    ///
    /// Taking `[Page]` at construction looked simpler and was wrong: SwiftUI
    /// builds a sheet's content when it is presented, so a sheet opened before
    /// the document's pages had loaded kept an empty snapshot and reported
    /// "no contents" for a document that plainly has some. Found by opening it
    /// through the `-PaperNestDebugShowOutline` hook, which gets there first.
    let model: DocumentModel
    let select: (PageID) -> Void

    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [DocumentOutlineEntry]?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L10n.outline)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.done) { dismiss() }
                            .accessibilityIdentifier("outline-done")
                    }
                }
                // Keyed on the page count so a document still
                // loading is read again once its pages arrive.
                .task(id: model.pages.count) { await load() }
        }
        #if os(macOS)
        .frame(minWidth: 380, idealWidth: 420, minHeight: 320, idealHeight: 420)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if let entries {
            if entries.isEmpty {
                // Carrying no contents is something a file simply is, not a
                // fault — and a file that could not be read says the same
                // rather than having an outline invented for it.
                Text(L10n.outlineEmpty)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .accessibilityIdentifier("outline-empty")
            } else {
                List {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        Button {
                            if let pageID = Self.pageToSelect(entry, in: model.pages) { select(pageID) }
                            dismiss()
                        } label: {
                            Text(entry.title)
                                .multilineTextAlignment(.leading)
                                // The nesting the file declares, held to a few
                                // steps so a deeply nested heading keeps a
                                // readable text width on a phone.
                                .padding(.leading, CGFloat(min(entry.depth, 4)) * 14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityIdentifier("outline-entry-\(index)")
                        .accessibilityValue(entry.title)
                    }
                }
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }

    /// The page an entry should open, or nil when it is no longer there.
    ///
    /// The engine drops entries for deleted pages as it reads the outline, but
    /// this sheet holds what it read. A page deleted while the sheet is open
    /// would otherwise select an id the document no longer has, leaving the
    /// editor showing nothing at all.
    nonisolated static func pageToSelect(_ entry: DocumentOutlineEntry, in pages: [Page]) -> PageID? {
        pages.contains { $0.id == entry.pageID } ? entry.pageID : nil
    }

    private func load() async {
        guard let renderer = session.environment?.renderer else {
            entries = []
            return
        }
        // A file this cannot read has no contents to show, which is the same
        // answer as a file that carries none; neither is worth an alert over a
        // view whose whole job is navigation.
        entries = (try? await renderer.outline(for: model.pages)) ?? []
    }
}

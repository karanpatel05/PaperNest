import CoreGraphics
import Foundation
import PaperNestCore
import PaperNestStore

/// What a redaction actually did, including the part a caller must not
/// paper over.
public struct RedactionOutcome: Sendable {
    /// The page as it now stands: the redacted picture, in its old place.
    public let page: Page
    /// The original the page used to show, or nil for a page that had none.
    public let previousOriginal: AssetID?
    /// **True is the unsafe answer.** Assets are content-addressed, so two
    /// pages of identical paper share one file; when another page still shows
    /// it, the original cannot be deleted and the redacted words remain
    /// reachable through that other page. Named this way round on purpose: a
    /// caller has to look at it before telling anyone the content is gone.
    public let originalStillInLibrary: Bool
    /// How many marks drawn over the areas were removed with it.
    public let removedMarks: Int
}

/// Redacting a page, as one operation.
///
/// The steps are not separable in practice. Rendering alone leaves the
/// original sitting in the library; replacing the content alone leaves the
/// recognised words in `page_recognition`; forgetting the undo history alone
/// leaves the file on disk. This exists so a caller cannot do three of the
/// four and believe the job is done.
///
/// Marks are a fifth step. Ink, text boxes and placed pictures live in their own
/// rows and are drawn over the flattened picture, on screen and in every
/// export, and a text box's words answer searches; a mark over a black area
/// shows what was redacted. The caller passes the ones to remove
/// (`PageRedactionReview.marksOverlapping` finds them) and they go in this same
/// operation. Private comments are never drawn or exported, and stay.
///
/// It still does not scrub the disk: deleting a file unlinks it, and the bytes
/// may persist until overwritten. Nor does it reach copies already synced to
/// iCloud: deleting an asset here only cancels an upload not yet made.
public struct PageRedactor: Sendable {
    private let store: LibraryStore
    private let renderer: PageRenderer

    public init(store: LibraryStore, renderer: PageRenderer) {
        self.store = store
        self.renderer = renderer
    }

    public func redact(_ page: Page, rectangles: [NormalizedRect], removingMarks marks: [PageObject] = [],
                       dpi: CGFloat = PageRedaction.defaultDPI) async throws -> RedactionOutcome {
        // The redacted page is a new picture with no author's limits on it,
        // and every later export would treat it as free. Checked before
        // anything is drawn or written, so a refusal leaves the page as it was.
        guard try await !renderer.permissions(for: [page]).isRestricted else {
            throw RedactionError.restrictedByAuthor
        }
        let redacted = try await PageRedaction.redactedPNG(for: page, rectangles: rectangles,
                                                           renderer: renderer, dpi: dpi)
        let previous = page.content.assetID

        // The file is written durably before any row names it, as every other
        // path here does.
        let staged = try store.assets.store(redacted, kind: .png, originalFilename: nil)
        // The marks go before the paper is replaced, after the picture is
        // drawn and stored: a drawing that fails removes nothing, and a
        // redaction that is applied never leaves a mark over its black.
        let removable = marks.filter { $0.pageID == page.id }.map(\.id)
        if !removable.isEmpty {
            try await store.applyObjectChanges(on: page.id, saving: [], deleting: removable)
        }
        guard let current = try await store.page(page.id) else { throw StoreError.pageNotFound }
        // The page keeps its size and its transform: the new content is the
        // whole upright sheet as pixels, so an existing crop or rotation still
        // applies and must not be baked in a second time.
        let snapshot = LibraryStore.PageContentSnapshot(sourceSize: current.sourceSize,
                                                        content: .image(staged.id),
                                                        transform: current.transform)
        let (_, updated) = try await store.replacePageContent(page.id, with: snapshot, assets: [staged])

        // `replacePageContent` clears the page's rows from `search_index`, so
        // the words stop answering searches at once. These two go further:
        // the recognition row still physically holds them, and the undo
        // history still references the paper they were read from.
        try await store.deleteRecognition(for: page.id)
        // Details someone kept from this page are its words too.
        try await store.deleteDocumentDetails(readFrom: page.id)
        try await store.forgetReplacedContent(for: page.id)

        var stillThere = false
        if let previous, previous != staged.id {
            stillThere = try await !store.deleteAssetIfUnreferenced(previous)
        }
        return RedactionOutcome(page: updated, previousOriginal: previous,
                                originalStillInLibrary: stillThere, removedMarks: removable.count)
    }
}

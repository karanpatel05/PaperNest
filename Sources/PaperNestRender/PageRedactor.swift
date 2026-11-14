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
}

/// Redacting a page, as one operation.
///
/// The steps are not separable in practice. Rendering alone leaves the
/// original sitting in the library; replacing the content alone leaves the
/// recognised words in `page_recognition`; forgetting the undo history alone
/// leaves the file on disk. This exists so a caller cannot do three of the
/// four and believe the job is done.
///
/// It still does not scrub the disk: deleting a file unlinks it, and the bytes
/// may persist until overwritten. Nor does it touch ink, comments or stamps,
/// which live in their own rows — a note holding the redacted thing survives.
public struct PageRedactor: Sendable {
    private let store: LibraryStore
    private let renderer: PageRenderer

    public init(store: LibraryStore, renderer: PageRenderer) {
        self.store = store
        self.renderer = renderer
    }

    public func redact(_ page: Page, rectangles: [NormalizedRect],
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
        // The page keeps its size and its transform: the new content is the
        // whole upright sheet as pixels, so an existing crop or rotation still
        // applies and must not be baked in a second time.
        let snapshot = LibraryStore.PageContentSnapshot(sourceSize: page.sourceSize,
                                                        content: .image(staged.id),
                                                        transform: page.transform)
        let (_, updated) = try await store.replacePageContent(page.id, with: snapshot, assets: [staged])

        // `replacePageContent` clears the page's rows from `search_index`, so
        // the words stop answering searches at once. These two go further:
        // the recognition row still physically holds them, and the undo
        // history still references the paper they were read from.
        try await store.deleteRecognition(for: page.id)
        try await store.forgetReplacedContent(for: page.id)

        var stillThere = false
        if let previous, previous != staged.id {
            stillThere = try await !store.deleteAssetIfUnreferenced(previous)
        }
        return RedactionOutcome(page: updated, previousOriginal: previous,
                                originalStillInLibrary: stillThere)
    }
}

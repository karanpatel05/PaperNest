import CoreGraphics
import Foundation
import PaperNestCore
import PaperNestStore

/// Looks through a document for blank and repeated pages (`PageCleanup`):
/// each page read for its words and marks and drawn once, small; blank
/// candidates and look-alikes drawn again at Compare's large size to
/// confirm. Nothing is stored and nothing is deleted.
public struct PageCleanupScanner: Sendable {
    private let renderer: PageRenderer
    private let store: LibraryStore

    public init(renderer: PageRenderer, store: LibraryStore) {
        self.renderer = renderer
        self.store = store
    }

    /// `progress` is told the share done, from 0 to 1, after each page read.
    public func suggestions(for itemID: ItemID,
                            progress: @Sendable (Double) async -> Void = { _ in }) async throws -> [CleanupSuggestion] {
        let pages = try await store.pages(of: itemID)
        let bookmarked = Set(try await store.bookmarks(of: itemID).map(\.pageID))
        let detailsPage = try await store.documentDetails(of: itemID)?.pageID
        var cleanupPages: [CleanupPage] = []
        for (index, page) in pages.enumerated() {
            try Task.checkCancellation()
            let objects = try await store.objects(on: page.id)
            var attachments = Set<CleanupAttachment>()
            if objects.contains(where: { if case .comment = $0.payload { true } else { false } }) { attachments.insert(.comment) }
            if bookmarked.contains(page.id) { attachments.insert(.bookmark) }
            if detailsPage == page.id { attachments.insert(.keptDetails) }
            let marks = objects.compactMap { object -> PageObject.Payload? in
                if case .comment = object.payload { return nil }
                return object.payload
            }
            let small = try await renderer.renderThumbnail(page, maxPixelSize: DocumentComparer.pictureSide)
            guard let picture = DocumentComparer.gray(small) else { throw RenderError.contextCreationFailed }
            cleanupPages.append(CleanupPage(index: index, content: page.content, transform: page.transform, marks: marks,
                                            words: try await words(of: page), inkRatio: picture.inkRatio(),
                                            fingerprint: picture.fingerprint(), attachments: attachments))
            await progress(Double(index + 1) / Double(max(1, pages.count)))
        }

        var detailInk: [Int: Double] = [:]
        for index in PageCleanup.blankCandidates(cleanupPages) where !cleanupPages[index].isNotebookPaperPage {
            try Task.checkCancellation()
            detailInk[index] = try await DocumentComparer(renderer: renderer).detailPicture(pages[index]).inkRatio()
        }
        let blank = PageCleanup.blankSuggestions(cleanupPages, detailInk: detailInk)
        let duplicates = PageCleanup.exactDuplicates(cleanupPages)
        var similar: [CleanupSuggestion] = []
        let taken = Set((blank + duplicates).map(\.page))
        for pair in PageCleanup.similarCandidates(cleanupPages, excluding: taken) where !similar.contains(where: { $0.page == pair.page }) {
            try Task.checkCancellation()
            if pair.needsPictureCheck {
                let comparer = DocumentComparer(renderer: renderer)
                let a = try await comparer.detailPicture(pages[pair.of]), b = try await comparer.detailPicture(pages[pair.page])
                guard PictureDifference.regions(a, b, columns: max(1, a.width / DocumentComparer.cellSide)).isEmpty else { continue }
            }
            similar.append(CleanupSuggestion(page: pair.page, reason: .similar(to: pair.of), isPreselected: false,
                                             attachments: cleanupPages[pair.page].attachments))
        }
        return PageCleanup.suggestions(blank: blank, duplicates: duplicates, similar: similar)
    }

    /// The page's words when it has been read: its PDF text, or its current
    /// recognition (a completed recognition with no lines is "read, none").
    /// Notebook paper has none to read. Nil when nobody has read it.
    private func words(of page: Page) async throws -> [String]? {
        if case .template = page.content { return [] }
        let words = try await renderer.textLayout(for: page).comparisonText.words.map(\.text)
        if !words.isEmpty { return words }
        if case .pdfPage = page.content { return [] }
        guard let recognition = try await store.recognition(for: page.id), recognition.status == .completed,
              recognition.sourceRevision == page.revision else { return nil }
        return recognition.lines.flatMap { $0.text.split(whereSeparator: \.isWhitespace).map(String.init) }
    }
}

private extension CleanupPage {
    var isNotebookPaperPage: Bool { if case .template = content { true } else { false } }
}

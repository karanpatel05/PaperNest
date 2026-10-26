import Foundation
import PaperNestCore
import PaperNestStore

/// Reads the text off pages nobody has asked about, so a scan becomes
/// searchable by its contents on its own.
///
/// An actor, so launch and a later library change cannot read the same pages
/// at the same time. Recognition itself is unchanged: this walks the same
/// render → recognize → save path the manual **Recognize Text** action uses,
/// and `saveRecognition` still owns committing the result with the search
/// index and refusing to make a stale one findable.
///
/// ARCHITECTURE plans a Recognition module for Vision OCR and the search
/// index feed. This and `TextRecognizer` both belong in it. They stay here
/// because `PaperNestUI` and `PaperNestExport` already import `TextRecognizer`
/// from this module, and moving it is not this slice's work.
public actor AutomaticTextRecognizer {
    private let store: LibraryStore
    private let renderer: PageRenderer
    private let recognizer: TextRecognizer

    public init(store: LibraryStore, renderer: PageRenderer, recognizer: TextRecognizer = TextRecognizer()) {
        self.store = store
        self.renderer = renderer
        self.recognizer = recognizer
    }

    /// Reads pages that have no current result, a batch at a time, and returns
    /// how many pages it recorded.
    ///
    /// Each page is saved as it finishes, so an interrupted pass keeps what it
    /// has read and the next one resumes from the store. A page that cannot be
    /// read is recorded as failed rather than retried on every pass; a rescan
    /// or a new engine version is what gives it another attempt. When a whole
    /// batch records nothing there is no progress left to make, so this returns
    /// instead of asking again.
    @discardableResult
    public func recognizeMissing(batchSize: Int = 10) async throws -> Int {
        let languages = TextRecognizer.supportedLanguages(from: recognizer.languages)
        var recorded = 0
        while true {
            try Task.checkCancellation()
            let pages = try await store.pagesNeedingRecognition(engineVersion: TextRecognizer.engineVersion,
                                                                limit: batchSize)
            guard !pages.isEmpty else { return recorded }

            var progressed = false
            for page in pages {
                try Task.checkCancellation()
                // Recorded against the revision that was read, so a page
                // changed mid-pass is read again rather than described wrongly.
                var result = PageRecognition(pageID: page.id, sourceRevision: page.revision,
                                             engineVersion: TextRecognizer.engineVersion, status: .failed,
                                             languages: languages, lines: [])
                do {
                    guard let image = try await renderer.renderSourceForRecognition(page, pixelsPerPoint: 2) else {
                        // Nothing on the paper to read; the query already
                        // excludes these, so this is belt and braces.
                        continue
                    }
                    // Off the cooperative pool: see the note on this method.
                    result.lines = try await recognizer.recognizeOnADedicatedThread(image)
                    result.status = .completed
                } catch {
                    // Keep the failed result rather than dropping the page: it
                    // is what stops this page being read on every launch.
                }
                guard (try? await store.saveRecognition(result)) != nil else { continue }
                recorded += 1
                progressed = true
            }
            guard progressed else { return recorded }
        }
    }
}

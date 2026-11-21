import Foundation
import PaperNestCore
import PaperNestStore

/// Reads the handwriting on pages whose ink has no current reading, so what
/// someone wrote by hand can be found by search.
///
/// An actor, so two passes never read the same pages at once. Each page is
/// read from its pen strokes alone (`HandwritingRecognizer`), off the
/// cooperative pool, and saved as it finishes against the ink count read
/// before it started: if the ink changed meanwhile, `saveHandwriting` keeps
/// nothing and the page comes up again on the next pass.
public actor AutomaticHandwritingRecognizer {
    private let store: LibraryStore
    private let recognizer: HandwritingRecognizer

    public init(store: LibraryStore, recognizer: HandwritingRecognizer = HandwritingRecognizer()) {
        self.store = store
        self.recognizer = recognizer
    }

    /// Reads pages that need it, a batch at a time, and returns how many
    /// readings it kept. A page that cannot be read is kept as failed rather
    /// than retried on every pass. When a whole batch keeps nothing, every
    /// page in it changed while it was read; that is left for the next pass
    /// rather than chased now.
    @discardableResult
    public func readMissing(batchSize: Int = 10) async throws -> Int {
        let languages = TextRecognizer.supportedLanguages(from: recognizer.languages)
        var kept = 0
        while true {
            try Task.checkCancellation()
            let pages = try await store.pagesNeedingHandwriting(engineVersion: HandwritingRecognizer.engineVersion,
                                                                limit: batchSize)
            guard !pages.isEmpty else { return kept }
            var progressed = false
            for (page, generation) in pages {
                try Task.checkCancellation()
                let ink = try await store.objects(on: page.id).compactMap { object -> InkStroke? in
                    if case .ink(let stroke) = object.payload { return stroke }
                    return nil
                }
                var result = HandwritingRecognitionResult(pageID: page.id, inkGeneration: generation,
                                                          engineVersion: HandwritingRecognizer.engineVersion,
                                                          status: .failed, languages: languages, lines: [])
                do {
                    result.lines = try await recognizer.recognize(ink).map {
                        .init(text: $0.text, confidence: $0.confidence, bounds: $0.bounds)
                    }
                    result.status = .completed
                } catch {
                    // Kept as failed: it is what stops this page being read on every pass.
                }
                guard (try? await store.saveHandwriting(result)) == true else { continue }
                kept += 1
                progressed = true
            }
            guard progressed else { return kept }
        }
    }
}

import Foundation
import Testing
import PaperNestCore
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestImport
@testable import PaperNestRender

/// F4: text gets read without the user asking. Vision runs on device, so
/// these are real recognitions of synthetic pages, not stubs.
@Suite struct AutomaticTextRecognizerTests {
    private func pass(_ lib: TestLibrary) -> AutomaticTextRecognizer {
        AutomaticTextRecognizer(store: lib.store, renderer: lib.renderer)
    }

    @Test func readsAnImportedScanWithoutBeingAsked() async throws {
        let lib = try TestLibrary()
        let item = try await lib.importer.importItem(
            .data(SyntheticDocuments.textImage(lines: ["Invoice total", "Paid in full"]), name: "Receipt"))
        #expect(try await lib.store.search("invoice").isEmpty, "nothing has read the scan yet")

        let read = try await pass(lib).recognizeMissing()

        #expect(read == 1)
        #expect(try await lib.store.search("invoice") == [item.id])
        #expect(try await lib.store.search("paid") == [item.id])
    }

    @Test func leavesADigitalPDFToItsOwnWords() async throws {
        let lib = try TestLibrary()
        let item = try await lib.importer.importItem(
            .data(SyntheticDocuments.textPDF(pages: ["Council tax notice"]), name: "Notice"))
        try await EmbeddedTextIndexer(store: lib.store).indexMissing()
        let page = try await lib.store.pages(of: item.id)[0]

        let read = try await pass(lib).recognizeMissing()

        #expect(read == 0, "recognizing a raster of text we already have exactly would be worse, not better")
        #expect(try await lib.store.recognition(for: page.id) == nil)
        #expect(try await lib.store.search("council") == [item.id], "and it is still findable, through its own text")
    }

    @Test func aSecondPassHasNothingLeftToDo() async throws {
        let lib = try TestLibrary()
        _ = try await lib.importer.importItem(
            .data(SyntheticDocuments.textImage(lines: ["Meter reading"]), name: "Reading"))
        let recognizer = pass(lib)

        #expect(try await recognizer.recognizeMissing() == 1)
        #expect(try await recognizer.recognizeMissing() == 0)
    }

    @Test func aPageWithNothingPrintedOnItIsNotReadAgainAndAgain() async throws {
        let lib = try TestLibrary()
        _ = try await lib.importer.importItem(
            .data(SyntheticDocuments.image(width: 800, height: 1000, type: .png), name: "Blank"))
        let recognizer = pass(lib)

        // Looked at it, found no words: that is a finished result, not a
        // failure to retry on every launch.
        #expect(try await recognizer.recognizeMissing() == 1)
        #expect(try await recognizer.recognizeMissing() == 0)
    }

    @Test func readingAPageDoesNotMoveTheDocumentInTheLibrary() async throws {
        let lib = try TestLibrary()
        let item = try await lib.importer.importItem(
            .data(SyntheticDocuments.textImage(lines: ["Bank statement"]), name: "Statement"))

        _ = try await pass(lib).recognizeMissing()

        // Recognition is not an edit; a first-launch sweep must not reorder
        // the whole library by date.
        #expect(try await lib.store.item(item.id)?.modifiedAt == item.modifiedAt)
    }

    @Test func aRescannedPageIsReadAgainAndItsOldWordsStopMatching() async throws {
        let lib = try TestLibrary()
        let item = try await lib.importer.importItem(
            .data(SyntheticDocuments.textImage(lines: ["Invoice total"]), name: "Doc"))
        _ = try await pass(lib).recognizeMissing()
        #expect(try await lib.store.search("invoice") == [item.id])

        let page = try await lib.store.pages(of: item.id)[0]
        let replacement = try lib.store.assets.store(
            SyntheticDocuments.textImage(lines: ["Meter reading"]), kind: .png, originalFilename: "new.png")
        _ = try await lib.store.replacePageContent(page.id, with: .init(sourceSize: page.sourceSize,
                                                                        content: .image(replacement.id),
                                                                        transform: page.transform),
                                                   assets: [replacement])
        #expect(try await lib.store.search("invoice").isEmpty, "the old reading describes paper that is gone")

        #expect(try await pass(lib).recognizeMissing() == 1)
        #expect(try await lib.store.search("meter") == [item.id])
        #expect(try await lib.store.search("invoice").isEmpty)
    }

    /// Regression for a hang, not a slowdown. Vision's task queue dispatches
    /// **synchronously** while preserving its own capacity, so a recognition
    /// parks the calling thread until Vision has room. Run from an actor, that
    /// thread is one of Swift concurrency's cooperative threads, of which there
    /// is roughly one per core; several passes at once parked every one of them
    /// and the whole test target froze with five tests stuck in
    /// `semaphore_wait_trap` under `VNControlledCapacityTasksQueue`.
    ///
    /// If this regresses, the symptom is the suite hanging rather than this
    /// test reporting a failure: starvation stops the timer that would catch it.
    @Test func severalPassesAtOnceDoNotStarveTheCooperativeThreadPool() async throws {
        var libraries: [TestLibrary] = []
        // More passes than the pool has threads (8 cores here): with six,
        // two threads stayed free to service Vision and it slipped through.
        for _ in 0..<16 {
            let lib = try TestLibrary()
            _ = try await lib.importer.importItem(
                .data(SyntheticDocuments.textImage(lines: ["Invoice total"]), name: "Scan"))
            libraries.append(lib)
        }

        let read = await withTaskGroup(of: Int.self) { group in
            for lib in libraries {
                group.addTask {
                    (try? await AutomaticTextRecognizer(store: lib.store, renderer: lib.renderer)
                        .recognizeMissing()) ?? 0
                }
            }
            return await group.reduce(0, +)
        }

        #expect(read == libraries.count, "every pass has to finish, not park a thread forever")
    }
}

import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestRender
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestUI

/// F4 end to end through the real view models: a scan nobody has titled is
/// findable by a word printed on it, once its text has been read.
@MainActor
@Suite(.serialized) struct RecognitionWorkflowTests {
    let root: URL
    let libraryURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestOCR-\(UUID().uuidString)", isDirectory: true)
        libraryURL = root.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func readySession() async throws -> LibrarySession {
        let session = LibrarySession(libraryURL: libraryURL)
        await session.bootstrap()
        guard case .ready = session.state else {
            Issue.record("library did not open: \(session.state)")
            throw CancellationError()
        }
        return session
    }

    private func matches(_ library: LibraryModel, _ query: String) async -> [ItemID] {
        library.searchText = query
        await library.reload()
        return library.items.map(\.id)
    }

    @Test func aWordPrintedOnThePageFindsTheDocumentOnlyAfterRecognition() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let scan = root.appendingPathComponent("Scan.png")
        try SyntheticDocuments.textImage(lines: ["Quarterly statement", "Total 1234"]).write(to: scan)
        let session = try await readySession()
        let library = LibraryModel(session: session)
        await library.importFiles([scan])
        await library.reload()
        let id = try #require(library.items.first?.id)
        let env = try #require(session.environment)

        // The word is on the paper, not in the title, so nothing matches yet.
        #expect(await matches(library, "Quarterly").isEmpty)

        let document = DocumentModel(itemID: id, session: session)
        await document.load()
        #expect(!document.isRecognizing)
        await document.recognizeText()
        #expect(document.recognitionProgress == nil, "progress must clear when the run ends")

        #expect(await matches(library, "Quarterly") == [id])
        #expect(await matches(library, "statement") == [id])
        #expect(await matches(library, "mortgage").isEmpty)

        let page = try await env.store.pages(of: id)[0]
        let stored = try #require(try await env.store.recognition(for: page.id))
        #expect(stored.status == .completed)
        #expect(stored.engineVersion == TextRecognizer.engineVersion)
        #expect(stored.sourceRevision == page.revision)
        #expect(stored.lines.contains { $0.text.contains("Quarterly") })
        // Boxes are in the page's own space, top-left origin.
        let line = try #require(stored.lines.first { $0.text.contains("Quarterly") })
        #expect(line.box.y < 0.3 && line.box.x < 0.5)

        // It survives a relaunch, because it is in the library, not in memory.
        let reopened = try await readySession()
        let reopenedLibrary = LibraryModel(session: reopened)
        #expect(await matches(reopenedLibrary, "Quarterly") == [id])
    }

    /// Rotating or cropping does not change the words on the paper, so the
    /// text stays findable. Replacing the page's content does change them, so
    /// it must not.
    @Test func textSurvivesAnEditButNotARescanOfThePage() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let scan = root.appendingPathComponent("Scan.png")
        try SyntheticDocuments.textImage(lines: ["Tenancy agreement"]).write(to: scan)
        let session = try await readySession()
        let library = LibraryModel(session: session)
        await library.importFiles([scan])
        await library.reload()
        let id = try #require(library.items.first?.id)
        let env = try #require(session.environment)

        let document = DocumentModel(itemID: id, session: session)
        await document.load()
        await document.recognizeText()
        #expect(await matches(library, "Tenancy") == [id])

        let page = try await env.store.pages(of: id)[0]
        var transform = page.transform
        transform.rotation = .clockwise90
        _ = try await env.store.updateTransform(page.id, to: transform)
        #expect(await matches(library, "Tenancy") == [id], "rotating does not change the words on the page")

        // A rescan puts different paper on the page: the old words must go.
        let replacement = root.appendingPathComponent("Rescan.png")
        try SyntheticDocuments.textImage(lines: ["Different paper"]).write(to: replacement)
        let data = try Data(contentsOf: replacement)
        let asset = try env.store.assets.store(data, kind: .png, originalFilename: "Rescan.png")
        let snapshot = LibraryStore.PageContentSnapshot(sourceSize: CGSize(width: 1000, height: 1400),
                                                        content: .image(asset.id), transform: .identity)
        _ = try await env.store.replacePageContent(page.id, with: snapshot, assets: [asset])
        #expect(await matches(library, "Tenancy").isEmpty, "the old page's text must not survive a rescan")

        // Reading the new paper makes the new words findable.
        await document.load()
        await document.recognizeText()
        #expect(await matches(library, "Different") == [id])
        #expect(await matches(library, "Tenancy").isEmpty)
    }
}

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import PaperNestCore
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestUI

/// The cleanup screen's model: what it offers and chooses, deleting as one
/// undoable step, never every page, and copies of the document.
@MainActor @Suite(.serialized) struct CleanupModelTests {
    private func whitePage() -> Data {
        let context = CGContext(data: nil, width: 600, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// A statement, the same statement again, and a blank scan that was read.
    private func bundle() async throws -> (URL, LibrarySession, LibraryStore, ItemID) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestCleanup-\(UUID())")
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let store = try #require(session.environment?.store)
        let statement = try store.assets.store(SyntheticDocuments.textPDF(pages: ["Account statement for November, three payments"]),
                                               kind: .pdf, originalFilename: nil)
        let blank = try store.assets.store(whitePage(), kind: .png, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Bundle", pages: [
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(statement.id, index: 0)),
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(statement.id, index: 0)),
            .init(sourceSize: CGSize(width: 600, height: 800), content: .image(blank.id)),
        ], assets: [statement, blank])
        let pages = try await store.pages(of: item.id)
        try await store.saveRecognition(PageRecognition(pageID: pages[2].id, sourceRevision: pages[2].revision, engineVersion: "test",
                                                        status: .completed, languages: ["en-US"], lines: []))
        return (root, session, store, item.id)
    }

    private func ready(_ model: CleanupModel) async throws {
        for _ in 0..<200 where model.phase != .ready && model.phase != .failed { try await Task.sleep(for: .milliseconds(50)) }
        #expect(model.phase == .ready)
    }

    private func pages(_ document: DocumentModel, count: Int) async throws {
        for _ in 0..<100 where document.pages.count != count { try await Task.sleep(for: .milliseconds(50)) }
    }

    @Test func theDuplicateAndTheBlankPageAreChosenAndGoAsOneUndoableStep() async throws {
        let (root, session, _, itemID) = try await bundle()
        defer { try? FileManager.default.removeItem(at: root) }
        let document = DocumentModel(itemID: itemID, session: session)
        await document.load()
        let original = document.pages.map(\.id)
        let model = CleanupModel(document: document)

        model.look()
        try await ready(model)

        #expect(model.suggestions.map(\.reason) == [.duplicate(of: 0), .blank])
        #expect(model.selected == [1, 2], "both on strong evidence")
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        #expect(await model.deleteSelected(undoManager: undo))
        undo.endUndoGrouping()
        #expect(document.pages.map(\.id) == [original[0]])

        undo.undo()
        try await pages(document, count: 3)
        #expect(document.pages.map(\.id) == original, "every page back, in order")
        undo.redo()
        try await pages(document, count: 1)
        #expect(document.pages.map(\.id) == [original[0]])
    }

    @Test func everyPageCannotBeDeleted() async throws {
        let (root, session, store, itemID) = try await bundle()
        defer { try? FileManager.default.removeItem(at: root) }
        let document = DocumentModel(itemID: itemID, session: session)
        await document.load()
        let model = CleanupModel(document: document)
        model.look()
        try await ready(model)

        model.selected = [0, 1, 2]

        #expect(model.choosesEveryPage)
        #expect(await !model.deleteSelected(undoManager: nil))
        #expect(try await store.pages(of: itemID).count == 3)
    }

    /// A chosen page changed after the look (turned, elsewhere): nothing is
    /// deleted, the document is looked through again, and what is offered
    /// then is what the pages are now.
    @Test func aPageChangedAfterTheLookStopsTheDeletionAndIsLookedAtAgain() async throws {
        let (root, session, store, itemID) = try await bundle()
        defer { try? FileManager.default.removeItem(at: root) }
        let document = DocumentModel(itemID: itemID, session: session)
        await document.load()
        let model = CleanupModel(document: document)
        model.look()
        try await ready(model)
        #expect(model.selected == [1, 2])

        let blank = try await store.pages(of: itemID)[2]
        try await store.updateTransform(blank.id, to: PageTransform(rotation: .clockwise90))

        #expect(await !model.deleteSelected(undoManager: nil))
        #expect(model.lookedAgain)
        #expect(model.phase != .ready, "Review is off until the new look is done")
        #expect(try await store.pages(of: itemID).count == 3, "nothing deleted")

        try await ready(model)
        // Its reading was of the page before it turned: unread now, so only offered.
        #expect(model.suggestions.map(\.reason) == [.duplicate(of: 0), .looksBlank])
        #expect(model.selected == [1])
        #expect(await model.deleteSelected(undoManager: nil))
        #expect(try await store.pages(of: itemID).map(\.id).contains(blank.id), "the page that changed stays")
        #expect(try await store.pages(of: itemID).count == 2)
    }

    /// The page a duplicate was offered against is removed elsewhere after
    /// the look: deleting the duplicate now would lose that content entirely,
    /// so nothing goes and the document is looked through again.
    @Test func theCopyIsNotDeletedWhenTheOriginalWentElsewhere() async throws {
        let (root, session, store, itemID) = try await bundle()
        defer { try? FileManager.default.removeItem(at: root) }
        let document = DocumentModel(itemID: itemID, session: session)
        await document.load()
        let model = CleanupModel(document: document)
        model.look()
        try await ready(model)
        let pages = try await store.pages(of: itemID)
        model.selected = [1]

        _ = try await store.deletePages([pages[0].id])

        #expect(await !model.deleteSelected(undoManager: nil))
        #expect(model.lookedAgain)
        #expect(try await store.pages(of: itemID).map(\.id) == [pages[1].id, pages[2].id], "the last copy stays")
        try await ready(model)
        #expect(!model.suggestions.contains { $0.page == 0 }, "no longer a duplicate of anything")
    }

    @Test func anIdenticalDocumentIsOfferedAndMovedToRecentlyDeleted() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestCleanup-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let store = try #require(session.environment?.store)
        let statement = try store.assets.store(SyntheticDocuments.textPDF(pages: ["Account statement"]), kind: .pdf, originalFilename: nil)
        func make(_ name: String) async throws -> PaperNestCore.LibraryItem {
            try await store.createItem(kind: .document, name: name, pages: [
                .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(statement.id, index: 0)),
                .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(statement.id, index: 0)),
            ], assets: [statement])
        }
        let original = try await make("Statement"), copy = try await make("Statement copy")
        let document = DocumentModel(itemID: original.id, session: session)
        await document.load()
        let model = CleanupModel(document: document)
        model.look()
        try await ready(model)
        #expect(model.copies.map(\.id) == [copy.id])

        await model.moveToRecentlyDeleted(try #require(model.copies.first))

        #expect(model.copies.isEmpty)
        #expect(try await store.item(copy.id)?.isDeleted == true, "in Recently Deleted, not gone")
    }
}

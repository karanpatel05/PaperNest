import Foundation
import Testing
import UniformTypeIdentifiers
import PaperNestCore
import PaperNestTestSupport
@testable import PaperNestUI

@MainActor @Suite struct NotePhotoPlacementTests {
    @Test func photoBytesWithoutAFilenameStayOnTheChosenPage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let store = try #require(session.environment?.store)
        let id = try await LibraryModel(session: session).createNotebook(named: "Photo note", template: .blank)
        let model = DocumentModel(itemID: id, session: session)
        await model.load()
        let page = try #require(model.selectedPage)
        let bytes = SyntheticDocuments.image(width: 300, height: 150, type: .png)
        try await model.addImage(bytes, named: nil, to: page, undoManager: nil)

        let reopened = DocumentModel(itemID: id, session: session)
        await reopened.load()
        let objects = try await store.objects(on: page.id)
        #expect(objects.count == 1)
        let object = try #require(objects.first)
        guard case .image(let image) = object.payload else {
            Issue.record("Photo must remain an image object, not a new document")
            return
        }
        #expect(abs(image.frame.width / image.frame.height - 2) < 0.01)
        #expect(reopened.pages.count == 1)
    }
}

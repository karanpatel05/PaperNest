import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestImport
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestUI

/// Redacting through the document, as the Redact screen does: the review
/// writes nothing, applying removes what would show over the black, and no
/// Undo can bring a removed mark back.
@MainActor @Suite(.serialized) struct RedactionWorkflowTests {
    /// The band `textPDF`'s line of text sits in.
    private let band = NormalizedRect.exact(x: 0.05, y: 0.13, width: 0.9, height: 0.07)

    /// One statement's bytes, so a second import of them shares the original.
    private let statement = SyntheticDocuments.textPDF(pages: ["ACCOUNT 55512345"])

    private func opened() async throws -> (URL, LibrarySession, DocumentModel, LibraryStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestRedactFlow-\(UUID())")
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let store = try #require(session.environment?.store)
        let item = try await DocumentImporter(store: store).importItem(.data(statement, name: "Statement"))
        let model = DocumentModel(itemID: item.id, session: session)
        await model.load()
        return (root, session, model, store)
    }

    private func textBox(_ pageID: PageID, _ text: String, y: CGFloat, key: String) -> PageObject {
        PageObject(pageID: pageID, zKey: key,
                   payload: .text(TextBox(frame: CGRect(x: 60, y: y, width: 300, height: 30), text: text)), modifiedAt: Date())
    }

    @Test func theReviewWritesNothingAndApplyingRemovesWhatWouldShowAndClearsUndo() async throws {
        let (root, _, model, store) = try await opened()
        defer { try? FileManager.default.removeItem(at: root) }
        let pageID = try #require(model.selectedPageID)
        let over = textBox(pageID, "PIN 9921", y: 110, key: "m")
        let beside = textBox(pageID, "Filed in March", y: 600, key: "n")
        try await store.saveObject(over)
        try await store.saveObject(beside)
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        try await model.setComment(on: pageID, replacing: nil, text: "Shredded the paper copy", undoManager: undo)
        undo.endUndoGrouping()
        #expect(undo.canUndo)
        await model.load()
        let page = try #require(model.selectedPage)

        // The review: the engine's picture, the marks, the warnings. Nothing written.
        let review = try await model.redactionReview(of: page, areas: [band])
        #expect(!review.picture.isEmpty)
        #expect(review.marks.map(\.id) == [over.id])
        #expect(review.comments == 1)
        #expect(review.hasSelectableText, "a digital page: its words go everywhere on it")
        #expect(!review.originalUsedElsewhere)
        #expect(try await store.page(pageID)?.content == page.content, "reviewing changed the page")
        #expect(try await store.objects(on: pageID).count == 3, "reviewing removed a mark")

        let outcome = try await model.redact(page, areas: [band], removingMarks: review.marks, undoManager: undo)

        #expect(outcome.removedMarks == 1)
        #expect(!outcome.originalStillInLibrary)
        guard case .image = try #require(try await store.page(pageID)).content else {
            Issue.record("the page is not a picture of itself"); return
        }
        let left = try await store.objects(on: pageID)
        #expect(Set(left.map(\.id)) == [beside.id, try #require(left.first { $0.commentText != nil }).id],
                "the box beside the area and the private comment stay")
        #expect(try await store.search("9921").isEmpty)
        #expect(try await store.search("55512345").isEmpty)
        #expect(try await store.search("March").count == 1)
        // Nothing to undo: an Undo here could have put a removed mark back.
        #expect(!undo.canUndo)
        #expect(!undo.canRedo)
    }

    @Test func aDuplicatedDocumentsOriginalIsNamedBeforeAnythingIsWritten() async throws {
        let (root, session, model, store) = try await opened()
        defer { try? FileManager.default.removeItem(at: root) }
        // The same paper imported twice is stored once.
        _ = try await DocumentImporter(store: store).importItem(.data(statement, name: "Copy"))
        _ = session
        let page = try #require(model.selectedPage)

        let review = try await model.redactionReview(of: page, areas: [band])

        #expect(review.originalUsedElsewhere, "the review would let someone believe the words are gone")
    }
}

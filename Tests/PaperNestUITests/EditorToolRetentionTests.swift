import Foundation
import Testing
import PaperNestCore
import PaperNestTestSupport
@testable import PaperNestUI

@MainActor @Suite struct EditorToolRetentionTests {
    @Test func signatureDraftSurvivesReappearanceAndTabSwitch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let library = LibraryModel(session: session)
        let first = try await library.createNotebook(named: "Draft", template: .blank)
        let second = try await library.createNotebook(named: "Other", template: .blank)
        let tabs = DocumentTabs()
        #expect(await tabs.open(first, session: session, finish: { true }))
        let entry = try #require(tabs.selected)
        await entry.model.load()
        let page = try #require(entry.model.selectedPage)
        let draft = SignatureDraft(model: entry.model, page: page)
        await draft.load()
        draft.name = "Unsaved signature"
        draft.capturePoints = [.init(x: 10, y: 10), .init(x: 40, y: 30)]
        entry.signatureDrafts[page.id] = draft
        #expect(entry.hasUnsavedToolDrafts)
        #expect(await tabs.open(second, session: session, finish: { true }))
        #expect(await tabs.select(first, finish: { true }))
        let retained = try #require(tabs.selected?.signatureDrafts[page.id])
        await retained.load()
        #expect(retained === draft)
        #expect(retained.name == "Unsaved signature")
        #expect(retained.capturePoints.count == 2)
        #expect(retained.hasUnsavedChanges)
        #expect(try await session.environment?.store.signatures().isEmpty == true)
    }

    @Test func formDirtyStateAndErrorSurviveReappearance() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let env = try #require(session.environment)
        let item = try await env.importer.importItem(.data(SyntheticDocuments.acroFormPDF(), name: "Form.pdf"))
        let entry = DocumentEditorState(id: item.id, session: session)
        let form = PDFFormSession(itemID: item.id, library: session)
        entry.formSession = form
        await form.load()
        #expect(!entry.hasUnsavedToolDrafts)
        let original = form.values
        form.values["customer"] = .text("Retained customer")
        form.failed = true
        #expect(entry.hasUnsavedToolDrafts)
        await form.load()
        #expect(form.values["customer"] == .text("Retained customer"))
        #expect(form.failed)
        form.values = original
        #expect(!form.hasUnsavedChanges)
        form.name += " renamed"
        #expect(form.hasUnsavedChanges)
        form.savedName = form.name
        #expect(!form.hasUnsavedChanges)
    }
}

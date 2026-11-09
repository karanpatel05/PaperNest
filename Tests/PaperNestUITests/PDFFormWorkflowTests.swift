import Foundation
import Testing
import PaperNestCore
import PaperNestExport
import PaperNestTestSupport
@testable import PaperNestUI

@MainActor @Suite struct PDFFormWorkflowTests {
    @Test func filledCopyKeepsOriginalAndEditableFields() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FormWorkflow-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let env = try #require(session.environment)
        let source = SyntheticDocuments.acroFormPDF(fields: [.init(name: "customer"), .init(type: "Btn", name: "approved")])
        let item = try await env.importer.importItem(.data(source, name: "Form.pdf"))
        let form = PDFFormSession(itemID: item.id, library: session)
        await form.load()
        #expect(form.fields.count == 2)
        form.values["customer"] = .text("Élise García")
        form.values["approved"] = .checked(true)
        form.name = "Completed form"
        let copy = try await form.saveCopy()
        #expect(copy.id != item.id)
        #expect(copy.name == "Completed form")
        let originalPage = try #require(try await env.store.pages(of: item.id).first)
        let originalAsset = try #require(originalPage.content.assetID)
        #expect(try await env.store.assetData(originalAsset).0 == source)
        let pages = try await env.store.pages(of: copy.id)
        let output = try await env.exporter.export(itemName: copy.name, pages: pages, options: ExportOptions(includesRecognizedText: false))
        defer { output.removeTemporaryFiles() }
        let written = try Data(contentsOf: #require(output.files.first))
        let fields = try PDFForm.fields(in: written)
        #expect(fields.first { $0.name == "customer" }?.value == "Élise García")
        #expect(fields.first { $0.name == "approved" }?.value == "on")
        let reopened = PDFFormSession(itemID: copy.id, library: session)
        await reopened.load()
        #expect(reopened.values["customer"] == .text("Élise García"))
    }

    @Test func transformedDocumentDoesNotOfferOriginalFieldsAndFailureRetainsDraft() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FormRefusal-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = LibrarySession(libraryURL: root)
        await library.bootstrap()
        let env = try #require(library.environment)
        let item = try await env.importer.importItem(.data(SyntheticDocuments.acroFormPDF(), name: "Form.pdf"))
        let form = PDFFormSession(itemID: item.id, library: library)
        await form.load()
        form.values["customer"] = .text("Retained draft")
        form.values["missing field"] = .text("refuse")
        do { _ = try await form.saveCopy(); Issue.record("Expected unknown-field refusal") } catch {}
        #expect(form.values["customer"] == .text("Retained draft"))
        #expect(try await env.store.items(in: .all).count == 1)
        let page = try #require(try await env.store.pages(of: item.id).first)
        var transform = page.transform
        transform.rotation = .clockwise90
        _ = try await env.store.updateTransform(page.id, to: transform)
        let edited = PDFFormSession(itemID: item.id, library: library)
        await edited.load()
        #expect(edited.fields.isEmpty, "Never fill an untouched source while silently dropping current edits")
    }
}

import Foundation
import PDFKit
import Testing
import PaperNestCore
import PaperNestExport
import PaperNestStore
@testable import PaperNestUI

@MainActor @Suite struct NotebookCreationTests {
    @Test(arguments: PageTemplate.allCases)
    func creationPersistsTemplateFolderAndExports(_ template: PageTemplate) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let env = try #require(session.environment)
        let folder = try await env.store.createFolder(named: "Notes")
        let model = LibraryModel(session: session)
        model.sidebarSelection = .folder(folder.id)
        let id = try await model.createNotebook(named: "  Study  ", template: template)
        let reopened = try LibraryStore(directory: root)
        let item = try #require(try await reopened.item(id))
        #expect(item.kind == .notebook)
        #expect(item.name == "Study")
        #expect(item.folderID == folder.id)
        let pages = try await reopened.pages(of: id)
        #expect(pages.count == 1)
        #expect(pages[0].content == .template(template))
        #expect(pages[0].sourceSize.width > 0 && pages[0].sourceSize.height > 0)
        let output = try await env.exporter.export(itemName: item.name, pages: pages, options: ExportOptions(format: .pdf))
        defer { output.removeTemporaryFiles() }
        #expect(PDFDocument(url: output.files[0])?.pageCount == 1)
        #expect(try await reopened.integrityCheck().isEmpty)
    }
}

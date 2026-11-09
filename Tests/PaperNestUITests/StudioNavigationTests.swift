import Foundation
import Testing
import UniformTypeIdentifiers
import PaperNestCore
import PaperNestTestSupport
@testable import PaperNestUI

@MainActor @Suite struct StudioNavigationTests {
    @Test func notebookFilterAndScanReviewUseTheSameDurableLibrary() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let library = LibraryModel(session: session, startsAtHome: true)
        let notebook = try await library.createNotebook(named: "Study", template: .grid)
        let scan = SyntheticDocuments.image(width: 100, height: 150, type: .jpeg)
        await library.importImages([scan, scan], name: "Scan", openAfterSaving: true)
        let opened = try #require(library.homeDocument)
        #expect(opened != notebook)
        let document = DocumentModel(itemID: opened, session: session)
        await document.load()
        #expect(document.pages.count == 2)
        await library.reloadSidebar()
        #expect(library.dashboardItems.count == 2)
        library.contentKind = .notes
        await library.reload()
        #expect(library.items.map(\.id) == [notebook])
        library.contentKind = .documents
        await library.reload()
        #expect(library.items.map(\.id) == [opened])
        let reopened = LibrarySession(libraryURL: root)
        await reopened.bootstrap()
        let loaded = LibraryModel(session: reopened)
        await loaded.reloadSidebar()
        #expect(Set(loaded.dashboardItems.map(\.id)) == [notebook, opened])
    }

    @Test func dashboardKeepsFavoritesOutsideTheRecentTen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let model = LibraryModel(session: session)
        let favorite = try await model.createNotebook(named: "Favorite", template: .blank)
        await model.setFavorite(favorite, true)
        for index in 0..<11 { _ = try await model.createNotebook(named: "Note \(index)", template: .blank) }
        await model.reloadSidebar()
        #expect(model.recentItems.count == 10)
        #expect(model.dashboardItems.count == 12)
        #expect(model.dashboardItems.contains { $0.id == favorite && $0.item.isFavorite })
    }
}

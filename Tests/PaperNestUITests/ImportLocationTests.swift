import Foundation
import Testing
import UniformTypeIdentifiers
import PaperNestCore
import PaperNestTestSupport
@testable import PaperNestUI

@MainActor @Suite struct ImportLocationTests {
    @Test func cancelledImportWritesNothing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let model = LibraryModel(session: session, startsAtHome: true)
        let task = Task { await model.importImages([SyntheticDocuments.image(width: 30, height: 40, type: .png)], name: "Cancelled", chooseLocation: true) }
        for _ in 0..<100 where model.importLocationRequest == nil { await Task.yield() }
        #expect(model.importLocationRequest != nil)
        await model.reloadSidebar()
        #expect(model.dashboardItems.isEmpty)
        model.finishImportLocation()
        await task.value
        await model.reloadSidebar()
        #expect(model.dashboardItems.isEmpty)
        #expect(model.homeDocument == nil)
    }

    @Test func newFolderImportSavesThenOpens() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let model = LibraryModel(session: session, startsAtHome: true)
        let task = Task { await model.importImages([SyntheticDocuments.image(width: 30, height: 40, type: .png)], name: "Receipt", chooseLocation: true) }
        for _ in 0..<100 where model.importLocationRequest == nil { await Task.yield() }
        #expect(model.importLocationRequest != nil)
        model.importLocationChoice = .newFolder("Receipts")
        model.finishImportLocation()
        await task.value
        await model.reloadSidebar()
        let item = try #require(model.dashboardItems.first)
        #expect(item.item.folderID == model.folders.first?.id)
        #expect(model.folders.first?.name == "Receipts")
        #expect(model.homeDocument == item.id)
    }
    @Test func fileImportUsesChosenFolderAndWideNavigation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let model = LibraryModel(session: session)
        await model.createFolder(named: "Existing")
        let folder = try #require(model.folders.first)
        model.sidebarSelection = nil
        let file = root.appendingPathComponent("Sample.png")
        try SyntheticDocuments.image(width: 30, height: 40, type: .png).write(to: file)
        let task = Task { await model.importFiles([file], chooseLocation: true) }
        for _ in 0..<100 where model.importLocationRequest == nil { await Task.yield() }
        #expect(model.importLocationRequest != nil)
        model.importLocationChoice = .folder(folder.id)
        model.finishImportLocation()
        await task.value
        await model.reloadSidebar()
        let item = try #require(model.dashboardItems.first)
        #expect(item.item.folderID == folder.id)
        #expect(model.path == [item.id])
        #expect(model.homeDocument == nil)
    }

    @Test func rootChoiceOverridesCurrentFolderAndFailureDoesNotOpen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let model = LibraryModel(session: session)
        await model.createFolder(named: "Not the destination")
        let task = Task { await model.importPhotos([(SyntheticDocuments.image(width: 30, height: 40, type: .png), "Photo.png")], chooseLocation: true) }
        for _ in 0..<100 where model.importLocationRequest == nil { await Task.yield() }
        model.importLocationChoice = .home
        model.finishImportLocation()
        await task.value
        await model.reloadSidebar()
        #expect(model.dashboardItems.first?.item.folderID == nil)
        #expect(model.path.count == 1)
        model.path = []
        let failed = Task { await model.importImages([Data()], name: "Broken", chooseLocation: true) }
        for _ in 0..<100 where model.importLocationRequest == nil { await Task.yield() }
        model.importLocationChoice = .home
        model.finishImportLocation()
        await failed.value
        #expect(model.path.isEmpty)
        #expect(model.presentedError != nil)
    }

}

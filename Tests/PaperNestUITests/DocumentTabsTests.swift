import Foundation
import Testing
import PaperNestCore
@testable import PaperNestUI

@MainActor @Suite struct DocumentTabsTests {
    @Test func tabsDeduplicatePreserveStateAndRespectFailedFlush() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let library = LibraryModel(session: session)
        let first = try await library.createNotebook(named: "First", template: .blank)
        let second = try await library.createNotebook(named: "Second", template: .grid)
        let tabs = DocumentTabs()
        #expect(await tabs.open(first, session: session, finish: { true }))
        let entry = try #require(tabs.selected)
        await entry.model.load()
        entry.zoom = 2
        let page = entry.model.selectedPageID
        #expect(await tabs.open(second, session: session, finish: { true }))
        #expect(await tabs.open(first, session: session, finish: { true }))
        #expect(tabs.entries.count == 2)
        #expect(tabs.selected === entry)
        #expect(tabs.selected?.zoom == 2)
        #expect(tabs.selected?.model.selectedPageID == page)
        #expect(!(await tabs.select(second, finish: { false })))
        #expect(tabs.selectedID == first)
        #expect(!(await tabs.close(first, finish: { false })))
        #expect(tabs.entries.count == 2)
        let draft = SignatureDraft(model: entry.model, page: try #require(entry.model.selectedPage))
        draft.capturePoints = [.init(x: 1, y: 1), .init(x: 10, y: 12)]
        entry.signatureDrafts[try #require(entry.model.selectedPageID)] = draft
        #expect(!(await tabs.close(first, finish: { true })), "An unfinished tool draft requires explicit discard")
        entry.pageToolBusy = true
        #expect(!(await tabs.close(first, discardDrafts: true, finish: { true })))
        entry.pageToolBusy = false
        #expect(await tabs.close(first, discardDrafts: true, finish: { true }))
        #expect(tabs.selectedID == second)
        #expect(await tabs.close(second, finish: { true }))
        #expect(tabs.entries.isEmpty)
        #expect(tabs.selectedID == nil)
        #expect(try await session.environment?.store.item(first) != nil)
    }
}

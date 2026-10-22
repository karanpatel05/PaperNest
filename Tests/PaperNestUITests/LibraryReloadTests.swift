import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore
@testable import PaperNestUI

/// Blocks only this test's store actor, so a real reload crosses an await
/// while the user changes the requested scope/query or cancels the task.
private final class ReloadReadGate: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    func waitUntilEntered() -> Bool { entered.wait(timeout: .now() + 5) == .success }
}

extension LibraryStore {
    fileprivate func holdReadsForTest(_ gate: ReloadReadGate) {
        gate.entered.signal()
        _ = gate.release.wait(timeout: .now() + 10)
    }
}

@MainActor @Suite struct LibraryReloadTests {
    enum Change: CaseIterable, Sendable { case query, scope, cancellation }

    @Test(arguments: Change.allCases)
    func anOutdatedReloadCannotPublishRowsIntoANewSelection(_ change: Change) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestReload-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let store = try #require(session.environment?.store)
        let old = try await store.createItem(kind: .document, name: "Old", pages: [], assets: [])
        let fresh = try await store.createItem(kind: .document, name: "Fresh", pages: [], assets: [])
        try await store.setFavorite(fresh.id, true)
        let model = LibraryModel(session: session)
        let gate = ReloadReadGate()
        let blocker = Task.detached { await store.holdReadsForTest(gate) }
        defer { gate.release.signal() }
        #expect(await Task.detached { gate.waitUntilEntered() }.value)
        var didStart = false
        let outdated = Task { didStart = true; await model.reload() }
        while !didStart { await Task.yield() }
        switch change {
        case .query: model.searchText = "Fresh"
        case .scope: model.sidebarSelection = .favorites
        case .cancellation: outdated.cancel()
        }
        gate.release.signal()
        await blocker.value
        await outdated.value
        #expect(model.items.isEmpty, "stale result published into the new scope/query")
        #expect(!model.hasLoaded)
        await model.reload()
        #expect(model.hasLoaded)
        #expect(Set(model.items.map(\.id)) == (change == .cancellation ? [old.id, fresh.id] : [fresh.id]))
    }
}

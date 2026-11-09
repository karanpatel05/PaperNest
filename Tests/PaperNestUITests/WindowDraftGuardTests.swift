import Foundation
import Testing
import PaperNestCore
@testable import PaperNestUI

@MainActor @Suite(.serialized) struct WindowDraftGuardTests {
    @Test func inactiveDraftCancelIsNonDestructiveAndBusyRefusesClose() async throws {
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
        draft.name = "Unsaved"
        draft.capturePoints = [.init(x: 1, y: 1), .init(x: 20, y: 20)]
        entry.signatureDrafts[page.id] = draft
        #expect(await tabs.open(second, session: session, finish: { true }))
        var prompts = 0
        #expect(!(await tabs.prepareWindowClose { prompts += 1; return false }))
        #expect(prompts == 1)
        #expect(draft.capturePoints.count == 2)
        #expect(tabs.entries.count == 2)
        #expect(await tabs.prepareWindowClose { true })
        #expect(draft.capturePoints.count == 2, "Quit canceled by another window must still retain this draft")
        entry.pageToolBusy = true
        #expect(!(await tabs.prepareWindowClose { prompts += 1; return true }))
        #expect(prompts == 1)
    }

    @Test func rootCloseGuardOverridesCurrentNavigationGuard() async {
        let guardState = DocumentEditingGuard()
        var navigationCalls = 0
        guardState.finish = { navigationCalls += 1; return true }
        guardState.finishWindow = { false }
        #expect(!(await guardState.prepareToCloseWindow()))
        #expect(navigationCalls == 0)
        guardState.finishWindow = nil
        #expect(await guardState.prepareToCloseWindow())
        #expect(navigationCalls == 1)
    }

    @Test func singleCloseLocksAndRejectsReentrantPreparation() async {
        let guardState = DocumentEditingGuard()
        defer { guardState.finishWindow = nil }
        guardState.finishWindow = {
            #expect(guardState.isClosing)
            #expect(!(await guardState.prepareToCloseWindow()))
            #expect(guardState.isClosing)
            return false
        }
        #expect(!(await guardState.prepareToCloseWindow()))
        #expect(!guardState.isClosing)
    }

    #if os(macOS)
    @Test func quitFreezesAllWindowsBeforeFirstFlushAndRestoresAfterCancel() async {
        let first = DocumentEditingGuard()
        let second = DocumentEditingGuard()
        PaperNestPendingEdits.register(first)
        PaperNestPendingEdits.register(second)
        defer {
            PaperNestPendingEdits.unregister(first)
            PaperNestPendingEdits.unregister(second)
            first.finishWindow = nil
        }
        first.finishWindow = {
            #expect(first.isClosing && second.isClosing)
            await Task.yield()
            #expect(first.isClosing && second.isClosing)
            return false
        }
        #expect(!(await PaperNestPendingEdits.finishAll()))
        #expect(!first.isClosing && !second.isClosing)
    }

    @Test func quitRefusesNewWindowRegisteredDuringFlush() async {
        let first = DocumentEditingGuard()
        let newcomer = DocumentEditingGuard()
        PaperNestPendingEdits.register(first)
        defer {
            PaperNestPendingEdits.unregister(first)
            PaperNestPendingEdits.unregister(newcomer)
            first.finishWindow = nil
        }
        first.finishWindow = {
            PaperNestPendingEdits.register(newcomer)
            return true
        }
        #expect(!(await PaperNestPendingEdits.finishAll()))
        #expect(!first.isClosing && !newcomer.isClosing)
    }
    #endif

}

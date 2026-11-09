import Foundation
import Testing
import PaperNestCore
import PaperNestStore
@testable import PaperNestUI

@MainActor @Suite(.serialized) struct InlineTextSessionTests {
    @Test func placementUsesInverseGeometryAndFailedSaveRetainsDraft() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("InlineSession-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = LibrarySession(libraryURL: root)
        await library.bootstrap()
        let store = try #require(library.environment?.store)
        let item = try await store.createItem(kind: .notebook, name: "Inline", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        ], assets: [])
        let model = DocumentModel(itemID: item.id, session: library)
        await model.load()
        let page = try #require(model.selectedPage)
        let session = InlineTextSession(model: model)
        let mapping = page.geometry.sourceToPage.concatenating(CGAffineTransform(scaleX: 0.5, y: 0.5))
        session.beginNew(on: page, at: CGPoint(x: 100, y: 120), sourceToView: mapping)
        #expect(session.box?.frame.minX == 200)
        #expect(session.box?.frame.minY == 240)
        session.change { $0.text = "Exact text  " }
        #expect(await session.flush(undoManager: nil))
        let original = try #require(session.original)
        #expect(try await store.objects(on: page.id).count == 1)
        session.change { $0.text = "Keep this draft" }
        // A concurrent writer must not be overwritten, and the draft must remain available.
        _ = try await store.updateText(original, text: "Other window", frame: try #require(session.box).frame,
                                      fontSize: 18, color: .black, alignment: .leading)
        #expect(!(await session.finish(undoManager: nil)))
        #expect(session.box?.text == "Keep this draft")
        #expect(session.hasFailure)
        #expect(session.original?.id == original.id)
    }

    @Test func contextualBarStaysInsideViewportAndAvoidsBox() {
        let visible = CGRect(x: 30, y: 50, width: 320, height: 400)
        for box in [CGRect(x: 35, y: 60, width: 100, height: 60), CGRect(x: 220, y: 370, width: 100, height: 60)] {
            let bar = InlineTextLayout.toolbarFrame(box: box, visible: visible, size: CGSize(width: 300, height: 48))
            #expect(visible.contains(bar))
            #expect(!box.intersects(bar))
            if bar.minY >= box.maxY { #expect(bar.minY >= box.maxY + 38) }
        }
    }

    @Test func contextualBarRemainsReachableWhenSelectionScrollsOutsideViewport() {
        let visible = CGRect(x: 30, y: 150, width: 320, height: 260)
        for box in [CGRect(x: -80, y: -200, width: 180, height: 60),
                    CGRect(x: 500, y: 600, width: 180, height: 60)] {
            let bar = InlineTextLayout.toolbarFrame(box: box, visible: visible,
                                                   size: CGSize(width: 420, height: 100))
            #expect(visible.contains(bar))
        }
    }

    @Test func concurrentFlushWaitersPersistLatestDraftAsOneObject() async throws {
        let fixture = try await makeSession()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let session = fixture.session
        session.change { $0.text = "First snapshot" }
        let first = Task { await session.flush(undoManager: nil) }
        try await waitUntil { session.isSaving }
        // Change the actual buffer while its first snapshot is in flight, then
        // overlap the background, debounce and toolbar callers waiting on it.
        session.change { $0.text = "Latest snapshot  \n"; $0.isBold = true }
        let waiters = (0..<12).map { _ in Task { await session.flush(undoManager: nil) } }
        #expect(await first.value)
        for waiter in waiters { #expect(await waiter.value) }
        let objects = try await fixture.store.objects(on: fixture.page.id)
        #expect(objects.count == 1)
        let saved = try #require(objects.first)
        guard case .text(let box) = saved.payload else { Issue.record("not text"); return }
        #expect(box.text == "Latest snapshot  \n" && box.isBold)
        #expect(session.original == saved)
        #expect(!session.hasFailure && !session.isSaving)
    }

    @Test func concurrentFinishesCommitNativeCompositionBeforeClearingDraft() async throws {
        let fixture = try await makeSession()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let session = fixture.session
        session.change { $0.text = "Uncommitted prefix" }
        // Native adapters publish marked text through this callback before
        // their view disappears. This simulates that boundary, not an IME UI.
        session.commitNative = { session.change { $0.text = "確定した文字  "; $0.isItalic = true } }
        let first = Task { await session.finish(undoManager: nil) }
        try await waitUntil { session.isFinishing }
        let waiters = (0..<8).map { _ in Task { await session.finish(undoManager: nil) } }
        session.change { $0.text = "Late stale delegate callback" }
        session.beginNew(on: fixture.page, at: .zero, sourceToView: .identity)
        #expect(await first.value)
        for waiter in waiters { #expect(await waiter.value) }
        let objects = try await fixture.store.objects(on: fixture.page.id)
        #expect(objects.count == 1)
        guard case .text(let box) = try #require(objects.first).payload else { Issue.record("not text"); return }
        #expect(box.text == "確定した文字  " && box.isItalic)
        #expect(!session.isSelected && !session.isFinishing && !session.hasFailure)
        #expect(session.commitNative == nil)
    }

    @Test func deleteDuringPendingSaveCoalescesConcurrentTerminalRequests() async throws {
        let fixture = try await makeSession()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let session = fixture.session
        session.change { $0.text = "Do not resurrect" }
        let flush = Task { await session.flush(undoManager: nil) }
        try await waitUntil { session.isSaving }
        let deleting = Task { await session.delete(undoManager: nil) }
        try await waitUntil { session.isFinishing }
        let finishing = Task { await session.finish(undoManager: nil) }
        let deletingAgain = Task { await session.delete(undoManager: nil) }
        #expect(await flush.value)
        await deleting.value
        #expect(await finishing.value)
        await deletingAgain.value
        #expect(try await fixture.store.objects(on: fixture.page.id).isEmpty)
        #expect(!session.isSelected && !session.hasFailure && !session.isSaving && !session.isFinishing)
        // An old flush must not repopulate the original after deletion.
        #expect(session.original == nil)
    }

    @Test func backgroundFlushDeletesClearedSavedTextAndDeletionUndoes() async throws {
        let fixture = try await makeSession()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let session = fixture.session
        session.change { $0.text = "Restore this exact text  "; $0.fontFamily = .serif }
        #expect(await session.flush(undoManager: nil))
        let original = try #require(session.original)
        session.change { $0.text = "  \n" }
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        await session.commitAndFlush(undoManager: undo)
        undo.endUndoGrouping()
        #expect(try await fixture.store.objects(on: fixture.page.id).isEmpty)
        #expect(!session.isSelected && !session.hasFailure)
        #expect(undo.canUndo)
        undo.undo()
        try await settled(fixture.model)
        #expect(try await fixture.store.objects(on: fixture.page.id) == [original])
        undo.redo()
        try await settled(fixture.model)
        #expect(try await fixture.store.objects(on: fixture.page.id).isEmpty)
        #expect(fixture.model.presentedError == nil)
    }

    @Test func failedRetryRetainsDraftUntilTheOriginalConflictIsResolved() async throws {
        let fixture = try await makeSession()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let session = fixture.session
        session.change { $0.text = "Original" }
        #expect(await session.flush(undoManager: nil))
        let original = try #require(session.original)
        let frame = try #require(session.box).frame
        let (_, other) = try await fixture.store.updateText(original, text: "Other window", frame: frame,
            fontSize: 18, color: .black, alignment: .leading)
        session.change { $0.text = "Retained local draft  "; $0.isBold = true }
        #expect(!(await session.finish(undoManager: nil)))
        #expect(!(await session.flush(undoManager: nil)))
        #expect(session.box?.text == "Retained local draft  ")
        #expect(session.original == original && session.hasFailure && !session.isFinishing)
        #expect(try await fixture.store.objects(on: fixture.page.id) == [other])
        // A real guarded inverse resolves the competing edit; retry must use
        // the retained draft, rather than reloading away the user's words.
        _ = try await fixture.store.applyInkChanges(on: fixture.page.id, saving: [original], replacing: [other], deleting: [])
        #expect(await session.finish(undoManager: nil))
        let objects = try await fixture.store.objects(on: fixture.page.id)
        #expect(objects.count == 1 && objects.first?.id == original.id)
        guard case .text(let saved) = try #require(objects.first).payload else { Issue.record("not text"); return }
        #expect(saved.text == "Retained local draft  " && saved.isBold)
        #expect(!session.hasFailure && !session.isSelected)
    }

    @Test func saveAsNewPreservesConflictingObjectAndExactDraftWithIndependentUndo() async throws {
        let fixture = try await makeSession()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let session = fixture.session
        session.change { $0.text = "Original" }
        #expect(await session.flush(undoManager: nil))
        let original = try #require(session.original)
        let (_, other) = try await fixture.store.updateText(original, text: "Other window",
            frame: try #require(session.box).frame, fontSize: 18, color: .black, alignment: .leading)
        session.change {
            $0.text = "  Local draft\n"; $0.fontFamily = .serif; $0.fontSize = 23
            $0.isBold = true; $0.isItalic = true; $0.alignment = .center
            $0.frame = CGRect(x: 80, y: 90, width: 260, height: 110)
        }
        #expect(!(await session.finish(undoManager: nil)))
        session.commitNative = { session.change { $0.text = "  確定した文字\n" } }
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        let copying = Task { await session.saveAsNewBox(undoManager: undo) }
        try await waitUntil { session.isFinishing }
        let concurrentFinish = Task { await session.finish(undoManager: undo) }
        #expect(await copying.value)
        #expect(await concurrentFinish.value)
        undo.endUndoGrouping()
        let objects = try await fixture.store.objects(on: fixture.page.id)
        #expect(objects.count == 2 && objects.contains(other))
        let copy = try #require(objects.first { $0.id != original.id })
        guard case .text(let saved) = copy.payload else { Issue.record("not text"); return }
        #expect(saved.text == "  確定した文字\n")
        #expect(saved.frame == CGRect(x: 80, y: 90, width: 260, height: 110))
        #expect(saved.fontFamily == .serif && saved.fontSize == 23 && saved.isBold && saved.isItalic)
        #expect(saved.alignment == .center)
        #expect(!session.isSelected && !session.isFinishing && !session.hasFailure)
        undo.undo()
        try await settled(fixture.model)
        #expect(try await fixture.store.objects(on: fixture.page.id) == [other])
        undo.redo()
        try await settled(fixture.model)
        #expect(try await fixture.store.objects(on: fixture.page.id) == objects)
    }

    @Test func missingPageKeepsDraftAfterFailedCopyAndAllowsExplicitDiscard() async throws {
        let fixture = try await makeSession()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let session = fixture.session
        session.change { $0.text = "Keep until explicitly discarded" }
        let draft = session.box
        _ = try await fixture.store.deletePages([fixture.page.id])
        #expect(!(await session.finish(undoManager: nil)))
        #expect(!(await session.saveAsNewBox(undoManager: nil)))
        #expect(session.box == draft && session.hasFailure && !session.isFinishing)
        await session.discardDraft()
        #expect(!session.isSelected && !session.hasFailure && session.commitNative == nil)
        #expect(try await fixture.store.page(fixture.page.id) == nil)
        #expect(await session.finish(undoManager: nil))
    }

    @Test func discardConflictingDraftDoesNotChangeSavedObject() async throws {
        let fixture = try await makeSession()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let session = fixture.session
        session.change { $0.text = "Original" }
        #expect(await session.flush(undoManager: nil))
        let original = try #require(session.original)
        let (_, other) = try await fixture.store.updateText(original, text: "Other window",
            frame: try #require(session.box).frame, fontSize: 18, color: .black, alignment: .leading)
        session.change { $0.text = "Discard only these words" }
        #expect(!(await session.finish(undoManager: nil)))
        let pageBefore = try await fixture.store.page(fixture.page.id)
        await session.discardDraft()
        #expect(try await fixture.store.objects(on: fixture.page.id) == [other])
        #expect(try await fixture.store.page(fixture.page.id) == pageBefore)
        #expect(!session.isSelected && !session.hasFailure && !session.isFinishing)
        session.select(other, on: fixture.page)
        #expect(session.original == other)
    }

    @Test func discardDuringPendingSavePreventsQueuedDraftWrites() async throws {
        let fixture = try await makeSession()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let session = fixture.session
        session.change { $0.text = "Already saving" }
        let flush = Task { await session.flush(undoManager: nil) }
        try await waitUntil { session.isSaving }
        session.change { $0.text = "Never save this later draft" }
        let waiters = (0..<8).map { _ in Task { await session.flush(undoManager: nil) } }
        await session.discardDraft()
        _ = await flush.value
        for waiter in waiters { _ = await waiter.value }
        let objects = try await fixture.store.objects(on: fixture.page.id)
        #expect(objects.count == 1)
        guard case .text(let saved) = try #require(objects.first).payload else { Issue.record("not text"); return }
        #expect(saved.text == "Already saving")
        #expect(!session.isSelected && !session.isSaving && !session.isFinishing)
        #expect(session.original == nil)
    }

    private struct SessionFixture {
        let root: URL
        let library: LibrarySession
        let store: LibraryStore
        let model: DocumentModel
        let session: InlineTextSession
        let page: Page
    }

    private func makeSession() async throws -> SessionFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("InlineSession-\(UUID())")
        let library = LibrarySession(libraryURL: root)
        await library.bootstrap()
        let store = try #require(library.environment?.store)
        let item = try await store.createItem(kind: .notebook, name: "Inline", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        ], assets: [])
        let model = DocumentModel(itemID: item.id, session: library)
        await model.load()
        let page = try #require(model.selectedPage)
        let session = InlineTextSession(model: model)
        session.beginNew(on: page, at: CGPoint(x: 40, y: 60), sourceToView: .identity)
        return SessionFixture(root: root, library: library, store: store, model: model, session: session, page: page)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
        try #require(condition(), "the test must observe an in-flight operation to exercise the race")
    }

    private func settled(_ model: DocumentModel) async throws {
        for _ in 0..<150 where model.isChangingNotebookPage { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!model.isChangingNotebookPage)
    }

}

import Foundation
import Observation
import PaperNestCore
import PaperNestImport
import PaperNestRender
import PaperNestStore

/// State and edits for one open document. Every edit commits to the store
/// first; `pages` reflects only committed state, and each edit registers its
/// inverse with the window's undo manager.
@MainActor @Observable
final class DocumentModel {
    let itemID: ItemID
    let session: LibrarySession
    private(set) var item: LibraryItem?
    private(set) var pages: [Page] = []
    private(set) var hasLoaded = false
    var selectedPageID: PageID?
    var presentedError: PresentedError?
    /// Pages finished, pages in total, while text recognition runs.
    private(set) var recognitionProgress: (done: Int, total: Int)?

    init(itemID: ItemID, session: LibrarySession) {
        self.itemID = itemID
        self.session = session
    }

    private var store: LibraryStore? { session.environment?.store }

    var isRecognizing: Bool { recognitionProgress != nil }

    /// Reads the printed text on every page and saves it, which is what makes
    /// a scan findable. Each page is saved as it finishes, so a long document
    /// is useful before the last page is done, and a failure on one page does
    /// not discard the others.
    func recognizeText() async {
        guard let store, let renderer = session.environment?.renderer, recognitionProgress == nil else { return }
        let recognizer = TextRecognizer()
        let languages = TextRecognizer.supportedLanguages(from: TextRecognizer.preferredLanguages)
        let pages = self.pages
        recognitionProgress = (0, pages.count)
        defer { recognitionProgress = nil }
        for (index, page) in pages.enumerated() {
            do {
                var result = PageRecognition(pageID: page.id, sourceRevision: page.revision,
                                             engineVersion: TextRecognizer.engineVersion, status: .failed,
                                             languages: languages, lines: [])
                if let image = try await renderer.renderSourceForRecognition(page, pixelsPerPoint: 2) {
                    result.lines = try recognizer.recognize(image)
                    result.status = .completed
                }
                try await store.saveRecognition(result)
            } catch {
                presentedError = .saveFailed()
            }
            recognitionProgress = (index + 1, pages.count)
        }
        session.didChange()
    }

    var selectedPage: Page? { pages.first { $0.id == selectedPageID } }
    var selectedIndex: Int? { pages.firstIndex { $0.id == selectedPageID } }

    func load() async {
        guard let store else { return }
        do {
            item = try await store.item(itemID)
            pages = try await store.pages(of: itemID)
            if selectedPageID == nil || !pages.contains(where: { $0.id == selectedPageID }) {
                selectedPageID = pages.first?.id
            }
            hasLoaded = true
        } catch {
            presentedError = .saveFailed()
        }
    }

    // MARK: - The document itself (title menu)

    func rename(to name: String) async {
        guard let store else { return }
        do {
            item = try await store.rename(itemID, to: name)
            session.didChange()
        } catch {
            presentedError = .saveFailed()
        }
    }

    func setFavorite(_ isFavorite: Bool) async {
        guard let store else { return }
        do {
            try await store.setFavorite(itemID, isFavorite)
            item = try await store.item(itemID)
            session.didChange()
        } catch {
            presentedError = .saveFailed()
        }
    }

    // MARK: - Transform edits

    func rotate(clockwise: Bool, undoManager: UndoManager?) async {
        guard let page = selectedPage else { return }
        var t = page.transform
        t.rotation = clockwise ? t.rotation.rotatedClockwise() : t.rotation.rotatedCounterclockwise()
        await apply(t, to: page.id, actionName: L10n.undoRotate, undoManager: undoManager)
    }

    func setFilter(_ filter: PageFilter, undoManager: UndoManager?) async {
        guard let page = selectedPage, page.transform.filter != filter else { return }
        var t = page.transform
        t.filter = filter
        await apply(t, to: page.id, actionName: L10n.undoFilter, undoManager: undoManager)
    }

    func setAdjustments(brightness: Double, contrast: Double, undoManager: UndoManager?) async {
        guard let page = selectedPage else { return }
        var t = page.transform
        t = PageTransform(crop: t.crop, rotation: t.rotation, filter: t.filter, brightness: brightness, contrast: contrast)
        await apply(t, to: page.id, actionName: L10n.undoAdjust, undoManager: undoManager)
    }

    /// Applies a crop drawn in the crop editor. A crop that only differs by
    /// rounding from the current one is not recorded as an edit.
    func setCrop(_ crop: NormalizedRect, undoManager: UndoManager?) async {
        guard let page = selectedPage, !page.transform.crop.isApproximately(crop) else { return }
        var t = page.transform
        t.crop = crop.isApproximately(.full) ? .full : crop
        await apply(t, to: page.id, actionName: L10n.undoCrop, undoManager: undoManager)
    }

    func revertToOriginal(undoManager: UndoManager?) async {
        guard let page = selectedPage else { return }
        await apply(.identity, to: page.id, actionName: L10n.revertToOriginal, undoManager: undoManager)
    }

    private func apply(_ transform: PageTransform, to pageID: PageID, actionName: String, undoManager: UndoManager?) async {
        guard let previous = pages.first(where: { $0.id == pageID })?.transform, previous != transform else { return }
        guard await commitTransform(transform, to: pageID) else { return }
        registerTransformUndo(restoring: previous, redoing: transform, pageID: pageID, actionName: actionName, undoManager: undoManager)
    }

    // Undo/redo: each handler registers its own inverse *synchronously*
    // while the undo manager is undoing (or redoing), so the inverse lands
    // on the correct stack; only then does it start the async store write.

    private func registerTransformUndo(restoring old: PageTransform, redoing new: PageTransform, pageID: PageID,
                                       actionName: String, undoManager: UndoManager?) {
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.registerTransformUndo(restoring: new, redoing: old, pageID: pageID, actionName: actionName, undoManager: undoManager)
                model.selectedPageID = pageID
                _ = Task { await model.commitTransform(old, to: pageID) }
            }
        }
        undoManager?.setActionName(actionName)
    }

    @discardableResult
    private func commitTransform(_ transform: PageTransform, to pageID: PageID) async -> Bool {
        guard let store else { return false }
        do {
            replace(try await store.updateTransform(pageID, to: transform))
            session.didChange()
            return true
        } catch {
            presentedError = .saveFailed()
            return false
        }
    }

    // MARK: - Ink (pass 7: Apple Pencil on iPad)

    /// Objects on the selected page, for the ink canvas. Refreshed after
    /// every committed ink change, undo and redo included, so the canvas
    /// can follow along.
    private(set) var selectedPageObjects: [PageObject] = []

    func loadSelectedPageObjects() async {
        guard let store, let pageID = selectedPageID else {
            selectedPageObjects = []
            return
        }
        do {
            let objects = try await store.objects(on: pageID)
            if selectedPageID == pageID { selectedPageObjects = objects }
        } catch {
            presentedError = .saveFailed()
        }
    }

    /// What one ink gesture changed on a page, with what it needs to be
    /// reversed exactly (erased strokes come back, moved strokes go back).
    struct InkChange {
        let pageID: PageID
        /// New or moved objects, as saved.
        let saved: [PageObject]
        /// The moved objects as they were before.
        let replaced: [PageObject]
        let deleted: [PageObject]

        var inverse: InkChange {
            let replacedIDs = Set(replaced.map(\.id))
            return InkChange(pageID: pageID, saved: replaced + deleted,
                             replaced: saved.filter { replacedIDs.contains($0.id) },
                             deleted: saved.filter { !replacedIDs.contains($0.id) })
        }
    }

    /// Commits one ink gesture as one undo step: `saving` holds new or
    /// moved objects, `deleting` the erased ones.
    func changeInk(on pageID: PageID, saving: [PageObject], deleting: [PageObject], undoManager: UndoManager?) async {
        guard let store, !saving.isEmpty || !deleting.isEmpty else { return }
        do {
            let current = Dictionary(uniqueKeysWithValues: try await store.objects(on: pageID).map { ($0.id, $0) })
            let change = InkChange(pageID: pageID, saved: saving, replaced: saving.compactMap { current[$0.id] }, deleted: deleting)
            guard await commitInk(change) else { return }
            registerInkUndo(change.inverse, undoManager: undoManager)
        } catch {
            presentedError = .saveFailed()
        }
    }

    private func registerInkUndo(_ change: InkChange, undoManager: UndoManager?) {
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.registerInkUndo(change.inverse, undoManager: undoManager)
                model.selectedPageID = change.pageID
                _ = Task { await model.commitInk(change) }
            }
        }
        undoManager?.setActionName(L10n.undoInk)
    }

    @discardableResult
    private func commitInk(_ change: InkChange) async -> Bool {
        guard let store else { return false }
        do {
            replace(try await store.applyObjectChanges(on: change.pageID, saving: change.saved, deleting: change.deleted.map(\.id)))
            if selectedPageID == change.pageID { selectedPageObjects = try await store.objects(on: change.pageID) }
            session.didChange()
            return true
        } catch {
            presentedError = .saveFailed()
            return false
        }
    }

    // MARK: - Page order

    func movePages(from offsets: IndexSet, to destination: Int, undoManager: UndoManager?) async {
        guard offsets.count == 1, let from = offsets.first else { return }
        // List's destination counts the moved row; convert to a final index.
        let target = destination > from ? destination - 1 : destination
        await movePage(at: from, to: target, undoManager: undoManager)
    }

    func moveSelected(by delta: Int, undoManager: UndoManager?) async {
        guard let index = selectedIndex else { return }
        await movePage(at: index, to: index + delta, undoManager: undoManager)
    }

    private func movePage(at from: Int, to target: Int, undoManager: UndoManager?) async {
        guard await commitMove(at: from, to: target) else { return }
        registerMoveUndo(from: target, to: from, undoManager: undoManager)
    }

    private func registerMoveUndo(from: Int, to target: Int, undoManager: UndoManager?) {
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.registerMoveUndo(from: target, to: from, undoManager: undoManager)
                _ = Task { await model.commitMove(at: from, to: target) }
            }
        }
        undoManager?.setActionName(L10n.undoMovePage)
    }

    @discardableResult
    private func commitMove(at from: Int, to target: Int) async -> Bool {
        guard let store, pages.indices.contains(from), pages.indices.contains(target), from != target else { return false }
        do {
            try await store.movePage(pages[from].id, toIndex: target)
            pages = try await store.pages(of: itemID)
            session.didChange()
            return true
        } catch {
            presentedError = .saveFailed()
            return false
        }
    }

    // MARK: - Deletion

    func deleteSelectedPage(undoManager: UndoManager?) async {
        guard let page = selectedPage, let deleted = await commitDelete([page.id]) else { return }
        registerDeleteUndo(deleted, undoManager: undoManager)
    }

    private func registerDeleteUndo(_ deleted: [LibraryStore.DeletedPage], undoManager: UndoManager?) {
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.registerRestoreUndo(deleted, undoManager: undoManager)
                _ = Task { await model.commitRestore(deleted) }
            }
        }
        undoManager?.setActionName(L10n.undoDeletePage)
    }

    private func registerRestoreUndo(_ deleted: [LibraryStore.DeletedPage], undoManager: UndoManager?) {
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.registerDeleteUndo(deleted, undoManager: undoManager)
                _ = Task { await model.commitDelete(deleted.map(\.page.id)) }
            }
        }
        undoManager?.setActionName(L10n.undoDeletePage)
    }

    @discardableResult
    private func commitDelete(_ ids: [PageID]) async -> [LibraryStore.DeletedPage]? {
        guard let store else { return nil }
        let index = selectedIndex ?? 0
        do {
            let deleted = try await store.deletePages(ids)
            pages = try await store.pages(of: itemID)
            if !pages.contains(where: { $0.id == selectedPageID }) {
                selectedPageID = pages.indices.contains(index) ? pages[index].id : pages.last?.id
            }
            session.didChange()
            return deleted
        } catch {
            presentedError = .saveFailed()
            return nil
        }
    }

    private func commitRestore(_ deleted: [LibraryStore.DeletedPage]) async {
        guard let store else { return }
        do {
            try await store.restorePages(deleted)
            pages = try await store.pages(of: itemID)
            selectedPageID = deleted.first?.page.id
            session.didChange()
        } catch {
            presentedError = .saveFailed()
        }
    }

    // MARK: - Adding and replacing pages (scan, rescan)

    /// Adds validated pages after the selected page and selects the first.
    func insertPages(_ prepared: DocumentImporter.Prepared) async {
        guard let store else { return }
        do {
            let inserted = try await store.insertPages(prepared.pages, into: itemID, after: selectedPageID, assets: prepared.assets)
            pages = try await store.pages(of: itemID)
            selectedPageID = inserted.first?.id ?? selectedPageID
            session.didChange()
        } catch {
            presentedError = .saveFailed()
        }
    }

    /// Rescan/replace: the selected page keeps its place and identity and
    /// shows the first new page; further new pages go right after it. The
    /// chosen look (filter, brightness, contrast) carries over; crop and
    /// rotation described the old capture, so they reset.
    func replaceSelectedPage(with prepared: DocumentImporter.Prepared, undoManager: UndoManager?) async {
        guard let store, let page = selectedPage, let first = prepared.pages.first else { return }
        let look = page.transform
        let replacement = LibraryStore.PageContentSnapshot(
            sourceSize: first.sourceSize, content: first.content,
            transform: PageTransform(filter: look.filter, brightness: look.brightness, contrast: look.contrast))
        do {
            let change = try await store.replacePage(page.id, with: replacement, inserting: Array(prepared.pages.dropFirst()),
                                                     assets: prepared.assets)
            registerReplacementUndo(change, undoManager: undoManager)
            pages = try await store.pages(of: itemID)
            selectedPageID = page.id
            session.didChange()
        } catch {
            presentedError = .saveFailed()
        }
    }

    private func registerReplacementUndo(_ change: LibraryStore.PageReplacement, undoManager: UndoManager?) {
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.registerReplacementRedo(change, undoManager: undoManager)
                _ = Task { await model.commitReplacement(change, undoing: true) }
            }
        }
        undoManager?.setActionName(L10n.undoReplacePage)
    }

    private func registerReplacementRedo(_ change: LibraryStore.PageReplacement, undoManager: UndoManager?) {
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.registerReplacementUndo(change, undoManager: undoManager)
                _ = Task { await model.commitReplacement(change, undoing: false) }
            }
        }
        undoManager?.setActionName(L10n.undoReplacePage)
    }

    private func commitReplacement(_ change: LibraryStore.PageReplacement, undoing: Bool) async {
        guard let store else { return }
        do {
            if undoing {
                try await store.revertPageReplacement(change)
            } else {
                try await store.reapplyPageReplacement(change)
            }
            pages = try await store.pages(of: itemID)
            selectedPageID = change.pageID
            session.didChange()
        } catch {
            presentedError = .saveFailed()
        }
    }

    private func replace(_ page: Page) {
        if let index = pages.firstIndex(where: { $0.id == page.id }) {
            pages[index] = page
        }
    }
}

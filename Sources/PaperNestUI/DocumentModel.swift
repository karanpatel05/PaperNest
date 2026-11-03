import Foundation
import ImageIO
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
    private(set) var isChangingNotebookPage = false
    private var historyTask: Task<Void, Never>?
    private var pendingHistory = 0
    private var historyGeneration = 0
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
    func recognizeText(on pageID: PageID? = nil) async {
        await finishPendingHistory()
        guard let store, let renderer = session.environment?.renderer, recognitionProgress == nil else { return }
        let recognizer = TextRecognizer()
        let languages = TextRecognizer.supportedLanguages(from: TextRecognizer.preferredLanguages)
        let pages = self.pages.filter { pageID == nil || $0.id == pageID }
        recognitionProgress = (0, pages.count)
        defer { recognitionProgress = nil }
        for (index, page) in pages.enumerated() {
            do {
                var result = PageRecognition(pageID: page.id, sourceRevision: page.revision,
                                             engineVersion: TextRecognizer.engineVersion, status: .failed,
                                             languages: languages, lines: [])
                if let image = try await renderer.renderSourceForRecognition(page, pixelsPerPoint: 2) {
                    result.lines = try await recognizer.recognizeOnADedicatedThread(image)
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
        await finishPendingHistory()
        guard let page = selectedPage else { return }
        var t = page.transform
        t.rotation = clockwise ? t.rotation.rotatedClockwise() : t.rotation.rotatedCounterclockwise()
        await apply(t, to: page.id, actionName: L10n.undoRotate, undoManager: undoManager)
    }

    func setFilter(_ filter: PageFilter, undoManager: UndoManager?) async {
        await finishPendingHistory()
        guard let page = selectedPage, page.transform.filter != filter else { return }
        var t = page.transform
        t.filter = filter
        await apply(t, to: page.id, actionName: L10n.undoFilter, undoManager: undoManager)
    }

    func setAdjustments(brightness: Double, contrast: Double, undoManager: UndoManager?) async {
        await finishPendingHistory()
        guard let page = selectedPage else { return }
        var t = page.transform
        t = PageTransform(crop: t.crop, rotation: t.rotation, filter: t.filter, brightness: brightness, contrast: contrast)
        await apply(t, to: page.id, actionName: L10n.undoAdjust, undoManager: undoManager)
    }

    /// Applies a crop drawn in the crop editor. A crop that only differs by
    /// rounding from the current one is not recorded as an edit.
    func setCrop(_ crop: NormalizedRect, undoManager: UndoManager?) async {
        await finishPendingHistory()
        guard let page = selectedPage, !page.transform.crop.isApproximately(crop) else { return }
        var t = page.transform
        t.crop = crop.isApproximately(.full) ? .full : crop
        await apply(t, to: page.id, actionName: L10n.undoCrop, undoManager: undoManager)
    }

    func revertToOriginal(undoManager: UndoManager?) async {
        await finishPendingHistory()
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

    /// Advances every time this model touches the undo stack.
    ///
    /// `UndoManager.canUndo` and `canRedo` are not observable, so a view
    /// holding Undo and Redo buttons re-reads them only when one of its own
    /// inputs changes. The notifications cover an undo and a redo but **not a
    /// registration made from inside a `Task`**, which is every ink edit, so
    /// the row went on showing the state from before the stroke: Undo greyed
    /// out on the mark just drawn. This is the input it was missing — the
    /// model is the only thing that knows it has registered.
    private(set) var historyRevision = 0

    private func historyDidChange() { historyRevision &+= 1 }

    /// A fresh edit must not write into an intermediate undo/redo state.
    /// Recheck after each suspension because native shortcuts may enqueue more.
    private func finishPendingHistory() async {
        while let pending = historyTask { await pending.value }
    }

    /// All callbacks sharing the document's UndoManager must commit in request
    /// order, including mixed page creation/deletion/ink/transform history.
    private func enqueueHistory(undoManager: UndoManager?, operation: @escaping @MainActor () async -> Bool) {
        isChangingNotebookPage = true
        pendingHistory += 1
        let previous = historyTask
        let generation = historyGeneration
        historyTask = Task { @MainActor in
            await previous?.value
            defer {
                pendingHistory -= 1
                isChangingNotebookPage = pendingHistory > 0
                if pendingHistory == 0 { historyTask = nil }
            }
            guard generation == historyGeneration else { return }
            if !(await operation()) {
                historyGeneration += 1
                undoManager?.removeAllActions(withTarget: self)
                historyDidChange()
            }
        }
    }

    private func registerTransformUndo(restoring old: PageTransform, redoing new: PageTransform, pageID: PageID,
                                       actionName: String, undoManager: UndoManager?) {
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.registerTransformUndo(restoring: new, redoing: old, pageID: pageID, actionName: actionName, undoManager: undoManager)
                model.enqueueHistory(undoManager: undoManager) {
                    model.selectedPageID = pageID
                    return await model.commitTransform(old, to: pageID)
                }
            }
        }
        undoManager?.setActionName(actionName)
        historyDidChange()
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
        await finishPendingHistory()
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

    func addShape(to page: Page, kind: ShapeAnnotation, start: CGPoint, end: CGPoint,
                  color: RGBAColor, width: Double, undoManager: UndoManager?) async throws {
        await finishPendingHistory()
        guard let store, page.itemID == itemID else { throw StoreError.pageNotFound }
        let result = try await store.addShape(to: page, kind: kind, start: start, end: end, color: color, width: width)
        replace(result.page)
        let change = InkChange(pageID: page.id, saved: result.objects, replaced: [], deleted: [])
        registerInkUndo(change.inverse, undoManager: undoManager, actionName: kind.isStamp ? L10n.stampTitle : L10n.shapeTitle)
        await loadSelectedPageObjects()
        session.didChange()
    }

    /// Puts typed text on a page.
    ///
    /// Nothing can place a box by hand yet, so the frame is chosen here: a
    /// band across the upper part of the page with room for a few lines.
    /// Text longer than that is clipped when drawn, which is why the height
    /// grows with the font size rather than being a fixed fraction.
    func addTextBox(to page: Page, text: String, fontSize: Double, color: RGBAColor,
                    alignment: TextBox.Alignment, undoManager: UndoManager?) async throws {
        await finishPendingHistory()
        guard let store, page.itemID == itemID else { throw StoreError.pageNotFound }
        let size = page.sourceSize
        let frame = CGRect(x: size.width * 0.1, y: size.height * 0.12,
                           width: size.width * 0.8,
                           height: max(fontSize * 3, size.height * 0.12))
        let result = try await store.placeText(text, on: page.id, frame: frame,
                                               fontSize: fontSize, color: color,
                                               alignment: alignment)
        replace(result.page)
        let change = InkChange(pageID: page.id, saved: [result.object], replaced: [], deleted: [])
        registerInkUndo(change.inverse, undoManager: undoManager, actionName: L10n.textBox)
        await loadSelectedPageObjects()
        session.didChange()
    }

    /// Removes the strokes an eraser drag touched, as one undoable step.
    ///
    /// Whole strokes, not parts of them: see `MacInkCanvas.strokesHit`.
    func eraseInk(_ objects: [PageObject], on page: Page, undoManager: UndoManager?) async throws {
        guard !objects.isEmpty else { return }
        await finishPendingHistory()
        guard let store, page.itemID == itemID else { throw StoreError.pageNotFound }
        replace(try await store.applyInkChanges(on: page.id, saving: [], replacing: [],
                                                deleting: objects))
        let change = InkChange(pageID: page.id, saved: [], replaced: [], deleted: objects)
        registerInkUndo(change.inverse, undoManager: undoManager, actionName: L10n.inkEraser)
        await loadSelectedPageObjects()
        session.didChange()
    }

    /// Puts an image on a page.
    ///
    /// The bytes are staged durably first and the row that references them is
    /// written in the same transaction by `placeImage`, so the housekeeping
    /// sweep cannot take the file in between.
    func addImage(_ data: Data, named filename: String?, to page: Page,
                  undoManager: UndoManager?) async throws {
        await finishPendingHistory()
        guard let store, page.itemID == itemID else { throw StoreError.pageNotFound }
        // The project's own sniffer, so what is stored is what the bytes
        // are rather than what a filename claimed.
        guard let kind = FileTypeSniffer.kind(of: data), kind.isDrawableImage else {
            throw StoreError.invalidPlacement
        }
        let staged = try store.assets.store(data, kind: kind, originalFilename: filename)
        let frame = Self.imageFrame(pixels: Self.pixelSize(of: data), on: page)
        let result = try await store.placeImage(staged, on: page.id, frame: frame)
        replace(result.page)
        let change = InkChange(pageID: page.id, saved: [result.object], replaced: [], deleted: [])
        registerInkUndo(change.inverse, undoManager: undoManager, actionName: L10n.insertImage)
        await loadSelectedPageObjects()
        session.didChange()
    }

    /// The image's own pixel dimensions, or nil when they cannot be read.
    ///
    /// Orientation is taken into account: a photo stored sideways reports the
    /// size it is *shown* at, which is the shape the frame has to match.
    nonisolated static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double
        else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        // 5...8 are the quarter turns, which swap the shown dimensions.
        return orientation >= 5 ? CGSize(width: height, height: width)
                                : CGSize(width: width, height: height)
    }

    /// Where a newly placed image goes: across the upper middle of the page,
    /// **keeping its own proportions** so a photo is not squashed. Nothing can
    /// place one by hand yet, and it can be dragged afterwards.
    nonisolated static func imageFrame(pixels: CGSize?, on page: Page) -> CGRect {
        let source = page.sourceSize
        let box = CGSize(width: source.width * 0.5, height: source.height * 0.4)
        let pixels = pixels ?? box
        let scale = min(box.width / max(pixels.width, 1), box.height / max(pixels.height, 1))
        let size = CGSize(width: max(pixels.width * scale, 1), height: max(pixels.height * scale, 1))
        return CGRect(x: (source.width - size.width) / 2, y: source.height * 0.15,
                      width: size.width, height: size.height)
    }

    /// Saves one drawn stroke on top of what the page already holds.
    ///
    /// The Mac canvas's way in. iOS does not use it: PencilKit hands over a
    /// whole drawing to reconcile, which `InkCanvas` does.
    func addInkStroke(_ stroke: InkStroke, to page: Page, undoManager: UndoManager?) async throws {
        await finishPendingHistory()
        guard let store, page.itemID == itemID else { throw StoreError.pageNotFound }
        let top = selectedPageObjects.filter { $0.pageID == page.id }.map(\.zKey).max()
        let object = PageObject(pageID: page.id, zKey: try SortKey.between(top, nil),
                                payload: .ink(stroke), modifiedAt: Date())
        replace(try await store.applyInkChanges(on: page.id, saving: [object],
                                                replacing: [], deleting: []))
        let change = InkChange(pageID: page.id, saved: [object], replaced: [], deleted: [])
        registerInkUndo(change.inverse, undoManager: undoManager, actionName: L10n.undoInk)
        await loadSelectedPageObjects()
        session.didChange()
    }

    /// Moves a placed mark to a new frame in source space.
    ///
    /// Only a text box or a placed image: ink is moved by the drawing canvas's
    /// own lasso, and a page comment has no frame to move. Goes through
    /// `applyInkChanges` so the write is refused if the object changed under
    /// it, and so undo works the same way it does for everything else.
    func moveObject(_ object: PageObject, to frame: CGRect, undoManager: UndoManager?) async throws {
        await finishPendingHistory()
        guard let store, let page = selectedPage, object.pageID == page.id else {
            throw StoreError.pageNotFound
        }
        guard let moved = Self.moved(object, to: frame) else { return }
        replace(try await store.applyInkChanges(on: page.id, saving: [moved],
                                                replacing: [object], deleting: []))
        let change = InkChange(pageID: page.id, saved: [moved], replaced: [object], deleted: [])
        registerInkUndo(change.inverse, undoManager: undoManager, actionName: L10n.moveObject)
        await loadSelectedPageObjects()
        session.didChange()
    }

    /// The object with a new frame, or nil for a kind this does not move.
    nonisolated static func moved(_ object: PageObject, to frame: CGRect) -> PageObject? {
        var moved = object
        switch object.payload {
        case .text(var box):
            box.frame = frame
            moved.payload = .text(box)
        case .image(var image):
            image.frame = frame
            moved.payload = .image(image)
        case .ink, .comment:
            return nil
        }
        moved.modifiedAt = Date()
        return moved
    }

    /// Moves handwriting, as one undoable step.
    ///
    /// Takes the objects' **ids** and reads their current state here rather
    /// than trusting what the canvas was holding: between selecting a stroke
    /// and dragging it the page may have been undone underneath, and
    /// `applyInkChanges` refuses a write whose `replacing` no longer matches.
    func moveInk(_ ids: [PageObjectID], on page: Page, by delta: CGPoint,
                 undoManager: UndoManager?) async throws {
        await finishPendingHistory()
        guard let store, page.itemID == itemID else { throw StoreError.pageNotFound }
        let wanted = Set(ids)
        let current = selectedPageObjects.filter { wanted.contains($0.id) && $0.pageID == page.id }
        let moved = current.compactMap { Self.translated($0, by: delta) }
        guard moved.count == current.count, !moved.isEmpty else { return }
        replace(try await store.applyInkChanges(on: page.id, saving: moved,
                                                replacing: current, deleting: []))
        let change = InkChange(pageID: page.id, saved: moved, replaced: current, deleted: [])
        registerInkUndo(change.inverse, undoManager: undoManager, actionName: L10n.moveInk)
        await loadSelectedPageObjects()
        session.didChange()
    }

    /// A stroke shifted across the page, or nil for a kind with no points.
    ///
    /// Every point moves and nothing else changes — the same id, so undo sees
    /// one mark moved rather than one deleted and another added, and the same
    /// `widthScale` and `time` per point, so pressure and timing recorded by
    /// an Apple Pencil survive being moved on a Mac.
    nonisolated static func translated(_ object: PageObject, by delta: CGPoint) -> PageObject? {
        guard case .ink(var stroke) = object.payload else { return nil }
        stroke.points = stroke.points.map {
            InkPoint(x: $0.x + delta.x, y: $0.y + delta.y, widthScale: $0.widthScale, time: $0.time)
        }
        var moved = object
        moved.payload = .ink(stroke)
        moved.modifiedAt = Date()
        return moved
    }

    /// A drag measured in view points, as a distance in source points.
    ///
    /// Through the page's own transform rather than past it: two points
    /// converted and subtracted, so a rotated or flipped page moves a mark the
    /// way it looks rather than the way a bare division by the scale would.
    nonisolated static func sourceDelta(of viewTranslation: CGSize,
                                        sourceToView: CGAffineTransform) -> CGPoint {
        let viewToSource = sourceToView.inverted()
        let moved = CGPoint(x: viewTranslation.width, y: viewTranslation.height).applying(viewToSource)
        let origin = CGPoint.zero.applying(viewToSource)
        return CGPoint(x: moved.x - origin.x, y: moved.y - origin.y)
    }

    /// A drag of a lassoed selection, cut back so the selection stays on the
    /// page.
    ///
    /// Stricter than `clamped`, which lets a frame hang over an edge: the
    /// lasso only takes a stroke it can enclose **wholly**, so handwriting
    /// with a tail off the page could never be selected again, and would be
    /// stuck there. A selection already larger than the page cannot satisfy
    /// both edges, and then it is left alone rather than pinned.
    nonisolated static func clampedTranslation(of bounds: CGRect, by delta: CGPoint,
                                               within source: CGSize) -> CGPoint {
        func clamp(_ value: Double, _ lowest: Double, _ highest: Double) -> Double {
            highest >= lowest ? min(max(value, lowest), highest) : value
        }
        return CGPoint(x: clamp(delta.x, -bounds.minX, source.width - bounds.maxX),
                       y: clamp(delta.y, -bounds.minY, source.height - bounds.maxY))
    }

    /// Keeps a dragged frame from being lost off the edge of the page.
    ///
    /// Not clamped to sit fully on the page — hanging over an edge is a
    /// legitimate thing to want, and drawing clips it — but the origin stays
    /// inside, so a mark can always be found and dragged back.
    nonisolated static func clamped(_ frame: CGRect, within source: CGSize) -> CGRect {
        CGRect(x: min(max(frame.minX, 0), max(source.width - 1, 0)),
               y: min(max(frame.minY, 0), max(source.height - 1, 0)),
               width: frame.width, height: frame.height)
    }

    func addTextMarkup(_ snapshot: PageRecognition, lineIndices: Set<Int>, style: TextMarkupStyle, color: RGBAColor? = nil,
                       undoManager: UndoManager?) async throws {
        await finishPendingHistory()
        guard let store else { throw StoreError.pageNotFound }
        let result = try await store.addTextMarkup(snapshot, lineIndices: lineIndices, style: style, color: color)
        replace(result.page)
        let change = InkChange(pageID: result.page.id, saved: result.objects, replaced: [], deleted: [])
        registerInkUndo(change.inverse, undoManager: undoManager, actionName: L10n.annotateText)
        await loadSelectedPageObjects()
        session.didChange()
    }

    func editInk(on page: Page, objects: [PageObject], edit: InkEdit, undoManager: UndoManager?) async throws {
        await finishPendingHistory()
        guard let store else { throw StoreError.pageNotFound }
        let result = try await store.editInk(on: page.id, expectedRevision: page.revision, objects: objects, edit: edit)
        replace(result.page)
        let removing: Bool
        if case .remove = edit { removing = true } else { removing = false }
        let change = InkChange(pageID: page.id, saved: result.saved,
                               replaced: removing ? [] : result.previous, deleted: removing ? result.previous : [])
        registerInkUndo(change.inverse, undoManager: undoManager,
                        actionName: removing ? L10n.markupRemove : L10n.markupRecolor)
        await loadSelectedPageObjects()
        session.didChange()
    }

    private func registerInkUndo(_ change: InkChange, undoManager: UndoManager?, actionName: String = L10n.undoInk) {
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.registerInkUndo(change.inverse, undoManager: undoManager, actionName: actionName)
                model.enqueueHistory(undoManager: undoManager) {
                    model.selectedPageID = change.pageID
                    return await model.commitInk(change)
                }
            }
        }
        undoManager?.setActionName(actionName)
        historyDidChange()
    }

    @discardableResult
    private func commitInk(_ change: InkChange) async -> Bool {
        guard let store else { return false }
        do {
            replace(try await store.applyInkChanges(on: change.pageID, saving: change.saved,
                                                  replacing: change.replaced, deleting: change.deleted))
            if selectedPageID == change.pageID { selectedPageObjects = try await store.objects(on: change.pageID) }
            session.didChange()
            return true
        } catch StoreError.pageObjectsChanged {
            await load()
            await loadSelectedPageObjects()
            presentedError = PresentedError(title: L10n.genericErrorTitle, message: L10n.markupChanged)
            return false
        } catch {
            presentedError = .saveFailed()
            return false
        }
    }

    // MARK: - Page order

    func movePages(from offsets: IndexSet, to destination: Int, undoManager: UndoManager?) async {
        await finishPendingHistory()
        guard offsets.count == 1, let from = offsets.first else { return }
        // List's destination counts the moved row; convert to a final index.
        let target = destination > from ? destination - 1 : destination
        await movePage(at: from, to: target, undoManager: undoManager)
    }

    func moveSelected(by delta: Int, undoManager: UndoManager?) async {
        await finishPendingHistory()
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
                model.enqueueHistory(undoManager: undoManager) { await model.commitMove(at: from, to: target) }
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
        await finishPendingHistory()
        guard let page = selectedPage, let deleted = await commitDelete([page.id]) else { return }
        registerDeleteUndo(deleted, undoManager: undoManager)
    }

    private func registerDeleteUndo(_ deleted: [LibraryStore.DeletedPage], undoManager: UndoManager?) {
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.registerRestoreUndo(deleted, undoManager: undoManager)
                model.enqueueHistory(undoManager: undoManager) { await model.commitRestore(deleted) }
            }
        }
        undoManager?.setActionName(L10n.undoDeletePage)
    }

    private func registerRestoreUndo(_ deleted: [LibraryStore.DeletedPage], undoManager: UndoManager?) {
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.registerDeleteUndo(deleted, undoManager: undoManager)
                model.enqueueHistory(undoManager: undoManager) { await model.commitDelete(deleted.map(\.page.id)) != nil }
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

    private func commitRestore(_ deleted: [LibraryStore.DeletedPage]) async -> Bool {
        guard let store else { return false }
        do {
            try await store.restorePages(deleted)
            pages = try await store.pages(of: itemID)
            selectedPageID = deleted.first?.page.id
            session.didChange()
            return true
        } catch {
            presentedError = .saveFailed()
            return false
        }
    }

    // MARK: - Page comments

    func comments(on pageID: PageID) async throws -> [PageObject] {
        guard let store, let page = try await store.page(pageID), page.itemID == itemID,
              let parent = try await store.item(itemID), !parent.isDeleted else { throw StoreError.pageNotFound }
        return try await store.objects(on: pageID).filter { $0.commentText != nil }
    }

    func setComment(on pageID: PageID, replacing expected: PageObject?, text: String?, undoManager: UndoManager?) async throws {
        await finishPendingHistory()
        guard let store, let page = try await store.page(pageID), page.itemID == itemID else { throw StoreError.pageNotFound }
        let change = try await store.setPageComment(on: pageID, replacing: expected, text: text)
        registerCommentUndo(change.inverse, undoManager: undoManager)
        await load()
        await loadSelectedPageObjects()
        session.didChange()
    }

    private func registerCommentUndo(_ change: LibraryStore.PageCommentChange, undoManager: UndoManager?) {
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.registerCommentUndo(change.inverse, undoManager: undoManager)
                model.enqueueHistory(undoManager: undoManager) {
                    do {
                        guard let store = model.store else { throw StoreError.pageNotFound }
                        _ = try await store.applyPageCommentChange(change)
                        await model.load()
                        await model.loadSelectedPageObjects()
                        model.session.didChange()
                        return true
                    } catch {
                        await model.load()
                        await model.loadSelectedPageObjects()
                        model.presentedError = PresentedError(title: L10n.genericErrorTitle, message: L10n.commentHistoryChanged)
                        return false
                    }
                }
            }
        }
        undoManager?.setActionName(L10n.commentAction)
    }

    // MARK: - Notebook template pages

    func addNotebookPage(_ template: PageTemplate, after anchor: PageID?, undoManager: UndoManager?) async throws {
        await finishPendingHistory()
        guard !isChangingNotebookPage, let store else { throw StoreError.pageNotFound }
        isChangingNotebookPage = true
        defer { isChangingNotebookPage = pendingHistory > 0 }
        let change = try await store.addNotebookPage(template, to: itemID, after: anchor)
        registerNotebookPageUndo(NotebookUndoStep(change), undoManager: undoManager)
        selectedPageID = change.page.id
        await load()
        await loadSelectedPageObjects()
        session.didChange()
    }

    @MainActor private final class NotebookUndoStep {
        var change: LibraryStore.NotebookPageChange?
        init(_ change: LibraryStore.NotebookPageChange? = nil) { self.change = change }
    }

    private func registerNotebookPageUndo(_ step: NotebookUndoStep, undoManager: UndoManager?) {
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                // UndoManager routes registration to redo only within this
                // synchronous callback. Native keyboard/menu requests may consume
                // this slot immediately; serialize their mutations until its token
                // is armed by the preceding durable transition.
                let inverse = NotebookUndoStep()
                model.registerNotebookPageUndo(inverse, undoManager: undoManager)
                model.enqueueHistory(undoManager: undoManager) {
                    do {
                        guard let store = model.store, let change = step.change else { throw StoreError.pageNotFound }
                        let result = try await store.toggleNotebookPage(change)
                        inverse.change = result
                        if !result.isDeleted { model.selectedPageID = result.page.id }
                        await model.load()
                        await model.loadSelectedPageObjects()
                        model.session.didChange()
                        return true
                    } catch {
                        await model.load()
                        await model.loadSelectedPageObjects()
                        model.presentedError = PresentedError(title: L10n.genericErrorTitle, message: L10n.notebookPageChanged)
                        return false
                    }
                }
            }
        }
        undoManager?.setActionName(L10n.addNotebookPage)
    }

    // MARK: - Adding and replacing pages (scan, rescan)

    /// Adds validated pages after the selected page and selects the first.
    func insertPages(_ prepared: DocumentImporter.Prepared) async {
        await finishPendingHistory()
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
        await finishPendingHistory()
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
                model.enqueueHistory(undoManager: undoManager) { await model.commitReplacement(change, undoing: true) }
            }
        }
        undoManager?.setActionName(L10n.undoReplacePage)
    }

    private func registerReplacementRedo(_ change: LibraryStore.PageReplacement, undoManager: UndoManager?) {
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.registerReplacementUndo(change, undoManager: undoManager)
                model.enqueueHistory(undoManager: undoManager) { await model.commitReplacement(change, undoing: false) }
            }
        }
        undoManager?.setActionName(L10n.undoReplacePage)
    }

    private func commitReplacement(_ change: LibraryStore.PageReplacement, undoing: Bool) async -> Bool {
        guard let store else { return false }
        do {
            if undoing {
                try await store.revertPageReplacement(change)
            } else {
                try await store.reapplyPageReplacement(change)
            }
            pages = try await store.pages(of: itemID)
            selectedPageID = change.pageID
            session.didChange()
            return true
        } catch {
            presentedError = .saveFailed()
            return false
        }
    }

    private func replace(_ page: Page) {
        if let index = pages.firstIndex(where: { $0.id == page.id }) {
            pages[index] = page
        }
    }
}

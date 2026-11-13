import Foundation
import Observation
import PaperNestCore

/// A transient edit buffer, never a second metadata store. A failed commit
/// leaves this buffer and its original comparison value intact for retry.
@MainActor @Observable
final class InlineTextSession {
    let model: DocumentModel
    private(set) var box: TextBox?
    private(set) var original: PageObject?
    private(set) var page: Page?
    private(set) var canvasSize: CGSize?
    private(set) var canvasZoom: CGFloat = 1
    var isPlacing = false
    var isEditing = false
    var focusRequest = 0
    private(set) var hasFailure = false
    private(set) var isSaving = false
    private var generation = UUID()
    private(set) var isFinishing = false
    @ObservationIgnored var commitNative: (() -> Void)?
    /// Dresses a box placed from scratch in the Text tool's current type
    /// settings. Left nil, a new box is 18-point Helvetica as it always was.
    @ObservationIgnored var styleForNewBox: ((inout TextBox) -> Void)?
    private var terminal: Task<Bool, Never>?
    private var pending: Task<Bool, Never>?
    private var debounce: Task<Void, Never>?
    private var isRecovering = false

    init(model: DocumentModel) { self.model = model }
    var isSelected: Bool { box != nil }
    var excludedIDs: Set<PageObjectID> { original.map { [$0.id] } ?? [] }

    func beginNew(on page: Page, at point: CGPoint, sourceToView: CGAffineTransform, zoom: CGFloat = 1) {
        guard box == nil, !isFinishing else { return }
        let source = point.applying(sourceToView.inverted())
        let frame = DocumentModel.clamped(CGRect(x: source.x, y: source.y,
            width: min(240, page.sourceSize.width * 0.6), height: 90), within: page.sourceSize)
        self.page = page
        captureCanvas(page: page, sourceToView: sourceToView, zoom: zoom)
        var fresh = TextBox(frame: frame, text: "", fontSize: 18)
        styleForNewBox?(&fresh)
        box = fresh
        original = nil
        generation = UUID()
        hasFailure = false
        isPlacing = false
        edit()
    }

    func select(_ object: PageObject, on page: Page, sourceToView: CGAffineTransform = .identity, zoom: CGFloat = 1) {
        guard box == nil, !isFinishing, case .text(let text) = object.payload else { return }
        self.page = page; original = object; box = text
        captureCanvas(page: page, sourceToView: sourceToView, zoom: zoom)
        generation = UUID(); isPlacing = false; isEditing = false; hasFailure = false
    }

    private func captureCanvas(page: Page, sourceToView: CGAffineTransform, zoom: CGFloat) {
        let scale = hypot(sourceToView.a, sourceToView.b)
        canvasSize = CGSize(width: page.geometry.pageSize.width * scale, height: page.geometry.pageSize.height * scale)
        canvasZoom = zoom
    }

    func edit() { guard !isFinishing else { return }; isEditing = true; focusRequest += 1 }
    func change(_ edit: (inout TextBox) -> Void) {
        guard !isFinishing, var value = box else { return }
        edit(&value); box = value
    }

    func scheduleSave(undoManager: UndoManager?) {
        debounce?.cancel()
        guard !hasFailure, !isFinishing else { return }
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard let self else { return }
            _ = await self.flush(undoManager: undoManager)
        }
    }

    @discardableResult
    func flush(undoManager: UndoManager?) async -> Bool {
        let requestedGeneration = generation
        guard !isRecovering else { return false }
        while let pending { guard await pending.value else { return false } }
        guard generation == requestedGeneration, !isRecovering else { return false }
        guard let box, let page else { return true }
        if case .text(let saved)? = original?.payload, saved == box { return true }
        // Empty text is an editing state. Only finishing explicitly deletes it.
        guard !box.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        let token = generation, before = original
        isSaving = true
        let task = Task { @MainActor [self] in
            do {
                let saved = try await model.saveInlineText(box, replacing: before, on: page, undoManager: undoManager)
                if generation == token { original = saved; hasFailure = false }
                isSaving = false; pending = nil
                return true
            } catch {
                hasFailure = true; isSaving = false; pending = nil
                return false
            }
        }
        pending = task
        guard await task.value else { return false }
        guard generation == token, !isRecovering else { return false }
        // Changes made while awaiting the store must also become durable.
        if self.box != box { return await flush(undoManager: undoManager) }
        return true
    }

    @discardableResult
    func finish(undoManager: UndoManager?) async -> Bool {
        await terminate(deleting: false, undoManager: undoManager)
    }

    func delete(undoManager: UndoManager?) async {
        _ = await terminate(deleting: true, undoManager: undoManager)
    }

    /// Recovers a rejected edit without replacing the other writer's object.
    /// The original comparison value and draft remain intact if insertion fails.
    @discardableResult
    func saveAsNewBox(undoManager: UndoManager?) async -> Bool {
        await recover(savingCopy: true, undoManager: undoManager)
    }

    /// Explicitly abandons only the transient buffer. Already-started writes
    /// finish first; no delete or additional save is issued by this operation.
    func discardDraft() async {
        _ = await recover(savingCopy: false, undoManager: nil)
    }

    private func recover(savingCopy: Bool, undoManager: UndoManager?) async -> Bool {
        let token = generation
        while let terminal {
            let result = await terminal.value
            // A successful terminal operation may already have released this
            // draft. Never apply a waiting recovery to a newly selected box.
            guard generation == token else { return result }
        }
        guard isSelected else { return true }
        if savingCopy { commitNative?() }
        debounce?.cancel()
        isFinishing = true
        isRecovering = true
        let task = Task { @MainActor [self] in
            defer { isFinishing = false; isRecovering = false; terminal = nil }
            // A failed pending save is precisely what recovery must tolerate.
            // Suppress its callers' recursive flush of a newer draft as well.
            while let pending { _ = await pending.value }
            guard generation == token else { return false }
            if savingCopy {
                guard let box, let page,
                      !box.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
                isSaving = true
                defer { isSaving = false }
                do {
                    _ = try await model.saveInlineText(box, replacing: nil, on: page, undoManager: undoManager)
                } catch {
                    hasFailure = true; focusRequest += 1
                    return false
                }
            }
            clear()
            return true
        }
        terminal = task
        return await task.value
    }

    /// Commit any marked IME text synchronously before the native view goes away.
    func commitAndFlush(undoManager: UndoManager?) async {
        commitNative?()
        if box?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            _ = await finish(undoManager: undoManager)
        } else { _ = await flush(undoManager: undoManager) }
    }

    private func terminate(deleting: Bool, undoManager: UndoManager?) async -> Bool {
        if let terminal { return await terminal.value }
        commitNative?()
        debounce?.cancel()
        isFinishing = true
        let token = generation
        let task = Task { @MainActor [self] in
            defer { isFinishing = false; terminal = nil }
            guard await flush(undoManager: undoManager) else {
                focusRequest += 1
                return false
            }
            guard generation == token else { return false }
            if deleting || box?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                if let original {
                    do { try await model.deleteInlineText(original, undoManager: undoManager) }
                    catch { hasFailure = true; focusRequest += 1; return false }
                }
            }
            clear()
            return true
        }
        terminal = task
        return await task.value
    }

    private func clear() {
        commitNative = nil
        box = nil; original = nil; page = nil; canvasSize = nil; isEditing = false
        isPlacing = false; hasFailure = false; generation = UUID()
    }
}

/// All inputs are viewport coordinates derived from PageGeometry.
enum InlineTextLayout {
    static func toolbarFrame(box: CGRect, visible: CGRect, size: CGSize) -> CGRect {
        let width = min(size.width, visible.width)
        let height = min(size.height, visible.height)
        let x = min(max(box.midX - width / 2, visible.minX), visible.maxX - width)
        let above = box.minY - height - 10
        // Leave room for the explicit resize handle below the lower corner.
        let below = box.maxY + 44
        let y: CGFloat
        if above >= visible.minY && above + height <= visible.maxY { y = above }
        else if below >= visible.minY && below + height <= visible.maxY { y = below }
        else { y = visible.minY }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// One guard per RootView/window; another document window cannot replace it.
@MainActor @Observable final class DocumentEditingGuard {
    @ObservationIgnored var finish: (() async -> Bool)?
    /// Root-owned lifetime guard; remains installed when no document is visible.
    @ObservationIgnored var finishWindow: (() async -> Bool)?
    private(set) var isClosing = false

    /// All windows must be frozen synchronously before global quit awaits any flush.
    func beginClosing() -> Bool {
        guard !isClosing else { return false }
        isClosing = true
        return true
    }
    func endClosing() { isClosing = false }

    func prepareWhileClosing() async -> Bool {
        guard isClosing else { return false }
        if let finishWindow { return await finishWindow() }
        return await finish?() ?? true
    }

    func prepareToCloseWindow() async -> Bool {
        guard beginClosing() else { return false }
        defer { endClosing() }
        return await prepareWhileClosing()
    }
    @ObservationIgnored var owner: UUID?
}

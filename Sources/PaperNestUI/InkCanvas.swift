#if os(iOS)
import PaperNestCore
import PencilKit
import SwiftUI
import UIKit

/// The iPad ink layer over a page (pass 7). PencilKit draws and edits; every
/// finished gesture (a stroke, an erase, a lasso move) is turned into stored
/// `InkStroke` objects and handed to `onChange` as one change.
///
/// Undo: each change is one step in the document's undo history
/// (`DocumentModel.changeInk` registers its exact inverse), so ⌘Z, the Edit
/// menu and the tool palette's buttons all undo ink, also after zooming,
/// switching pages or leaving Markup. PencilKit's own per-stroke undo is
/// switched off (`InkCanvasView`); undoing reloads the canvas from the store.
struct InkCanvas: UIViewRepresentable {
    let pageID: PageID
    let objects: [PageObject]
    let sourceToView: CGAffineTransform
    let fingerDrawing: Bool
    /// The document's undo manager, for the tool palette's Undo and Redo.
    let documentUndoManager: UndoManager?
    var studioTool: MacMarkupTool? = nil
    var enablesTwoFingerNavigation = false
    var studioColor: RGBAColor = .black
    var studioWidth: Double = 2
    var eraserMode: InkEraserMode = .precision
    let onChange: (_ saving: [PageObject], _ deleting: [PageObject]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> InkCanvasView {
        let canvas = InkCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // The page viewer scrolls and zooms; the canvas never does.
        canvas.isScrollEnabled = false
        canvas.pinchGestureRecognizer?.isEnabled = false
        do {
            let navigation = NotebookInkNavigationGuard(target: nil, action: nil)
            canvas.addGestureRecognizer(navigation)
            canvas.drawingGestureRecognizer.require(toFail: navigation)
        }
        // Paper is always white, so ink keeps the colors picked for it.
        canvas.overrideUserInterfaceStyle = .light
        canvas.delegate = context.coordinator
        canvas.accessibilityIdentifier = "ink-canvas"
        context.coordinator.canvas = canvas
        let picker = context.coordinator.toolPicker
        picker.colorUserInterfaceStyle = .light
        if studioTool == nil {
            picker.addObserver(canvas)
            picker.setVisible(true, forFirstResponder: canvas)
        }
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return canvas
    }

    func updateUIView(_ canvas: InkCanvasView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        canvas.paletteUndoManager.document = documentUndoManager
        canvas.drawingPolicy = fingerDrawing ? .anyInput : .pencilOnly
        if let studioTool {
            coordinator.toolPicker.setVisible(false, forFirstResponder: canvas)
            let width = studioWidth * InkConversion.uniformScale(sourceToView)
            switch studioTool {
            case .pen, .highlighter:
                setTool(PKInkingTool(studioTool == .pen ? .pen : .marker,
                                    color: InkConversion.color(studioColor), width: width), on: canvas)
            case .eraser: setTool(Self.eraser(mode: eraserMode, size: studioWidth), on: canvas)
            case .lasso: setTool(PKLassoTool(), on: canvas)
            }
        }
        coordinator.show(pageID: pageID, objects: objects, sourceToView: sourceToView)
        canvas.accessibilityLabel = L10n.markup
        canvas.accessibilityValue = L10n.strokeCount(objects.filter { if case .ink = $0.payload { true } else { false } }.count)
    }

    /// Size is a relative preference (8...64), mapped into the supported
    /// native range so all presets remain distinct at every page zoom.
    static func eraser(mode: InkEraserMode, size: Double) -> PKEraserTool {
        if mode == .stroke { return PKEraserTool(.vector) }
        let range = PKEraserTool.EraserType.fixedWidthBitmap.validWidthRange
        let fraction = min(1, max(0, (size - 8) / 56))
        return PKEraserTool(.fixedWidthBitmap, width: range.lowerBound + fraction * (range.upperBound - range.lowerBound))
    }

    /// Reassigning even an equivalent tool can dismiss PencilKit's selection.
    private func setTool<T: PKTool & Equatable>(_ tool: T, on canvas: PKCanvasView) {
        if canvas.tool as? T != tool { canvas.tool = tool }
    }

    static func dismantleUIView(_ canvas: InkCanvasView, coordinator: Coordinator) {
        coordinator.toolPicker.setVisible(false, forFirstResponder: canvas)
        coordinator.toolPicker.removeObserver(canvas)
        canvas.resignFirstResponder()
    }

    @MainActor final class Coordinator: NSObject, PKCanvasViewDelegate {
        weak var canvas: InkCanvasView?
        let toolPicker = PKToolPicker()
        var onChange: ((_ saving: [PageObject], _ deleting: [PageObject]) -> Void)?

        private var pageID: PageID?
        private var conversion = InkConversion(sourceToView: .identity)
        /// Each stroke on the canvas, by seed: the objects it is stored as,
        /// and its shape when stored (to notice moves and erasing).
        private var known: [UInt32: (objects: [PageObject], shape: [StrokeShape])] = [:]
        /// The objects the canvas shows, including its own unsaved changes.
        private var shown: [PageObjectID: PageObject.Payload] = [:]
        /// The objects the model last reported, and the states the canvas
        /// has sent since (oldest first). SwiftUI can refresh the canvas
        /// before a change is saved; the model then still reports an older
        /// state, which must not count as an outside change (reloading would
        /// drop the new stroke for a moment and wipe the undo history).
        private var modelState: [PageObjectID: PageObject.Payload] = [:]
        private var pending: [[PageObjectID: PageObject.Payload]] = []
        private var topZKey: String?
        private var isLoading = false
        private var nextSeed: UInt32 = 1

        func show(pageID: PageID, objects: [PageObject], sourceToView: CGAffineTransform) {
            let incoming = Dictionary(objects.map { ($0.id, $0.payload) }, uniquingKeysWith: { a, _ in a })
            if pageID == self.pageID, sourceToView == conversion.sourceToView {
                if let caughtUp = pending.firstIndex(of: incoming) {
                    pending.removeFirst(caughtUp + 1)
                    modelState = incoming
                    return
                }
                // SwiftUI also updates for toolbar/focus changes and while an
                // ink mutation is still committing. Neither should recreate
                // native strokes or discard PencilKit's transient selection.
                if incoming == modelState { return }
            }
            // Another page, a new zoom or rotation, or a change from outside.
            self.pageID = pageID
            conversion = InkConversion(sourceToView: sourceToView)
            load(objects)
        }

        private func load(_ objects: [PageObject]) {
            guard let canvas else { return }
            known = [:]
            var strokes: [PKStroke] = []
            for object in objects {
                guard case .ink(let ink) = object.payload else { continue }
                let seed = nextSeed
                nextSeed &+= 1
                let stroke = conversion.pkStroke(from: ink, seed: seed)
                strokes.append(stroke)
                known[seed] = ([object], [StrokeShape(stroke)])
            }
            shown = Dictionary(objects.map { ($0.id, $0.payload) }, uniquingKeysWith: { a, _ in a })
            modelState = shown
            pending = []
            topZKey = objects.map(\.zKey).max()
            isLoading = true
            canvas.drawing = PKDrawing(strokes: strokes)
            isLoading = false
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isLoading, let pageID else { return }
            var saving: [PageObject] = []
            var deleting: [PageObject] = []
            // PencilKit can split a partially erased stroke into several
            // native strokes sharing the original randomSeed. Reconcile the
            // whole family once, otherwise fragments reuse the same object ID
            // and the guarded store correctly rejects the duplicate write.
            var families: [UInt32: [PKStroke]] = [:]
            var order: [UInt32] = []
            for stroke in canvasView.drawing.strokes {
                if families[stroke.randomSeed] == nil { order.append(stroke.randomSeed) }
                families[stroke.randomSeed, default: []].append(stroke)
            }
            let present = Set(order)
            for seed in order {
                let strokes = families[seed] ?? []
                let shape = strokes.map(StrokeShape.init)
                if let entry = known[seed], entry.shape == shape { continue }
                let previous = known[seed]?.objects ?? []
                let inks = strokes.flatMap { conversion.inkStrokes(from: $0) }
                let updated = objects(for: inks, reusing: previous, pageID: pageID)
                deleting += previous.filter { old in !updated.contains { $0.id == old.id } }
                saving += updated
                known[seed] = (updated, shape)
            }
            for (seed, entry) in known where !present.contains(seed) {
                deleting += entry.objects
                known[seed] = nil
            }
            guard !saving.isEmpty || !deleting.isEmpty else { return }
            for object in deleting { shown[object.id] = nil }
            for object in saving { shown[object.id] = object.payload }
            pending.append(shown)
            onChange?(saving, deleting)
        }

        private func objects(for inks: [InkStroke], reusing old: [PageObject], pageID: PageID) -> [PageObject] {
            inks.enumerated().map { index, ink in
                if index < old.count {
                    var object = old[index]
                    object.payload = .ink(ink)
                    object.modifiedAt = Date()
                    return object
                }
                let zKey = (try? SortKey.between(topZKey, nil)) ?? UUID().uuidString
                topZKey = zKey
                return PageObject(pageID: pageID, zKey: zKey, payload: .ink(ink), modifiedAt: Date())
            }
        }
    }
}

/// A canvas whose undo manager takes no registrations: PencilKit records
/// each stroke there, but every change is already one step in the
/// document's history (see `InkCanvas`). The tool palette's Undo and Redo
/// ask the canvas's undo manager, so they are passed on to the document's.
final class InkCanvasView: PKCanvasView {
    let paletteUndoManager = PaletteUndoManager()
    override var undoManager: UndoManager? { paletteUndoManager }
}

final class PaletteUndoManager: UndoManager {
    /// The document's undo manager. The palette enables its buttons when
    /// this manager announces a change, so the document's announcements are
    /// passed on.
    weak var document: UndoManager? {
        didSet { if document !== oldValue { relayNotifications() } }
    }
    /// Touched on the main thread, and in `deinit` once nothing else can.
    nonisolated(unsafe) private var relays: [NSObjectProtocol] = []

    override init() {
        super.init()
        disableUndoRegistration()
    }

    deinit {
        relays.forEach(NotificationCenter.default.removeObserver)
    }

    override var canUndo: Bool { document?.canUndo ?? false }
    override var canRedo: Bool { document?.canRedo ?? false }
    override func undo() { document?.undo() }
    override func redo() { document?.redo() }

    private func relayNotifications() {
        relays.forEach(NotificationCenter.default.removeObserver)
        relays = []
        guard let document else { return }
        let names: [Notification.Name] = [.NSUndoManagerCheckpoint, .NSUndoManagerDidCloseUndoGroup,
                                          .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange]
        for name in names {
            relays.append(NotificationCenter.default.addObserver(forName: name, object: document, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    NotificationCenter.default.post(name: name, object: self)
                }
            })
        }
    }
}

/// What identifies a stroke's current shape: PencilKit moves strokes by
/// changing their transform and erases parts by masking their path.
struct StrokeShape: Equatable {
    let transform: CGAffineTransform
    let visibleRanges: [ClosedRange<CGFloat>]
    let pointCount: Int
    let inkType: PKInk.InkType

    init(_ stroke: PKStroke) {
        transform = stroke.transform
        visibleRanges = stroke.maskedPathRanges
        pointCount = stroke.path.count
        inkType = stroke.ink.inkType
    }
}
#endif

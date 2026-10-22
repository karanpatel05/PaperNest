#if os(iOS)
import PaperNestCore
import PencilKit
import SwiftUI
import UIKit

/// The iPad ink layer over a page (pass 7). PencilKit draws and edits; every
/// finished gesture (a stroke, an erase, a lasso move) is turned into stored
/// `InkStroke` objects and handed to `onChange` as one change.
///
/// Undo: PencilKit registers each stroke with the canvas's undo manager, so
/// the canvas has its own (`InkCanvasView`). Palette undo/redo and ⌘Z work
/// while marking up; the history ends whenever the drawing is reloaded (another
/// page, a zoom or rotation, an outside change) and with the Markup session.
struct InkCanvas: UIViewRepresentable {
    let pageID: PageID
    let objects: [PageObject]
    let sourceToView: CGAffineTransform
    let fingerDrawing: Bool
    let onChange: (_ saving: [PageObject], _ deleting: [PageObject]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> InkCanvasView {
        let canvas = InkCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // The page viewer scrolls and zooms; the canvas never does.
        canvas.isScrollEnabled = false
        // Paper is always white, so ink keeps the colors picked for it.
        canvas.overrideUserInterfaceStyle = .light
        canvas.delegate = context.coordinator
        canvas.accessibilityIdentifier = "ink-canvas"
        context.coordinator.canvas = canvas
        let picker = context.coordinator.toolPicker
        picker.colorUserInterfaceStyle = .light
        picker.addObserver(canvas)
        picker.setVisible(true, forFirstResponder: canvas)
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return canvas
    }

    func updateUIView(_ canvas: InkCanvasView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        canvas.drawingPolicy = fingerDrawing ? .anyInput : .pencilOnly
        coordinator.show(pageID: pageID, objects: objects, sourceToView: sourceToView)
        canvas.accessibilityLabel = L10n.markup
        canvas.accessibilityValue = L10n.strokeCount(objects.filter { if case .ink = $0.payload { true } else { false } }.count)
    }

    static func dismantleUIView(_ canvas: InkCanvasView, coordinator: Coordinator) {
        coordinator.toolPicker.setVisible(false, forFirstResponder: canvas)
        coordinator.toolPicker.removeObserver(canvas)
        canvas.ownUndoManager.removeAllActions()
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
        private var known: [UInt32: (objects: [PageObject], shape: StrokeShape)] = [:]
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
                if incoming == modelState { return }   // nothing saved yet
                if let caughtUp = pending.firstIndex(of: incoming) {
                    pending.removeFirst(caughtUp + 1)
                    modelState = incoming
                    return
                }
            }
            // Another page, a new zoom or rotation, or a change from outside.
            self.pageID = pageID
            conversion = InkConversion(sourceToView: sourceToView)
            load(objects)
        }

        /// Replaces the drawing. PencilKit's undo steps describe the drawing
        /// being replaced (other seeds, another page or zoom), so undoing one
        /// afterwards would save strokes in the wrong place: they go too.
        private func load(_ objects: [PageObject]) {
            guard let canvas else { return }
            canvas.ownUndoManager.removeAllActions()
            known = [:]
            var strokes: [PKStroke] = []
            for object in objects {
                guard case .ink(let ink) = object.payload else { continue }
                let seed = nextSeed
                nextSeed &+= 1
                let stroke = conversion.pkStroke(from: ink, seed: seed)
                strokes.append(stroke)
                known[seed] = ([object], StrokeShape(stroke))
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
            var present = Set<UInt32>()
            for stroke in canvasView.drawing.strokes {
                let seed = stroke.randomSeed
                present.insert(seed)
                let shape = StrokeShape(stroke)
                if let entry = known[seed] {
                    guard entry.shape != shape else { continue }
                    // Moved or partly erased. The first part keeps its ID,
                    // so a plain move is an update of the same object.
                    let updated = objects(for: conversion.inkStrokes(from: stroke), reusing: entry.objects, pageID: pageID)
                    deleting += entry.objects.filter { old in !updated.contains { $0.id == old.id } }
                    saving += updated
                    known[seed] = (updated, shape)
                } else {
                    let created = objects(for: conversion.inkStrokes(from: stroke), reusing: [], pageID: pageID)
                    saving += created
                    known[seed] = (created, shape)
                }
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

/// A canvas with an undo manager of its own (see `InkCanvas`).
final class InkCanvasView: PKCanvasView {
    let ownUndoManager = UndoManager()
    override var undoManager: UndoManager? { ownUndoManager }
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

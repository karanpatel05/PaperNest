#if os(iOS)
import PencilKit
import Testing
import PaperNestCore
@testable import PaperNestUI

@MainActor @Suite struct InkCanvasCoordinatorTests {
    @Test func notebookScrollProbeRestoresNativeOneFingerNavigation() async {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 800))
        let host = UIViewController(); window.rootViewController = host
        let scroll = UIScrollView(frame: window.bounds)
        host.view.addSubview(scroll)
        let content = UIView(frame: CGRect(x: 0, y: 0, width: 600, height: 1600))
        scroll.addSubview(content)
        let probe = NotebookTouchScrolling.Probe(frame: .zero)
        probe.requiresTwoFingers = true
        content.addSubview(probe)
        window.isHidden = false
        for _ in 0..<10 where scroll.panGestureRecognizer.minimumNumberOfTouches != 2 {
            await Task.yield()
        }
        #expect(scroll.panGestureRecognizer.minimumNumberOfTouches == 2)
        probe.requiresTwoFingers = false; probe.configure()
        #expect(scroll.panGestureRecognizer.minimumNumberOfTouches == 1)
        probe.requiresTwoFingers = true; probe.configure()
        probe.removeFromSuperview()
        #expect(scroll.panGestureRecognizer.minimumNumberOfTouches == 1)
        window.isHidden = true
    }

    @Test func lassoAcceptsOneTouchAndCooperatesWithNotebookScrolling() {
        let surface = NotebookLassoTouchSurface.Surface(frame: .zero)
        #expect(surface.pan.minimumNumberOfTouches == 1)
        #expect(surface.pan.maximumNumberOfTouches == 1)
        let scroll = UIScrollView()
        #expect(surface.gestureRecognizer(surface.pan, shouldRecognizeSimultaneouslyWith: scroll.panGestureRecognizer))
        let guardGesture = NotebookInkNavigationGuard(target: nil, action: nil)
        #expect(guardGesture.gestureRecognizer(guardGesture, shouldRecognizeSimultaneouslyWith: scroll.panGestureRecognizer))
        #expect(guardGesture.gestureRecognizer(guardGesture, shouldRecognizeSimultaneouslyWith: UIPinchGestureRecognizer()))
    }

    @Test func eraserUsesRoundFixedWidthAndDistinctSupportedSizes() {
        let range = PKEraserTool.EraserType.fixedWidthBitmap.validWidthRange
        let sizes = [8.0, 36, 64].map { InkCanvas.eraser(mode: .precision, size: $0).width }
        #expect(sizes[0] == range.lowerBound)
        #expect(sizes[0] < sizes[1] && sizes[1] < sizes[2])
        #expect(sizes[2] == range.upperBound)
        #expect(InkCanvas.eraser(mode: .precision, size: 36).eraserType == .fixedWidthBitmap)
        #expect(InkCanvas.eraser(mode: .stroke, size: 36).eraserType == .vector)
    }

    @Test func splitNativeStrokesWithSharedSeedSaveDistinctObjects() throws {
        let pageID = PageID.make()
        let original = object(on: pageID)
        let canvas = InkCanvasView()
        let coordinator = InkCanvas.Coordinator()
        coordinator.canvas = canvas
        coordinator.show(pageID: pageID, objects: [original], sourceToView: .identity)
        let seed = try #require(canvas.drawing.strokes.first?.randomSeed)
        let conversion = InkConversion(sourceToView: .identity)
        let pieces = [
            InkStroke(tool: .pen, color: .black, width: 3,
                      points: [.init(x: 30, y: 40), .init(x: 50, y: 49, time: 0.2)]),
            InkStroke(tool: .pen, color: .black, width: 3,
                      points: [.init(x: 80, y: 61, time: 0.5), .init(x: 100, y: 70, time: 0.7)])
        ]
        canvas.drawing = PKDrawing(strokes: pieces.map { conversion.pkStroke(from: $0, seed: seed) })
        var saved: [PageObject] = []
        coordinator.onChange = { saving, _ in saved = saving }
        coordinator.canvasViewDrawingDidChange(canvas)
        #expect(saved.count == 2)
        #expect(Set(saved.map(\.id)).count == 2)
        #expect(saved.first?.id == original.id)
    }

    private func object(on pageID: PageID) -> PageObject {
        PageObject(pageID: pageID, zKey: "a", payload: .ink(InkStroke(
            tool: .pen, color: .black, width: 3,
            points: [InkPoint(x: 30, y: 40), InkPoint(x: 100, y: 70)])), modifiedAt: Date())
    }

    @Test func unchangedRefreshPreservesNativeStrokeIdentity() {
        let pageID = PageID.make()
        let object = object(on: pageID)
        let canvas = InkCanvasView()
        let coordinator = InkCanvas.Coordinator()
        coordinator.canvas = canvas
        coordinator.show(pageID: pageID, objects: [object], sourceToView: .identity)
        let seeds = canvas.drawing.strokes.map(\.randomSeed)
        // Replacing the drawing destroys PencilKit's transient lasso selection.
        coordinator.show(pageID: pageID, objects: [object], sourceToView: .identity)
        #expect(canvas.drawing.strokes.map(\.randomSeed) == seeds)
    }

    @Test func staleModelRefreshDoesNotErasePendingInkMove() throws {
        let pageID = PageID.make()
        let object = object(on: pageID)
        let canvas = InkCanvasView()
        let coordinator = InkCanvas.Coordinator()
        coordinator.canvas = canvas
        coordinator.show(pageID: pageID, objects: [object], sourceToView: .identity)
        let translation = CGAffineTransform(translationX: 45, y: 25)
        canvas.drawing = canvas.drawing.transformed(using: translation)
        var saved: [PageObject] = []
        coordinator.onChange = { saving, _ in saved = saving }
        coordinator.canvasViewDrawingDidChange(canvas)
        #expect(saved.count == 1)
        let moved = canvas.drawing.dataRepresentation()
        coordinator.show(pageID: pageID, objects: [object], sourceToView: .identity)
        #expect(canvas.drawing.dataRepresentation() == moved)
        coordinator.show(pageID: pageID, objects: saved, sourceToView: .identity)
        coordinator.show(pageID: pageID, objects: saved, sourceToView: .identity)
        #expect(canvas.drawing.dataRepresentation() == moved)
    }

    @Test func externalEditAndGeometryChangesStillReload() throws {
        let pageID = PageID.make()
        var object = object(on: pageID)
        let canvas = InkCanvasView()
        let coordinator = InkCanvas.Coordinator()
        coordinator.canvas = canvas
        coordinator.show(pageID: pageID, objects: [object], sourceToView: .identity)
        let seed = try #require(canvas.drawing.strokes.first?.randomSeed)
        guard case .ink(var ink) = object.payload else { return }
        ink.points[0].x = 60
        object.payload = .ink(ink)
        coordinator.show(pageID: pageID, objects: [object], sourceToView: .identity)
        #expect(canvas.drawing.strokes.first?.randomSeed != seed)
        coordinator.show(pageID: pageID, objects: [object], sourceToView: CGAffineTransform(scaleX: 2, y: 2))
        let location = try #require(canvas.drawing.strokes.first?.path.first?.location)
        #expect(abs(location.x - 120) < 0.01)
        #expect(abs(location.y - 80) < 0.01)
    }
}
#endif

import Foundation
import Testing
import PaperNestCore
@testable import PaperNestUI

struct PageSelectionGeometryTests {
    @Test func lassoAroundVisibleTextDoesNotNeedToEncloseEmptyTextBoxMargins() {
        let id = PageID.make()
        let text = PageObject(pageID: id, zKey: "b", payload: .text(TextBox(
            frame: CGRect(x: 100, y: 100, width: 240, height: 90), text: "Hi", fontSize: 20)), modifiedAt: Date())
        let loop = [CGPoint(x: 95, y: 95), CGPoint(x: 140, y: 95), CGPoint(x: 140, y: 135), CGPoint(x: 95, y: 135)]
        for rotation in QuarterTurns.allCases {
            let geometry = PageGeometry(sourceSize: CGSize(width: 600, height: 800), rotation: rotation)
            let map = geometry.sourceToPage.concatenating(CGAffineTransform(scaleX: 1.5, y: 1.5))
            #expect(PageSelectionGeometry.selection(from: loop.map { $0.applying(map) }, mode: .freehand,
                objects: [text], sourceToView: map).map(\.id) == [text.id])
        }
    }

    @Test func visibleTextCanJoinHandwritingAndImageInOneLoop() {
        let id = PageID.make()
        let objects = [
            PageObject(pageID: id, zKey: "a", payload: .ink(InkStroke(tool: .pen, color: .black, width: 3,
                points: [.init(x: 50, y: 110), .init(x: 70, y: 120)])), modifiedAt: Date()),
            PageObject(pageID: id, zKey: "b", payload: .text(TextBox(frame: CGRect(x: 100, y: 100, width: 240, height: 90),
                text: "Hi", fontSize: 20)), modifiedAt: Date()),
            PageObject(pageID: id, zKey: "c", payload: .image(PlacedImage(assetID: AssetID(sha256: String(repeating: "a", count: 64)),
                frame: CGRect(x: 50, y: 150, width: 40, height: 40))), modifiedAt: Date())
        ]
        let loop = [CGPoint(x: 40, y: 90), CGPoint(x: 145, y: 90), CGPoint(x: 145, y: 200), CGPoint(x: 40, y: 200)]
        #expect(PageSelectionGeometry.selection(from: loop, mode: .freehand, objects: objects, sourceToView: .identity).map(\.id) == objects.map(\.id))
        let emptyMargin = [CGPoint(x: 220, y: 150), CGPoint(x: 300, y: 150), CGPoint(x: 300, y: 180), CGPoint(x: 220, y: 180)]
        #expect(PageSelectionGeometry.selection(from: emptyMargin, mode: .freehand, objects: objects, sourceToView: .identity).isEmpty)
    }
    @Test func concaveFreehandLoopDoesNotSelectObjectsInItsBoundingRectangle() {
        let pageID = PageID.make()
        let inside = PageObject(pageID: pageID, zKey: "a", payload: .text(TextBox(
            frame: CGRect(x: 20, y: 60, width: 20, height: 20), text: "Inside")), modifiedAt: Date())
        let outside = PageObject(pageID: pageID, zKey: "b", payload: .text(TextBox(
            frame: CGRect(x: 60, y: 60, width: 20, height: 20), text: "Outside")), modifiedAt: Date())
        let loop = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 40),
                    CGPoint(x: 45, y: 40), CGPoint(x: 45, y: 100), CGPoint(x: 0, y: 100)]
        #expect(PageSelectionGeometry.selection(from: loop, mode: .freehand, objects: [inside, outside],
            sourceToView: .identity).map(\.id) == [inside.id])
        let contour = PageSelectionContour(viewPoints: loop, selectionBounds: CGRect(x: 20, y: 60, width: 20, height: 20),
                                            sourceToView: .identity)
        #expect(contour.contains(CGPoint(x: 30, y: 70), selectionBounds: CGRect(x: 20, y: 60, width: 20, height: 20), sourceToView: .identity))
        #expect(!contour.contains(CGPoint(x: 70, y: 70), selectionBounds: CGRect(x: 20, y: 60, width: 20, height: 20), sourceToView: .identity))
        #expect(contour.viewPoints(selectionBounds: CGRect(x: 20, y: 60, width: 20, height: 20), sourceToView: .identity) == loop)
    }

    @Test func freehandContourFollowsGroupMovementUndoAndZoom() {
        let geometry = PageGeometry(sourceSize: CGSize(width: 600, height: 800),
                                    crop: .init(x: 0.1, y: 0.1, width: 0.8, height: 0.8), rotation: .clockwise90)
        let bounds = CGRect(x: 100, y: 120, width: 80, height: 100)
        let sourceLoop = [CGPoint(x: 90, y: 100), CGPoint(x: 190, y: 110), CGPoint(x: 195, y: 230), CGPoint(x: 80, y: 225)]
        let map = geometry.sourceToPage.concatenating(CGAffineTransform(scaleX: 2, y: 2))
        let contour = PageSelectionContour(viewPoints: sourceLoop.map { $0.applying(map) }, selectionBounds: bounds, sourceToView: map)
        let moved = bounds.offsetBy(dx: 40, dy: -10)
        let zoomed = geometry.sourceToPage.concatenating(CGAffineTransform(scaleX: 3, y: 3))
        #expect(contour.viewPoints(selectionBounds: moved, sourceToView: zoomed) == sourceLoop.map {
            CGPoint(x: $0.x + 40, y: $0.y - 10).applying(zoomed)
        })
        #expect(contour.viewPoints(selectionBounds: bounds, sourceToView: map) == sourceLoop.map { $0.applying(map) })
    }
    @Test func clickingCroppedContentDoesNotMoveOrSnapIt() {
        let bounds = CGRect(x: 20, y: 30, width: 140, height: 150)
        let crop = CGRect(x: 80, y: 80, width: 400, height: 600)
        for delta in [CGSize.zero, CGSize(width: 1, height: 2)] {
            #expect(PageSelectionGeometry.dragTranslation(of: bounds, by: delta, sourceToView: .identity, crop: crop) == .zero)
        }
        #expect(PageSelectionGeometry.dragTranslation(of: bounds, by: CGSize(width: 20, height: 0),
            sourceToView: .identity, crop: crop) == CGPoint(x: 20, y: 0))
        #expect(PageSelectionGeometry.dragTranslation(of: bounds, by: CGSize(width: -20, height: 0),
            sourceToView: .identity, crop: crop) == .zero)
    }
    private func objects() -> [PageObject] {
        let pageID = PageID.make()
        return [
            PageObject(pageID: pageID, zKey: "a", payload: .ink(InkStroke(tool: .pen, color: .black, width: 4,
                points: [.init(x: 100, y: 100), .init(x: 150, y: 130)])), modifiedAt: Date()),
            PageObject(pageID: pageID, zKey: "b", payload: .text(TextBox(frame: CGRect(x: 180, y: 100, width: 120, height: 60), text: "Editable")), modifiedAt: Date()),
            PageObject(pageID: pageID, zKey: "c", payload: .image(PlacedImage(assetID: AssetID(sha256: String(repeating: "a", count: 64)),
                frame: CGRect(x: 100, y: 200, width: 100, height: 80))), modifiedAt: Date()),
            PageObject(pageID: pageID, zKey: "d", payload: .comment("Private"), modifiedAt: Date())
        ]
    }

    @Test func oneFreehandLoopSelectsHandwritingTextAndImageTogether() {
        let objects = objects()
        let path = [CGPoint(x: 80, y: 80), CGPoint(x: 320, y: 80), CGPoint(x: 320, y: 300), CGPoint(x: 80, y: 300)]
        #expect(PageSelectionGeometry.selection(from: path, mode: .freehand, objects: objects, sourceToView: .identity).map(\.id) == objects.prefix(3).map(\.id))
        #expect(PageSelectionGeometry.bounds(of: objects) == CGRect(x: 98, y: 98, width: 202, height: 182))
    }

    @Test func rectangleSelectionAndMovementUseRotatedCroppedGeometryAtEveryZoom() {
        let objects = objects()
        let geometry = PageGeometry(sourceSize: CGSize(width: 600, height: 800),
                                    crop: .init(x: 0.1, y: 0.1, width: 0.8, height: 0.8), rotation: .clockwise90)
        for zoom in [CGFloat(0.5), 1, 3] {
            let map = geometry.sourceToPage.concatenating(CGAffineTransform(scaleX: zoom, y: zoom))
            let rect = CGRect(x: 80, y: 85, width: 240, height: 220).applying(map)
            let path = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY)]
            #expect(PageSelectionGeometry.selection(from: path, mode: .rectangle, objects: objects, sourceToView: map).count == 3)
            let source = CGPoint(x: 25, y: -10)
            let view = PageSelectionGeometry.viewDelta(source, sourceToView: map)
            #expect(DocumentModel.sourceDelta(of: view, sourceToView: map) == source)
        }
    }

    @Test func tapSelectsTopmostEditableObjectAndEmptyLoopClears() {
        var objects = objects()
        guard case .image(var image) = objects[2].payload else { return }
        image.frame = CGRect(x: 180, y: 100, width: 120, height: 60)
        objects[2].payload = .image(image)
        #expect(PageSelectionGeometry.hit(at: CGPoint(x: 200, y: 120), objects: objects, sourceToView: .identity)?.id == objects[2].id)
        #expect(PageSelectionGeometry.selection(from: [CGPoint(x: 0, y: 0)], mode: .freehand, objects: objects, sourceToView: .identity).isEmpty)
        #expect(PageSelectionGeometry.selection(from: [CGPoint(x: 0, y: 0), CGPoint(x: 80, y: 0), CGPoint(x: 0, y: 0)], mode: .freehand, objects: objects, sourceToView: .identity).isEmpty)
    }
}

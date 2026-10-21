import CoreGraphics
import Testing
@testable import PaperNestUI

@Suite struct CropFrameTests {
    let bounds = CGRect(x: 0, y: 0, width: 600, height: 800)
    let rect = CGRect(x: 100, y: 100, width: 400, height: 500)
    let minSize = CGSize(width: 30, height: 40)

    @Test func cornersWinOverEdgesAndTheInteriorMoves() {
        #expect(CropFrame.handle(at: CGPoint(x: 102, y: 98), in: rect, tolerance: 20) == .topLeading)
        #expect(CropFrame.handle(at: CGPoint(x: 498, y: 603), in: rect, tolerance: 20) == .bottomTrailing)
        #expect(CropFrame.handle(at: CGPoint(x: 300, y: 95), in: rect, tolerance: 20) == .top)
        #expect(CropFrame.handle(at: CGPoint(x: 505, y: 350), in: rect, tolerance: 20) == .trailing)
        #expect(CropFrame.handle(at: CGPoint(x: 300, y: 350), in: rect, tolerance: 20) == .move)
        #expect(CropFrame.handle(at: CGPoint(x: 10, y: 10), in: rect, tolerance: 20) == nil)
    }

    @Test func draggingACornerMovesOnlyItsTwoEdges() {
        let r = CropFrame.adjust(rect, with: .topLeading, by: CGSize(width: 50, height: 60), within: bounds, minSize: minSize)
        #expect(r == CGRect(x: 150, y: 160, width: 350, height: 440))
        let e = CropFrame.adjust(rect, with: .trailing, by: CGSize(width: -100, height: 999), within: bounds, minSize: minSize)
        #expect(e == CGRect(x: 100, y: 100, width: 300, height: 500))
    }

    @Test func edgesStayInsideThePage() {
        let r = CropFrame.adjust(rect, with: .bottomTrailing, by: CGSize(width: 500, height: 500), within: bounds, minSize: minSize)
        #expect(r == CGRect(x: 100, y: 100, width: 500, height: 700))
        let l = CropFrame.adjust(rect, with: .leading, by: CGSize(width: -500, height: 0), within: bounds, minSize: minSize)
        #expect(l.minX == 0 && l.maxX == rect.maxX)
    }

    @Test func edgesCannotCrossOrShrinkBelowTheMinimum() {
        let r = CropFrame.adjust(rect, with: .leading, by: CGSize(width: 1000, height: 0), within: bounds, minSize: minSize)
        #expect(r.width == minSize.width && r.maxX == rect.maxX)
        let t = CropFrame.adjust(rect, with: .top, by: CGSize(width: 0, height: 1000), within: bounds, minSize: minSize)
        #expect(t.height == minSize.height && t.maxY == rect.maxY)
    }

    @Test func movingKeepsTheSizeAndStaysInside() {
        let r = CropFrame.adjust(rect, with: .move, by: CGSize(width: 1000, height: -1000), within: bounds, minSize: minSize)
        #expect(r.size == rect.size)
        #expect(r.maxX == bounds.maxX && r.minY == bounds.minY)
    }

    @Test func minimumSizeFollowsThePageProportionally() {
        let size = CropFrame.minimumSize(for: CGSize(width: 600, height: 800))
        #expect(size == CGSize(width: 30, height: 40))
    }
}

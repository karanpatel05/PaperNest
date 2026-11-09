#if os(iOS)
import Testing
import UIKit
@testable import PaperNestUI

@MainActor
struct ScannerPageTests {
    private func syntheticPage() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 120, height: 180), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 180))
            UIColor.red.setFill()
            context.fill(CGRect(x: 20, y: 30, width: 40, height: 80))
        }.pngData()!
    }

    @Test func rotateAndCropPreserveSource() {
        let source = syntheticPage()
        var page = ScannerPage(original: source)
        page.quarterTurns = 1
        #expect(page.rendered()?.size == CGSize(width: 180, height: 120))
        page.corners = [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.1), CGPoint(x: 0.9, y: 0.9), CGPoint(x: 0.1, y: 0.9)]
        #expect(page.rendered()?.size == CGSize(width: 144, height: 96))
        #expect(page.original == source)
        page.quarterTurns = 0
        page.corners = ScannerPage(original: source).corners
        #expect(page.rendered()?.size == CGSize(width: 120, height: 180))
    }

    @Test func filtersRemainEncodableAndSourceIsImmutable() {
        let source = syntheticPage()
        var page = ScannerPage(original: source)
        for filter in 0...2 {
            page.filter = filter
            #expect(page.rendered()?.jpegData(compressionQuality: 0.9) != nil)
            #expect(page.original == source)
        }
    }

    @Test func enhancementIsReversibleAndRetainsCropGeometry() {
        let source = syntheticPage()
        var page = ScannerPage(original: source)
        let baseline = page.rendered()?.pngData()
        page.enhanced = true
        #expect(page.rendered()?.size == CGSize(width: 120, height: 180))
        #expect(page.rendered()?.jpegData(compressionQuality: 0.9) != nil)
        #expect(page.original == source)
        page.enhanced = false
        #expect(page.rendered()?.pngData() == baseline)
        page.enhanced = true
        page.corners = [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.1), CGPoint(x: 0.9, y: 0.9), CGPoint(x: 0.1, y: 0.9)]
        #expect(page.rendered()?.size == CGSize(width: 96, height: 144))
        #expect(page.original == source)
    }

    @Test func invalidInputCannotProduceSavedPage() {
        let page = ScannerPage(original: Data([1, 2, 3]))
        #expect(page.rendered() == nil)
        #expect(ScannerPage.detectedCorners(page.original) == nil)
    }
}
#endif

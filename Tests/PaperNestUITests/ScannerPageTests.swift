#if os(iOS)
import Testing
import UIKit
import PaperNestCore
@testable import PaperNestUI

@MainActor
struct ScannerPageTests {
    /// White, 120 by 180, with a red block toward its top-left.
    private func syntheticPage(paper: UIColor = .white) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 120, height: 180), format: format).image { context in
            paper.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 180))
            UIColor.red.setFill()
            context.fill(CGRect(x: 20, y: 30, width: 40, height: 80))
        }.pngData()!
    }

    private let inset = [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.1), CGPoint(x: 0.9, y: 0.9), CGPoint(x: 0.1, y: 0.9)]

    /// Red, green and blue, 0...255, at a point measured from the top-left.
    private func pixel(_ image: UIImage?, x: Int, y: Int) throws -> (r: Int, g: Int, b: Int) {
        let cg = try #require(image?.cgImage)
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8,
                                    bytesPerRow: cg.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        let i = (y * cg.width + x) * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
    }

    @Test func rotateAndCropPreserveSource() {
        let source = syntheticPage()
        var page = ScannerPage(original: source)
        page.quarterTurns = 1
        #expect(page.rendered()?.size == CGSize(width: 180, height: 120))
        page.corners = inset
        #expect(page.rendered()?.size == CGSize(width: 144, height: 96))
        #expect(page.original == source)
        page.quarterTurns = 0
        page.corners = ScannerPage(original: source).corners
        #expect(page.rendered()?.size == CGSize(width: 120, height: 180))
    }

    @Test func everyPresetCanBeSavedAndLeavesTheCaptureAlone() {
        let source = syntheticPage()
        var page = ScannerPage(original: source)
        for preset in ScanPreset.allCases {
            page.appearance.preset = preset
            #expect(page.rendered()?.jpegData(compressionQuality: 0.9) != nil, "\(preset)")
            #expect(page.rendered()?.size == CGSize(width: 120, height: 180), "\(preset)")
            #expect(page.original == source)
        }
    }

    /// The preset is what the page is drawn with, not a label beside it.
    @Test func aPresetChangesThePictureThatIsSaved() throws {
        var page = ScannerPage(original: syntheticPage())
        let red = try pixel(page.rendered(), x: 40, y: 70)
        #expect(red.r > 200 && red.g < 80 && red.b < 80)
        page.appearance.preset = .grayscale
        let gray = try pixel(page.rendered(), x: 40, y: 70)
        #expect(abs(gray.r - gray.g) <= 2 && abs(gray.g - gray.b) <= 2, "red became \(gray)")
        page.appearance.preset = .original
        let again = try pixel(page.rendered(), x: 40, y: 70)
        #expect(again.r == red.r && again.g == red.g && again.b == red.b)
    }

    @Test func autoIsReversibleAndRetainsCropGeometry() {
        let source = syntheticPage()
        var page = ScannerPage(original: source)
        let baseline = page.rendered()?.pngData()
        page.appearance.preset = .auto
        #expect(page.rendered()?.size == CGSize(width: 120, height: 180))
        #expect(page.rendered()?.jpegData(compressionQuality: 0.9) != nil)
        #expect(page.original == source)
        page.appearance.preset = .original
        #expect(page.rendered()?.pngData() == baseline)
        page.appearance.preset = .auto
        page.corners = inset
        #expect(page.rendered()?.size == CGSize(width: 96, height: 144))
        #expect(page.original == source)
    }

    @Test func cleanupChangesThePictureAndNotTheCapture() throws {
        let source = syntheticPage(paper: UIColor(red: 0.86, green: 0.82, blue: 0.72, alpha: 1))
        var page = ScannerPage(original: source)
        let baseline = page.rendered()?.pngData()
        let tinted = try pixel(page.rendered(), x: 100, y: 160)
        page.appearance.cleanup = ScanCleanup(whitenBackground: 1)
        let whitened = try pixel(page.rendered(), x: 100, y: 160)
        #expect(tinted.b < 200 && whitened.r > 245 && whitened.g > 245 && whitened.b > 245, "paper \(tinted) became \(whitened)")
        #expect(page.rendered()?.size == CGSize(width: 120, height: 180))
        #expect(page.original == source)
        page.appearance.cleanup = .none
        #expect(page.rendered()?.pngData() == baseline)
    }

    @Test func resetUndoesTheLookTheRotationAndTheCrop() {
        let source = syntheticPage()
        var page = ScannerPage(original: source)
        let id = page.id
        let baseline = page.rendered()?.pngData()
        page.quarterTurns = 3
        page.appearance = ScanAppearance(preset: .highContrast, cleanup: .recommended)
        page.corners = inset
        page.reset()
        #expect(page.quarterTurns == 0)
        #expect(page.appearance == .original)
        #expect(page.corners == ScannerPage(original: source).corners)
        #expect(page.rendered()?.pngData() == baseline)
        #expect(page.original == source)
        #expect(page.id == id)
    }

    @Test func aCopyCarriesEveryEditUnderItsOwnIdentity() {
        var page = ScannerPage(original: syntheticPage())
        page.quarterTurns = 1
        page.appearance = ScanAppearance(preset: .blackAndWhite, cleanup: ScanCleanup(sharpenText: 0.5))
        page.corners = inset
        let copy = page.copy()
        #expect(copy.id != page.id)
        #expect(copy.original == page.original)
        #expect(copy.quarterTurns == 1 && copy.appearance == page.appearance && copy.corners == page.corners)
    }

    /// Thumbnails and the preview redraw when this changes, and only then.
    @Test func theDrawKeyChangesWithAnythingThatChangesThePicture() {
        var page = ScannerPage(original: syntheticPage())
        var seen = Set([page.drawKey])
        page.quarterTurns = 1; #expect(seen.insert(page.drawKey).inserted)
        page.appearance.preset = .auto; #expect(seen.insert(page.drawKey).inserted)
        page.appearance.cleanup.removeShadows = 0.25; #expect(seen.insert(page.drawKey).inserted)
        page.appearance.cleanup.whitenBackground = 0.25; #expect(seen.insert(page.drawKey).inserted)
        page.appearance.cleanup.sharpenText = 0.25; #expect(seen.insert(page.drawKey).inserted)
        page.corners = inset; #expect(seen.insert(page.drawKey).inserted)
        let same = page
        #expect(same.drawKey == page.drawKey)
    }

    @Test func aPreviewIsNoLargerThanAskedAndKeepsTheLook() throws {
        var page = ScannerPage(original: syntheticPage())
        page.appearance.preset = .grayscale
        let preview = try #require(page.rendered(maxDimension: 60))
        #expect(preview.size == CGSize(width: 40, height: 60))
        let block = try pixel(preview, x: 13, y: 23)
        #expect(abs(block.r - block.g) <= 2 && abs(block.g - block.b) <= 2 && block.r < 200, "the red block is \(block)")
    }

    /// The Cleanup sheet draws its before and after from one small picture
    /// of the page instead of the capture. Turned pages must come out turned.
    @Test func theCleanupSheetsPictureIsThePageWithoutItsLook() throws {
        var page = ScannerPage(original: syntheticPage())
        page.appearance.preset = .grayscale
        page.quarterTurns = 1
        let base = try #require(page.base(maxDimension: 60))
        #expect(base.width == 40 && base.height == 60, "the base is not turned: turning is the preview's job")
        let before = try #require(ScannerPage.preview(of: base, appearance: .original, quarterTurns: 1))
        #expect(before.size == CGSize(width: 60, height: 40))
        let after = try #require(ScannerPage.preview(of: base, appearance: page.appearance, quarterTurns: 0))
        let block = try pixel(after, x: 13, y: 23)
        #expect(abs(block.r - block.g) <= 2 && abs(block.g - block.b) <= 2, "the red block is \(block)")
    }

    @Test func invalidInputCannotProduceSavedPage() {
        let page = ScannerPage(original: Data([1, 2, 3]))
        #expect(page.rendered() == nil)
        #expect(page.base(maxDimension: 60) == nil)
        #expect(ScannerPage.detectedCorners(page.original) == nil)
    }
}
#endif

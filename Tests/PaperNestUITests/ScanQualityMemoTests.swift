#if os(iOS)
import CoreImage
import Testing
import UIKit
import PaperNestCore
@testable import PaperNestUI

/// The scanner's memo of measurements: it keeps only the scan in progress
/// (it lives as long as the app, and otherwise every capture would be
/// compared with every page scanned since launch), and of two photographs of
/// one page it marks the one worth deleting.
@MainActor
struct ScanQualityMemoTests {
    /// A page of print, different for each `seed`; `shift` moves the print
    /// a few points, as a second photograph would sit, and `blur` softens it.
    private func page(seed: Int, shift: CGFloat = 0, blur: Double = 0) -> ScannerPage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let words = ["report", "growth", "region", "costs", "orders", "spring", "summer", "teams", "stores", "north"]
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 780), format: format).image { context in
            UIColor(white: shift > 0 ? 0.95 : 1, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 780))
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.black]
            for line in 0..<40 {
                let text = (0..<9).map { words[(seed * 7 + line * 3 + $0 * ($0 + seed)) % words.count] }.joined(separator: " ")
                (text as NSString).draw(at: CGPoint(x: 40 + shift, y: 30 + shift + CGFloat(line) * 18), withAttributes: attributes)
            }
        }
        guard blur > 0, let source = CIImage(image: image) else { return ScannerPage(original: image.pngData()!) }
        let soft = source.clampedToExtent().applyingGaussianBlur(sigma: blur).cropped(to: source.extent)
        let drawn = CIContext().createCGImage(soft, from: source.extent)!
        return ScannerPage(original: UIImage(cgImage: drawn).pngData()!)
    }

    private func measured(_ pages: [ScannerPage]) async -> ScanQualityMemo {
        let memo = ScanQualityMemo()
        for each in pages { await memo.measure(each, among: pages) }
        return memo
    }

    /// The natural way to fix a blurred capture is to take it again; the
    /// mark then belongs on the blurred one, naming the good retake — not on
    /// the retake, which would invite deleting the good page.
    @Test func theBlurredPageOfARepeatIsMarkedNotItsSharpRetake() async {
        let pages = [page(seed: 1, blur: 4), page(seed: 1, shift: 6)]
        let memo = await measured(pages)
        #expect(memo.issues(for: pages[0]) == [.blurry])
        #expect(memo.issues(for: pages[1]).isEmpty)
        #expect(memo.repeated(pages[0], among: pages) == 1, "the blurred first page should name its sharp retake")
        #expect(memo.repeated(pages[1], among: pages) == nil, "the good retake should be left alone")
    }

    /// The other way round, the blurred page is still the one marked.
    @Test func aBlurredRetakeOfAGoodPageIsMarked() async {
        let pages = [page(seed: 1), page(seed: 1, shift: 6, blur: 4)]
        let memo = await measured(pages)
        #expect(memo.repeated(pages[1], among: pages) == 0)
        #expect(memo.repeated(pages[0], among: pages) == nil)
    }

    /// Two good photographs of one page: the later is the extra copy.
    @Test func ofTwoGoodPhotographsTheLaterIsMarked() async {
        let pages = [page(seed: 1), page(seed: 1, shift: 6), page(seed: 2)]
        let memo = await measured(pages)
        #expect(memo.repeated(pages[1], among: pages) == 0)
        #expect(memo.repeated(pages[0], among: pages) == nil)
        #expect(memo.repeated(pages[2], among: pages) == nil, "another page is no one's repeat")
    }

    @Test func measuringAPageForgetsPagesNoLongerInTheScan() async {
        let memo = ScanQualityMemo()
        let earlier = [page(seed: 1), page(seed: 2)]
        for each in earlier { await memo.measure(each, among: earlier) }
        #expect(memo.measuredCount == 2)
        #expect(memo.comparedCount == 1)

        // A new scan: the earlier pages are gone from it.
        let current = [page(seed: 3)]
        await memo.measure(current[0], among: current)
        #expect(memo.measuredCount == 1, "pages from an earlier scan are still kept")
        #expect(memo.comparedCount == 0, "pairs from an earlier scan are still kept")
    }

    /// A page deleted from the scan is forgotten, and a new page is compared
    /// only with the pages still in it.
    @Test func aDeletedPageIsForgottenAndNotComparedWith() async {
        let memo = ScanQualityMemo()
        let pages = [page(seed: 1), page(seed: 2), page(seed: 3)]
        for each in pages { await memo.measure(each, among: pages) }
        #expect(memo.comparedCount == 3)
        let remaining = [pages[0], pages[2], page(seed: 4)]
        await memo.measure(remaining[2], among: remaining)
        #expect(memo.measuredCount == 3)
        // 1–3 kept, and 4 compared with 1 and 3; nothing with the deleted 2.
        #expect(memo.comparedCount == 3)
    }
}
#endif

#if os(iOS)
import Testing
import UIKit
import PaperNestCore
@testable import PaperNestUI

/// The scanner's memo of measurements lives as long as the app, so it must
/// keep only the scan in progress: otherwise every capture is compared with
/// every page scanned since launch, and memory grows with each one.
@MainActor
struct ScanQualityMemoTests {
    /// A page of print, different for each `seed`.
    private func page(seed: Int) -> ScannerPage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let words = ["report", "growth", "region", "costs", "orders", "spring", "summer", "teams", "stores", "north"]
        let data = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 780), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 780))
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.black]
            for line in 0..<40 {
                let text = (0..<9).map { words[(seed * 7 + line * 3 + $0 * ($0 + seed)) % words.count] }.joined(separator: " ")
                (text as NSString).draw(at: CGPoint(x: 40, y: 30 + CGFloat(line) * 18), withAttributes: attributes)
            }
        }.pngData()!
        return ScannerPage(original: data)
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

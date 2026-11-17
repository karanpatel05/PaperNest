import CoreGraphics
import Foundation
import PaperNestCore
import PaperNestStore

/// Compares two documents' pages: reads each page's words and draws each
/// page small and in grey to match the pages up (`PageAlignment`), then draws
/// each matched pair larger to compare their pictures.
///
/// Nothing is stored. Each page is read and drawn as it is now, marks
/// included, so a drawing someone added shows as a difference in the picture
/// even where the words agree.
public struct DocumentComparer: Sendable {
    private let renderer: PageRenderer

    /// The longer side, in pixels, of the picture each page is matched by:
    /// about 1.4 pixels per millimetre on Letter, enough to tell pages apart.
    public static let pictureSide: CGFloat = 400
    /// The longer side of the pictures a matched pair is compared by: about
    /// 5.7 pixels per millimetre on Letter, so 10-point print is some 20
    /// pixels tall. At `pictureSide`, a changed digit in body text was missed.
    public static let detailSide: CGFloat = 1600
    /// Cells of the picture comparison, in pixels of the detail pictures.
    public static let cellSide = 8

    public init(renderer: PageRenderer) {
        self.renderer = renderer
    }

    /// One page as the comparison sees it. A page whose words cannot be read
    /// is compared by its picture; one that cannot be drawn is an error.
    public func comparedPage(_ page: Page) async throws -> ComparedPage {
        let layout: PageTextLayout
        do { layout = try await renderer.textLayout(for: page) } catch is CancellationError {
            throw CancellationError()
        } catch { layout = .empty }
        let image = try await renderer.renderThumbnail(page, maxPixelSize: Self.pictureSide)
        guard let picture = Self.gray(image) else { throw RenderError.contextCreationFailed }
        return ComparedPage(text: layout.comparisonText, picture: picture, geometry: page.geometry)
    }

    /// `progress` is told the share done, from 0 to 1, after each page read
    /// and each pair compared.
    public func compare(old: [Page], new: [Page],
                        progress: @Sendable (Double) async -> Void = { _ in }) async throws -> DocumentComparison {
        // Reading a page counts once; comparing a pair, drawn twice and larger, four times.
        var total = Double(max(1, old.count + new.count + 4 * min(old.count, new.count)))
        var done = 0.0
        var oldPages: [ComparedPage] = [], newPages: [ComparedPage] = []
        for page in old {
            try Task.checkCancellation()
            oldPages.append(try await comparedPage(page))
            done += 1; await progress(done / total)
        }
        for page in new {
            try Task.checkCancellation()
            newPages.append(try await comparedPage(page))
            done += 1; await progress(done / total)
        }
        try Task.checkCancellation()
        let entries = PageAlignment.align(old: oldPages.map(\.signature), new: newPages.map(\.signature))
        let pairs = entries.filter { if case .matched = $0 { true } else { false } }.count
        total = Double(old.count + new.count + 4 * pairs)
        var pages: [PageComparison] = []
        for entry in entries {
            try Task.checkCancellation()
            switch entry {
            case .matched(let i, let j, let moved):
                let detailOld = try await detailPicture(old[i])
                let detailNew = try await detailPicture(new[j])
                pages.append(PageComparison.compare(oldPages[i], newPages[j], oldIndex: i, newIndex: j, moved: moved,
                                                    detail: (detailOld, detailNew),
                                                    columns: max(1, detailOld.width / Self.cellSide)))
                done += 4; await progress(min(1, done / total))
            case .removed(let i): pages.append(PageComparison(oldIndex: i, newIndex: nil))
            case .added(let j): pages.append(PageComparison(oldIndex: nil, newIndex: j))
            }
        }
        return DocumentComparison(pages: pages)
    }

    /// A page drawn at `detailSide`, in grey; internal so the cleanup confirms with the same picture.
    func detailPicture(_ page: Page) async throws -> GrayPicture {
        let image = try await renderer.renderThumbnail(page, maxPixelSize: Self.detailSide)
        guard let picture = Self.gray(image) else { throw RenderError.contextCreationFailed }
        return picture
    }

    /// The picture in shades of grey, row by row from the top, on white.
    static func gray(_ image: CGImage, width: Int? = nil, height: Int? = nil) -> GrayPicture? {
        let width = width ?? image.width, height = height ?? image.height
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height)
        return GrayPicture(width: width, height: height, pixels: Array(UnsafeBufferPointer(start: bytes, count: width * height)))
    }

    /// The two pages laid over each other: what only the old page has in
    /// red, what only the new page has in green, and what both have in its
    /// own shade of grey. The new page is stretched onto the old one's size.
    ///
    /// Red, green, black: for each pixel, with `o` and `n` the old and new
    /// pages' shades (0 black … 1 white), the colour is (n, o, o·n).
    public static func overlay(old: CGImage, new: CGImage) -> CGImage? {
        guard let a = gray(old), let b = gray(new, width: old.width, height: old.height) else { return nil }
        let width = a.width, height = a.height
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for index in 0..<(width * height) {
            let o = Int(a.pixels[index]), n = Int(b.pixels[index])
            rgba[index * 4] = UInt8(n)
            rgba[index * 4 + 1] = UInt8(o)
            rgba[index * 4 + 2] = UInt8(o * n / 255)
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

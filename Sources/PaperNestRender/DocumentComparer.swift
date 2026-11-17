import CoreGraphics
import Foundation
import PaperNestCore
import PaperNestStore

/// Compares two documents' pages: reads each page's words, draws each page
/// once, small and in grey, and hands both to `DocumentComparison`.
///
/// Nothing is stored. Each page is read and drawn as it is now, marks
/// included, so a drawing someone added shows as a difference in the picture
/// even where the words agree.
public struct DocumentComparer: Sendable {
    private let renderer: PageRenderer

    /// The longer side, in pixels, of the picture each page is compared at.
    /// About 2.6 pixels per millimetre on Letter: enough to see a changed
    /// stamp or signature, and a page drawn this small costs little.
    public static let pictureSide: CGFloat = 400

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

    /// `progress` is told the share done, from 0 to 1, after each page.
    public func compare(old: [Page], new: [Page],
                        progress: @Sendable (Double) async -> Void = { _ in }) async throws -> DocumentComparison {
        let total = Double(max(1, old.count + new.count))
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
        return DocumentComparison.compare(old: oldPages, new: newPages)
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

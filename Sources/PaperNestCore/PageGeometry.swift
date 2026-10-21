import CoreGraphics
import Foundation

/// The single source of truth for page coordinates.
///
/// Spaces, all in points:
/// - **Source/content space**: upright, uncropped content, top-left origin,
///   y down, size `sourceSize`. Ink, text and OCR boxes live here.
/// - **Page space**: what the user sees and what export produces: the crop
///   applied, then the clockwise rotation. Top-left origin, y down, size
///   `pageSize`.
///
/// Drawing code composes `sourceToPage` with a page-to-device transform, so
/// on-screen display, thumbnails and every export path share one mapping.
public struct PageGeometry: Hashable, Sendable {
    public var sourceSize: CGSize
    public var crop: NormalizedRect
    public var rotation: QuarterTurns

    public init(sourceSize: CGSize, crop: NormalizedRect = .full, rotation: QuarterTurns = .none) {
        self.sourceSize = sourceSize
        self.crop = crop
        self.rotation = rotation
    }

    /// The crop rectangle in source points.
    public var cropRect: CGRect { crop.denormalized(in: sourceSize) }

    public var pageSize: CGSize {
        let c = cropRect.size
        return rotation.swapsAxes ? CGSize(width: c.height, height: c.width) : c
    }

    /// Maps source space to page space (both y-down).
    public var sourceToPage: CGAffineTransform {
        let c = cropRect
        let toCropped = CGAffineTransform(translationX: -c.minX, y: -c.minY)
        let w = c.width, h = c.height
        // Clockwise rotation in a y-down space, re-anchored at the origin.
        let rotate: CGAffineTransform = switch rotation {
        case .none: .identity
        case .clockwise90: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)
        case .half: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h)
        case .clockwise270: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)
        }
        return toCropped.concatenating(rotate)
    }

    public var pageToSource: CGAffineTransform { sourceToPage.inverted() }

    /// Maps a box normalized to the source (e.g. an OCR line) into page space.
    public func pageRect(forNormalizedSourceRect r: NormalizedRect) -> CGRect {
        r.denormalized(in: sourceSize).applying(sourceToPage)
    }

    // MARK: - Crop editing

    /// The same page with no crop: what a crop editor shows, rotated as the
    /// user sees it.
    public var uncropped: PageGeometry {
        PageGeometry(sourceSize: sourceSize, crop: .full, rotation: rotation)
    }

    /// The current crop as a rectangle on the uncropped, rotated page
    /// (points, y-down).
    public var cropRectInUncroppedPage: CGRect {
        cropRect.applying(uncropped.sourceToPage)
    }

    /// Converts a rectangle drawn on the uncropped, rotated page back into a
    /// crop of the upright source, the space crops are stored in.
    public func crop(fromUncroppedPageRect rect: CGRect) -> NormalizedRect {
        let source = rect.applying(uncropped.pageToSource)
        return NormalizedRect(
            x: source.minX / sourceSize.width,
            y: source.minY / sourceSize.height,
            width: source.width / sourceSize.width,
            height: source.height / sourceSize.height
        )
    }

    // MARK: - Native content spaces

    /// The upright size of a PDF page whose box is `box` and whose `/Rotate`
    /// is `rotationDegrees` (clockwise).
    public static func uprightPDFSize(box: CGRect, rotationDegrees: Int) -> CGSize {
        QuarterTurns(normalizingDegrees: rotationDegrees).swapsAxes
            ? CGSize(width: box.height, height: box.width)
            : box.size
    }

    /// Maps PDF page space (y up, origin at `box.origin`, unrotated) into
    /// upright source space (y down, top-left origin), honoring `/Rotate`.
    public static func pdfToSource(box: CGRect, rotationDegrees: Int) -> CGAffineTransform {
        let w = box.width, h = box.height
        let toOrigin = CGAffineTransform(translationX: -box.minX, y: -box.minY)
        let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h)
        let rotate: CGAffineTransform = switch QuarterTurns(normalizingDegrees: rotationDegrees) {
        case .none: .identity
        case .clockwise90: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)
        case .half: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h)
        case .clockwise270: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)
        }
        return toOrigin.concatenating(flip).concatenating(rotate)
    }

    /// Core Graphics draws images y-up into a rect. In a y-down space,
    /// concatenate this before drawing an image into `rect` so it appears
    /// upright there (a flip about the rectangle's horizontal midline).
    public static func yUpToYDown(in rect: CGRect) -> CGAffineTransform {
        CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: rect.minY + rect.maxY)
    }
}

/// Raster images rarely carry trustworthy resolution: phone cameras write 72
/// dpi for 4000-pixel photos. This policy decides a page size in points.
public enum ImageResolutionPolicy {
    /// Resolution metadata at or below this is treated as "unknown".
    static let untrustedDPI = 72.5
    /// Unknown-resolution images are sized as a document whose long edge is
    /// 11 in (US Letter height), preserving aspect ratio.
    public static let assumedLongEdgePoints: CGFloat = 792

    public static func pointSize(pixelSize: CGSize, dpi: CGSize?) -> CGSize {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return .zero }
        if let dpi, dpi.width > untrustedDPI, dpi.height > untrustedDPI {
            return CGSize(width: pixelSize.width * 72 / dpi.width, height: pixelSize.height * 72 / dpi.height)
        }
        let scale = assumedLongEdgePoints / max(pixelSize.width, pixelSize.height)
        return CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
    }
}

public enum PaperSize: String, Codable, Sendable, CaseIterable {
    /// Each page keeps its own size.
    case original
    case usLetter
    case a4

    /// Portrait dimensions in points.
    public var portraitSize: CGSize? {
        switch self {
        case .original: nil
        case .usLetter: CGSize(width: 612, height: 792)
        case .a4: CGSize(width: 595.2756, height: 841.8898)
        }
    }
}

/// Places a page on output paper. Content is always scaled to fit whole, so
/// nothing is ever cropped to make a page fit a paper size; paper
/// orientation follows the page's orientation.
public struct PaperLayout: Hashable, Sendable {
    public var paperSize: CGSize
    /// Where the page lands on the paper, y-down.
    public var contentRect: CGRect

    public init(pageSize: CGSize, paper: PaperSize, margin: CGFloat = 0) {
        guard let portrait = paper.portraitSize else {
            paperSize = pageSize
            contentRect = CGRect(origin: .zero, size: pageSize)
            return
        }
        let landscape = pageSize.width > pageSize.height
        let sheet = landscape ? CGSize(width: portrait.height, height: portrait.width) : portrait
        let avail = CGRect(origin: .zero, size: sheet).insetBy(dx: margin, dy: margin)
        let scale = min(avail.width / pageSize.width, avail.height / pageSize.height)
        let fitted = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
        paperSize = sheet
        contentRect = CGRect(
            x: avail.minX + (avail.width - fitted.width) / 2,
            y: avail.minY + (avail.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    /// Maps page space (y-down) onto the paper (y-down).
    public func pageToPaper(pageSize: CGSize) -> CGAffineTransform {
        let sx = contentRect.width / pageSize.width
        let sy = contentRect.height / pageSize.height
        return CGAffineTransform(a: sx, b: 0, c: 0, d: sy, tx: contentRect.minX, ty: contentRect.minY)
    }
}

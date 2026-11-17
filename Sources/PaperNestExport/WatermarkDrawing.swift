import CoreGraphics
import CoreText
import Foundation
import PaperNestCore

/// One drawn copy of a watermark on a page.
public struct WatermarkMark: Hashable, Sendable {
    /// Page space: points, origin at the top-left, y down.
    public var center: CGPoint
    /// Before rotation.
    public var size: CGSize
    /// Radians, turning clockwise as seen on the page.
    public var angle: CGFloat

    /// The smallest upright rectangle holding the turned mark.
    public var boundingBox: CGRect {
        let extent = WatermarkDrawing.rotatedExtent(size, angle: angle)
        return CGRect(x: center.x - extent.width / 2, y: center.y - extent.height / 2,
                      width: extent.width, height: extent.height)
    }
}

/// Lays out and draws a `Watermark`. The export writes it into PDF pages and
/// page pictures through `draw`, and the export sheet's preview draws the
/// same marks through the same function, so the preview cannot show
/// something the file will not contain.
///
/// **Letters are drawn as outlines, not as text.** A word drawn as text would
/// be picked up by every reader's search, copy and text extraction —
/// "CONFIDENTIAL" in the middle of a contract's copied paragraph, or a
/// search hit on every page. As shapes it is seen and never read.
public enum WatermarkDrawing {
    /// Sizes are shares of the page: one unit is a point on a US Letter page,
    /// measured on the page's shorter side, so a mark on an A5 page or a huge
    /// scan looks the same relative to the paper.
    static func unit(for pageSize: CGSize) -> CGFloat { max(min(pageSize.width, pageSize.height), 1) / 612 }

    /// Distance from the page edge to a corner mark, in units.
    static let cornerMargin: CGFloat = 24

    /// The marks `watermark` draws on a page of `pageSize` points. Empty when
    /// the watermark has nothing to draw.
    public static func marks(for watermark: Watermark, pageSize: CGSize) -> [WatermarkMark] {
        layout(for: watermark, pageSize: pageSize).marks
    }

    /// Draws `watermark` over a page of `pageSize` points.
    ///
    /// The context's transform must map page space — points, origin at the
    /// top-left, y down — onto the page. Callers drawing into a PDF page or a
    /// bitmap, both y-up, flip first. Drawing is clipped to the page and
    /// leaves the context's state as it found it.
    public static func draw(_ watermark: Watermark, pageSize: CGSize, in ctx: CGContext) {
        let (art, marks) = layout(for: watermark, pageSize: pageSize)
        guard let art, !marks.isEmpty else { return }
        let color = watermark.color
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.clip(to: CGRect(origin: .zero, size: pageSize))
        // One transparency group for every mark, so overlapping tiles and a
        // capsule's letters over its own tint are not darkened twice. Bounded
        // to the marks: an unbounded layer is a second page-sized buffer, and
        // a picture of a large page is already hundreds of megabytes.
        let page = CGRect(origin: .zero, size: pageSize)
        let covered = marks.reduce(CGRect.null) { $0.union($1.boundingBox) }.insetBy(dx: -2, dy: -2).intersection(page)
        guard !covered.isNull, !covered.isEmpty else { return }
        ctx.setAlpha(CGFloat(watermark.opacity))
        ctx.beginTransparencyLayer(in: covered, auxiliaryInfo: nil)
        for mark in marks {
            ctx.saveGState()
            ctx.translateBy(x: mark.center.x, y: mark.center.y)
            ctx.rotate(by: mark.angle)
            ctx.translateBy(x: -art.size.width / 2, y: -art.size.height / 2)
            art.draw(shape: watermark.shape, color: color, in: ctx)
            ctx.restoreGState()
        }
        ctx.endTransparencyLayer()
    }

    /// `image`, a picture of a page `pageSize` points large, with
    /// `watermark` drawn over it at the picture's own resolution. The image
    /// export draws through this, and so does the export sheet's preview.
    /// The picture is returned unchanged when there is nothing to draw.
    public static func applying(_ watermark: Watermark, to image: CGImage, pageSize: CGSize) throws -> CGImage {
        try applying([watermark], to: image, pageSize: pageSize)
    }

    /// Every mark in `marks` over one copy of the picture, in order. One copy
    /// rather than one per mark: a picture of a large page is hundreds of
    /// megabytes, and a free export with a watermark chosen draws two.
    public static func applying(_ marks: [Watermark], to image: CGImage, pageSize: CGSize) throws -> CGImage {
        let marks = marks.filter(\.isVisible)
        guard !marks.isEmpty, pageSize.width > 0, pageSize.height > 0 else { return image }
        let width = image.width, height = image.height
        // Opaque, like the picture it is drawn over: a page picture leaving
        // the app is already on white paper (`renderImage`).
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw ExportError.writeFailed }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Bitmap space is y-up in pixels; page space is y-down in points.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: CGFloat(width) / pageSize.width, y: -CGFloat(height) / pageSize.height)
        for mark in marks { draw(mark, pageSize: pageSize, in: ctx) }
        guard let result = ctx.makeImage() else { throw ExportError.writeFailed }
        return result
    }

    // MARK: - Layout

    private static func layout(for watermark: Watermark, pageSize: CGSize) -> (art: Art?, marks: [WatermarkMark]) {
        guard watermark.isVisible, pageSize.width > 0, pageSize.height > 0 else { return (nil, []) }
        let u = unit(for: pageSize)
        let angle = CGFloat(watermark.rotation * .pi / 180)
        let margin = cornerMargin * u
        var fontSize = baseFontSize(watermark.shape, placement: watermark.placement) * u
        var art = Art(watermark, fontSize: fontSize)

        // The room a mark may take, after which it is made smaller to fit:
        // most of the page in the middle, inside the margins in a corner.
        let room: CGSize = switch watermark.placement {
        case .center: CGSize(width: pageSize.width * 0.85, height: pageSize.height * 0.85)
        case .topRight, .bottomRight, .bottomLeft:
            CGSize(width: pageSize.width - 2 * margin, height: pageSize.height - 2 * margin)
        case .tiled:
            // Half the page at most, so long text still repeats rather than
            // becoming three marks that each nearly fill the page.
            CGSize(width: min(pageSize.width - 2 * margin, pageSize.width * 0.5),
                   height: min(pageSize.height - 2 * margin, pageSize.height * 0.5))
        }
        let extent = rotatedExtent(art.size, angle: angle)
        let fit = min(1, room.width / max(extent.width, 0.001), room.height / max(extent.height, 0.001))
        if fit < 1 {
            fontSize *= fit
            art = Art(watermark, fontSize: fontSize)
        }
        let box = rotatedExtent(art.size, angle: angle)

        func mark(at center: CGPoint) -> WatermarkMark { WatermarkMark(center: center, size: art.size, angle: angle) }
        switch watermark.placement {
        case .center:
            return (art, [mark(at: CGPoint(x: pageSize.width / 2, y: pageSize.height / 2))])
        case .topRight:
            return (art, [mark(at: CGPoint(x: pageSize.width - margin - box.width / 2, y: margin + box.height / 2))])
        case .bottomRight:
            return (art, [mark(at: CGPoint(x: pageSize.width - margin - box.width / 2,
                                           y: pageSize.height - margin - box.height / 2))])
        case .bottomLeft:
            return (art, [mark(at: CGPoint(x: margin + box.width / 2, y: pageSize.height - margin - box.height / 2))])
        case .tiled:
            // Rows offset by half a step, like brickwork, starting beyond the
            // page's edges so the paper is covered right to its corners.
            let gap = 36 * u
            let stepX = box.width + gap, stepY = box.height + gap
            var marks: [WatermarkMark] = []
            var row = 0
            var y = -stepY / 2
            while y < pageSize.height + stepY {
                var x = (row.isMultiple(of: 2) ? 0 : stepX / 2) - stepX / 2
                while x < pageSize.width + stepX {
                    let candidate = mark(at: CGPoint(x: x, y: y))
                    if candidate.boundingBox.intersects(CGRect(origin: .zero, size: pageSize)) { marks.append(candidate) }
                    x += stepX
                }
                y += stepY
                row += 1
            }
            return (art, marks)
        }
    }

    /// Starting letter height in units, before a mark is made smaller to fit.
    private static func baseFontSize(_ shape: WatermarkShape, placement: WatermarkPlacement) -> CGFloat {
        switch placement {
        case .center:
            switch shape { case .text: 120; case .capsule: 40; case .stamp: 56; case .brand: 64 }
        case .tiled:
            switch shape { case .text: 30; case .capsule: 14; case .stamp: 20; case .brand: 22 }
        case .topRight, .bottomRight, .bottomLeft:
            // The brand in a corner is the free-export mark: small enough to
            // leave the page usable, large enough to read.
            switch shape { case .text: 16; case .capsule: 12; case .stamp: 18; case .brand: 11 }
        }
    }

    /// Whether `text` draws anything at all. A colour emoji has no outline.
    static func hasInk(_ text: String) -> Bool {
        !GlyphRun(text, fontSize: 10, emphasized: true, tracking: 0).path.isEmpty
    }

    static func rotatedExtent(_ size: CGSize, angle: CGFloat) -> CGSize {
        let c = abs(cos(angle)), s = abs(sin(angle))
        return CGSize(width: size.width * c + size.height * s, height: size.width * s + size.height * c)
    }

    // MARK: - Art

    /// One mark, unrotated, with its top-left corner at the origin.
    private struct Art {
        let size: CGSize
        let fontSize: CGFloat
        let main: GlyphRun
        let date: GlyphRun?
        let mainOrigin: CGPoint
        let dateOrigin: CGPoint
        /// The `.brand` shape's logo and where it sits; nil for other shapes
        /// or a brand mark built without one.
        let logo: (mask: CGImage, frame: CGRect)?

        init(_ watermark: Watermark, fontSize: CGFloat) {
            self.fontSize = fontSize
            let shape = watermark.shape
            // Spaced capitals for a large word across the page, as the design
            // asks for CONFIDENTIAL; a little for the smaller shapes; the
            // brand's name keeps its own spacing.
            let tracking: CGFloat = switch shape { case .text: 0.08; case .capsule, .stamp: 0.04; case .brand: 0.01 }
            main = GlyphRun(watermark.drawnText, fontSize: fontSize, emphasized: true, tracking: tracking)
            date = watermark.drawnDateLine.map { GlyphRun($0, fontSize: fontSize * 0.5, emphasized: false, tracking: 0.02) }
            let gap = date == nil ? 0 : fontSize * 0.18
            let textWidth = max(main.size.width, date?.size.width ?? 0)
            let textHeight = main.size.height + gap + (date?.size.height ?? 0)
            // The logo is a square as tall as the name's line, set before it.
            let logoSide: CGFloat = shape == .brand && watermark.logo != nil ? main.size.height * 1.1 : 0
            let logoGap: CGFloat = logoSide > 0 ? fontSize * 0.3 : 0
            let contentWidth = logoSide + logoGap + textWidth
            let contentHeight = max(textHeight, logoSide)
            let padding: CGSize = switch shape {
            case .text, .brand: .zero
            case .capsule: CGSize(width: fontSize * 0.85, height: fontSize * 0.55)
            case .stamp: CGSize(width: fontSize * 0.75, height: fontSize * 0.5)
            }
            size = CGSize(width: contentWidth + 2 * padding.width, height: contentHeight + 2 * padding.height)
            let textLeft = padding.width + logoSide + logoGap
            let textTop = padding.height + (contentHeight - textHeight) / 2
            mainOrigin = CGPoint(x: textLeft + (textWidth - main.size.width) / 2, y: textTop)
            dateOrigin = CGPoint(x: textLeft + (textWidth - (date?.size.width ?? 0)) / 2,
                                 y: textTop + main.size.height + gap)
            if logoSide > 0, let mark = watermark.logo {
                logo = (mark.mask, CGRect(x: padding.width, y: padding.height + (contentHeight - logoSide) / 2,
                                          width: logoSide, height: logoSide))
            } else {
                logo = nil
            }
        }

        func draw(shape: WatermarkShape, color: RGBAColor, in ctx: CGContext) {
            let ink = CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
            let frame = CGRect(origin: .zero, size: size)
            switch shape {
            case .text:
                break
            case .brand:
                if let logo {
                    // The mask is an image, drawn y-up: flip within its own
                    // square, then paint the watermark's colour through it.
                    ctx.saveGState()
                    ctx.translateBy(x: logo.frame.minX, y: logo.frame.maxY)
                    ctx.scaleBy(x: 1, y: -1)
                    let square = CGRect(origin: .zero, size: logo.frame.size)
                    ctx.clip(to: square, mask: logo.mask)
                    ctx.setFillColor(ink)
                    ctx.fill(square)
                    ctx.restoreGState()
                }
            case .capsule:
                // Never more than half the shorter side: one narrow letter
                // ("I", "1") makes a capsule narrower than it is tall.
                let radius = min(size.height / 2, size.width / 2, fontSize * 1.2)
                ctx.addPath(CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil))
                ctx.setFillColor(CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 0.16))
                ctx.fillPath()
            case .stamp:
                let line = max(fontSize * 0.11, 0.5)
                let inset = frame.insetBy(dx: line / 2, dy: line / 2)
                // Fully rounded, as in the mockup; a two-line stamp with a date
                // keeps rounded corners rather than becoming a lozenge.
                let radius = min(inset.height / 2, inset.width / 2, fontSize * 0.9)
                ctx.addPath(CGPath(roundedRect: inset, cornerWidth: radius, cornerHeight: radius, transform: nil))
                ctx.setStrokeColor(ink)
                ctx.setLineWidth(line)
                ctx.strokePath()
            }
            ctx.setFillColor(ink)
            main.fill(at: mainOrigin, in: ctx)
            date?.fill(at: dateOrigin, in: ctx)
        }
    }

    /// A line of text as glyph outlines, in page space (y down), with its
    /// typographic box's top-left corner at the origin.
    private struct GlyphRun {
        let path: CGPath
        let size: CGSize

        /// Letters are shaped at one size and scaled. The system font
        /// changes its letterforms with size (optical sizes), so shaping at
        /// the size drawn would make a mark on an A5 page, a Letter page and
        /// the export sheet's small preview each a slightly different shape.
        private static let referenceSize: CGFloat = 100

        init(_ string: String, fontSize: CGFloat, emphasized: Bool, tracking: CGFloat) {
            let reference = Self.referenceSize
            let font = CTFontCreateUIFontForLanguage(emphasized ? .emphasizedSystem : .system, reference, nil)
                ?? CTFontCreateWithName((emphasized ? "Helvetica-Bold" : "Helvetica") as CFString, reference, nil)
            let attributed = NSAttributedString(string: string, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTKernAttributeName as String): reference * tracking,
            ])
            let line = CTLineCreateWithAttributedString(attributed)
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            // Tracking adds space after the last letter too; leave it off so
            // the word is centred on what is drawn.
            let trailing = string.isEmpty ? 0 : reference * tracking
            let scale = fontSize / reference
            size = CGSize(width: max(width - trailing, 0) * scale, height: (ascent + descent) * scale)

            // Core Text is y-up from the baseline; page space is y-down from
            // the top of the line. One flip, then each glyph at its position,
            // then down to the size asked for.
            let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: ascent)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            let outline = CGMutablePath()
            let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
            for run in runs {
                let count = CTRunGetGlyphCount(run)
                guard count > 0 else { continue }
                let attributes = CTRunGetAttributes(run) as NSDictionary
                // A character the font lacks is drawn from a fallback font,
                // which Core Text names on the run.
                var runFont = font
                if let value = attributes[kCTFontAttributeName as String],
                   CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID() {
                    runFont = value as! CTFont
                }
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
                for index in 0..<count {
                    var place = CGAffineTransform(translationX: positions[index].x, y: positions[index].y)
                    guard let glyph = CTFontCreatePathForGlyph(runFont, glyphs[index], &place) else { continue }
                    outline.addPath(glyph, transform: flip)
                }
            }
            path = outline
        }

        func fill(at origin: CGPoint, in ctx: CGContext) {
            ctx.saveGState()
            ctx.translateBy(x: origin.x, y: origin.y)
            ctx.addPath(path)
            ctx.fillPath()
            ctx.restoreGState()
        }
    }
}

import CoreGraphics
import Foundation
import ImageIO
import PaperNestCore
import PaperNestStore

public enum RenderError: Error, Equatable, Sendable {
    /// The page's original is not on this device (e.g. not downloaded yet).
    case sourceUnavailable
    case sourceDamaged
    case outputTooLarge
    case contextCreationFailed
}

/// Draws pages for display, thumbnails and export. Every path goes through
/// `draw(_:source:in:pageToContext:)`, so what is exported matches what is
/// shown.
public struct PageRenderer: Sendable {
    public let store: LibraryStore
    let cache: SourceCache

    /// Largest bitmap the renderer will allocate (about 400 MB at RGBA8).
    public static let maxPixelCount = 100_000_000

    public init(store: LibraryStore, cacheCapacity: Int = 6) {
        self.store = store
        cache = SourceCache(capacity: cacheCapacity)
    }

    // MARK: - Bitmaps

    /// Renders `page` with `pixelsPerPoint` resolution onto white.
    /// `includingInk: false` is for the ink editor, which draws the strokes
    /// it is editing over the page itself.
    public func renderImage(_ page: Page, pixelsPerPoint: CGFloat, includingInk: Bool = true) async throws -> CGImage {
        let size = page.geometry.pageSize
        let width = max(1, Int((size.width * pixelsPerPoint).rounded()))
        let height = max(1, Int((size.height * pixelsPerPoint).rounded()))
        guard width * height <= Self.maxPixelCount else { throw RenderError.outputTooLarge }
        let source = try await prepareSource(for: page, pixelsPerPoint: pixelsPerPoint)
        let ink = includingInk ? try await inkStrokes(for: page) : []
        return try Self.bitmap(width: width, height: height) { ctx in
            let pageToContext = CGAffineTransform(a: CGFloat(width) / size.width, b: 0, c: 0, d: -CGFloat(height) / size.height,
                                                  tx: 0, ty: CGFloat(height))
            Self.draw(page, source: source, ink: ink, in: ctx, pageToContext: pageToContext)
        }
    }

    /// Renders with the longer page edge at `maxPixelSize` pixels.
    public func renderThumbnail(_ page: Page, maxPixelSize: CGFloat, includingInk: Bool = true) async throws -> CGImage {
        let size = page.geometry.pageSize
        return try await renderImage(page, pixelsPerPoint: maxPixelSize / max(size.width, size.height), includingInk: includingInk)
    }

    /// The page's ink, in paint order.
    public func inkStrokes(for page: Page) async throws -> [InkStroke] {
        try await store.objects(on: page.id).compactMap { object in
            if case .ink(let stroke) = object.payload { stroke } else { nil }
        }
    }

    static func bitmap(width: Int, height: Int, draw: (CGContext) -> Void) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw RenderError.contextCreationFailed }
        ctx.interpolationQuality = .high
        draw(ctx)
        guard let image = ctx.makeImage() else { throw RenderError.contextCreationFailed }
        return image
    }

    // MARK: - Sources

    /// Original content prepared for drawing at a given resolution.
    public enum PreparedSource: @unchecked Sendable {
        /// Upright raster, filters already applied, covering `covering` (a
        /// rectangle of the source in points): the whole source for images,
        /// just the crop for rasterized PDF pages.
        case image(CGImage, covering: CGRect)
        /// Vector PDF page. `CGPDFDocument` is created per preparation, so it
        /// is never shared across concurrent draws.
        case pdf(CGPDFDocument, pageNumber: Int)
        case template(PageTemplate)
    }

    /// Loads and prepares a page's original. Raster sources are decoded at
    /// no more than the resolution needed. PDF pages stay vector unless they
    /// need pixel filters; then only the cropped region is rasterized, so a
    /// tight crop shown large never needs a huge whole-page bitmap.
    public func prepareSource(for page: Page, pixelsPerPoint: CGFloat) async throws -> PreparedSource {
        switch page.content {
        case .template(let template):
            return .template(template)
        case .image(let assetID):
            let needed = Int((max(page.sourceSize.width, page.sourceSize.height) * pixelsPerPoint).rounded(.up))
            let image = try await cache.uprightImage(assetID, maxPixelSize: needed, store: store)
            return .image(ImageAdjustments.apply(page.transform, to: image), covering: CGRect(origin: .zero, size: page.sourceSize))
        case .pdfPage(let assetID, let index):
            let data = try await cache.pdfData(assetID, store: store)
            guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider),
                  index + 1 <= document.numberOfPages else { throw RenderError.sourceDamaged }
            guard page.transform.needsPixelProcessing else { return .pdf(document, pageNumber: index + 1) }
            let region = page.geometry.cropRect
            let raster = try Self.rasterizePDFPage(document, pageNumber: index + 1, sourceSize: page.sourceSize,
                                                   region: region, pixelsPerPoint: pixelsPerPoint)
            return .image(ImageAdjustments.apply(page.transform, to: raster), covering: region)
        }
    }

    /// Rasterizes `region` (source points) of a PDF page onto white.
    static func rasterizePDFPage(_ document: CGPDFDocument, pageNumber: Int, sourceSize: CGSize,
                                 region: CGRect, pixelsPerPoint: CGFloat) throws -> CGImage {
        let width = max(1, Int((region.width * pixelsPerPoint).rounded()))
        let height = max(1, Int((region.height * pixelsPerPoint).rounded()))
        guard width * height <= maxPixelCount else { throw RenderError.outputTooLarge }
        return try bitmap(width: width, height: height) { ctx in
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let sx = CGFloat(width) / region.width
            let sy = CGFloat(height) / region.height
            // Source space (y-down) → bitmap (y-up), with `region` filling it.
            ctx.concatenate(CGAffineTransform(a: sx, b: 0, c: 0, d: -sy, tx: -region.minX * sx, ty: CGFloat(height) + region.minY * sy))
            drawPDFContent(document, pageNumber: pageNumber, sourceSize: sourceSize, in: ctx)
        }
    }

    // MARK: - Drawing

    /// Draws a page and its ink. `pageToContext` maps page space (points,
    /// y-down) into the context's user space; the page is clipped to its
    /// bounds and painted on white so transparent originals never lose dark
    /// content. Ink is in source space, so it follows crop and rotation.
    /// `ink` has no default: every caller decides, so none drops it silently.
    public static func draw(_ page: Page, source: PreparedSource, ink: [InkStroke], in ctx: CGContext, pageToContext: CGAffineTransform) {
        let geometry = page.geometry
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.concatenate(pageToContext)
        let pageRect = CGRect(origin: .zero, size: geometry.pageSize)
        ctx.clip(to: pageRect)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(pageRect)
        ctx.concatenate(geometry.sourceToPage)

        switch source {
        case .image(let image, let covering):
            ctx.saveGState()
            ctx.concatenate(PageGeometry.yUpToYDown(in: covering))
            ctx.interpolationQuality = .high
            ctx.draw(image, in: covering)
            ctx.restoreGState()
        case .pdf(let document, let pageNumber):
            drawPDFContent(document, pageNumber: pageNumber, sourceSize: page.sourceSize, in: ctx)
        case .template(let template):
            drawTemplate(template, size: page.sourceSize, in: ctx)
        }
        for stroke in ink { drawInk(stroke, in: ctx) }
    }

    /// Draws one stroke in source space. Pen ink is opaque, its width
    /// following each point (consecutive segments of the same width share
    /// one path, keeping PDFs small). Highlighter ink is one translucent
    /// path, multiplied so the page shows through.
    static func drawInk(_ stroke: InkStroke, in ctx: CGContext) {
        guard let first = stroke.points.first else { return }
        let c = stroke.color
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let point = { (p: InkPoint) in CGPoint(x: p.x, y: p.y) }

        if stroke.tool == .highlighter || c.alpha < 0.999 {
            let opacity = stroke.tool == .highlighter ? InkStroke.highlighterOpacity : 1
            if stroke.tool == .highlighter { ctx.setBlendMode(.multiply) }
            ctx.setStrokeColor(CGColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha * opacity))
            ctx.setLineWidth(stroke.width)
            ctx.move(to: point(first))
            // A tap leaves a dot: a zero-length segment with round caps.
            for p in stroke.points.dropFirst() { ctx.addLine(to: point(p)) }
            if stroke.points.count == 1 { ctx.addLine(to: point(first)) }
            ctx.strokePath()
            return
        }

        ctx.setStrokeColor(CGColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha))
        guard stroke.points.count > 1 else {
            ctx.setLineWidth(stroke.width(at: first))
            ctx.move(to: point(first))
            ctx.addLine(to: point(first))
            ctx.strokePath()
            return
        }
        func rounded(_ w: Double) -> Double { (w * 4).rounded() / 4 }
        var runWidth = rounded((stroke.width(at: stroke.points[0]) + stroke.width(at: stroke.points[1])) / 2)
        ctx.move(to: point(first))
        for i in 1..<stroke.points.count {
            let a = stroke.points[i - 1], b = stroke.points[i]
            let w = rounded((stroke.width(at: a) + stroke.width(at: b)) / 2)
            if w != runWidth {
                ctx.setLineWidth(runWidth)
                ctx.strokePath()
                ctx.move(to: point(a))
                runWidth = w
            }
            ctx.addLine(to: point(b))
        }
        ctx.setLineWidth(runWidth)
        ctx.strokePath()
    }

    /// Draws a PDF page as vectors into a context currently in source space.
    static func drawPDFContent(_ document: CGPDFDocument, pageNumber: Int, sourceSize: CGSize, in ctx: CGContext) {
        guard let pdfPage = document.page(at: pageNumber) else { return }
        let box = pdfPage.getBoxRect(.cropBox)
        let rotation = Int(pdfPage.rotationAngle)
        let upright = PageGeometry.uprightPDFSize(box: box, rotationDegrees: rotation)
        ctx.saveGState()
        // Stored source sizes come from the same boxes, so this scale is 1
        // unless a page's metadata was rounded; it keeps content inside.
        ctx.concatenate(CGAffineTransform(scaleX: sourceSize.width / upright.width, y: sourceSize.height / upright.height))
        ctx.concatenate(PageGeometry.pdfToSource(box: box, rotationDegrees: rotation))
        ctx.clip(to: box)
        ctx.drawPDFPage(pdfPage)
        ctx.restoreGState()
    }

    static func drawTemplate(_ template: PageTemplate, size: CGSize, in ctx: CGContext) {
        let spacing: CGFloat
        switch template {
        case .blank: return
        case .lined: spacing = 24
        case .grid: spacing = 18
        }
        ctx.saveGState()
        ctx.setStrokeColor(CGColor(red: 0.62, green: 0.72, blue: 0.85, alpha: 1))
        ctx.setLineWidth(0.5)
        var y = template == .lined ? spacing * 3 : spacing
        while y < size.height {
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }
        if template == .grid {
            var x = spacing
            while x < size.width {
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
        }
        ctx.strokePath()
        ctx.restoreGState()
    }
}

/// Small LRU cache of decoded originals; bounded so large libraries never
/// accumulate decoded images in memory.
actor SourceCache {
    private struct ImageKey: Hashable {
        let asset: AssetID
        let maxPixelSize: Int
    }

    private let capacity: Int
    private var images: [ImageKey: CGImage] = [:]
    private var pdfs: [AssetID: Data] = [:]
    private var order: [AnyHashable] = []

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func uprightImage(_ asset: AssetID, maxPixelSize: Int, store: LibraryStore) async throws -> CGImage {
        // Bucket requested sizes so nearby zoom levels share a decode.
        let bucket = Self.bucket(maxPixelSize)
        let key = ImageKey(asset: asset, maxPixelSize: bucket)
        if let hit = images[key] {
            touch(key)
            return hit
        }
        let data = try await load(asset, store: store)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw RenderError.sourceDamaged }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // applies EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: bucket,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw RenderError.sourceDamaged }
        images[key] = image
        touch(key)
        return image
    }

    func pdfData(_ asset: AssetID, store: LibraryStore) async throws -> Data {
        if let hit = pdfs[asset] {
            touch(asset)
            return hit
        }
        let data = try await load(asset, store: store)
        pdfs[asset] = data
        touch(asset)
        return data
    }

    private func load(_ asset: AssetID, store: LibraryStore) async throws -> Data {
        do {
            return try await store.assetData(asset).0
        } catch {
            throw RenderError.sourceUnavailable
        }
    }

    static func bucket(_ size: Int) -> Int {
        var b = 256
        while b < size { b *= 2 }
        return min(b, 16_384)
    }

    private func touch(_ key: AnyHashable) {
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > capacity {
            let evicted = order.removeFirst()
            if let k = evicted.base as? ImageKey { images[k] = nil }
            if let k = evicted.base as? AssetID { pdfs[k] = nil }
        }
    }
}

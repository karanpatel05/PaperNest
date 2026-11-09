import CoreGraphics
import CoreText
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

/// One thing painted over a page's own content.
///
/// A page's objects come back from `LibraryStore.objects(on:)` in `zKey`
/// order and this list keeps that order, so an image placed over a stroke
/// covers it and a stroke drawn over an image covers that — whichever the
/// page says came last. There is no rule that images sit beneath ink.
///
/// `@unchecked Sendable` for the same reason as `PreparedSource`: the image
/// is decoded once and only read afterwards.
public enum PageLayer: @unchecked Sendable {
    case ink(InkStroke)
    /// A decoded image and the frame it fills, in upright source points.
    case image(CGImage, CGRect)
    case text(TextBox)
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
    public func renderImage(_ page: Page, pixelsPerPoint: CGFloat, includingInk: Bool = true,
                            excludingObjectIDs: Set<PageObjectID> = []) async throws -> CGImage {
        let size = page.geometry.pageSize
        let width = max(1, Int((size.width * pixelsPerPoint).rounded()))
        let height = max(1, Int((size.height * pixelsPerPoint).rounded()))
        guard width * height <= Self.maxPixelCount else { throw RenderError.outputTooLarge }
        let source = try await prepareSource(for: page, pixelsPerPoint: pixelsPerPoint)
        let layers = try await layers(for: page, pixelsPerPoint: pixelsPerPoint, includingInk: includingInk,
                                      excludingObjectIDs: excludingObjectIDs)
        return try Self.bitmap(width: width, height: height) { ctx in
            let pageToContext = CGAffineTransform(a: CGFloat(width) / size.width, b: 0, c: 0, d: -CGFloat(height) / size.height,
                                                  tx: 0, ty: CGFloat(height))
            Self.draw(page, source: source, layers: layers, in: ctx, pageToContext: pageToContext)
        }
    }

    /// A transparent, page-sized preview of the selected editable objects.
    /// Used only while moving a selection: no original page content is loaded
    /// or painted, and no metadata or assets are changed.
    public func renderSelection(_ page: Page, objectIDs: Set<PageObjectID>,
                                pixelsPerPoint: CGFloat) async throws -> CGImage {
        let size = page.geometry.pageSize
        guard pixelsPerPoint.isFinite, pixelsPerPoint > 0,
              size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            throw RenderError.outputTooLarge
        }
        let pixelWidth = max(1, (size.width * pixelsPerPoint).rounded())
        let pixelHeight = max(1, (size.height * pixelsPerPoint).rounded())
        // Check before conversion or integer multiplication, including values
        // too large to represent as Int, so a bad scale cannot trap or allocate.
        guard pixelWidth.isFinite, pixelHeight.isFinite,
              pixelWidth <= CGFloat(Self.maxPixelCount), pixelHeight <= CGFloat(Self.maxPixelCount),
              pixelWidth * pixelHeight <= CGFloat(Self.maxPixelCount) else { throw RenderError.outputTooLarge }
        let width = Int(pixelWidth), height = Int(pixelHeight)
        let selected = try await store.objects(on: page.id).filter { objectIDs.contains($0.id) }
        let layers = try await preparedLayers(selected, pixelsPerPoint: pixelsPerPoint, includingInk: true)
        return try Self.bitmap(width: width, height: height, transparent: true) { ctx in
            let pageToContext = CGAffineTransform(a: CGFloat(width) / size.width, b: 0,
                c: 0, d: -CGFloat(height) / size.height, tx: 0, ty: CGFloat(height))
            ctx.concatenate(pageToContext)
            ctx.clip(to: CGRect(origin: .zero, size: size))
            ctx.concatenate(page.geometry.sourceToPage)
            Self.drawLayers(layers, in: ctx)
        }
    }

    /// Renders with the longer page edge at `maxPixelSize` pixels.
    public func renderThumbnail(_ page: Page, maxPixelSize: CGFloat, includingInk: Bool = true,
                            excludingObjectIDs: Set<PageObjectID> = []) async throws -> CGImage {
        let size = page.geometry.pageSize
        return try await renderImage(page, pixelsPerPoint: maxPixelSize / max(size.width, size.height), includingInk: includingInk,
                                     excludingObjectIDs: excludingObjectIDs)
    }

    /// The page's recognized text, but only when it still describes the page:
    /// a result from an older revision is stale and must not be exported or
    /// searched. Mirrors the rule `LibraryStore.saveRecognition` indexes by.
    public func recognizedLines(for page: Page) async throws -> [RecognizedLine] {
        guard let recognition = try await store.recognition(for: page.id),
              recognition.status == .completed, recognition.sourceRevision == page.revision else { return [] }
        return recognition.lines
    }

    /// The text the page's own PDF carries, for callers exporting text. Nil
    /// when the page carries none. Beside `recognizedLines(for:)` so the
    /// exporter reaches stored text through the renderer rather than holding a
    /// store reference of its own.
    public func embeddedText(for page: Page) async throws -> String? {
        try await store.embeddedText(for: page.id)
    }

    /// The bytes of the PDF this page came from, or nil when it did not come
    /// from one. For a caller that needs the original file rather than a
    /// drawing of it: exporting a page nobody has edited copies it instead of
    /// reproducing its marks, which is what keeps links and form fields.
    public func sourcePDFData(for page: Page) async throws -> Data? {
        guard case .pdfPage(let assetID, _) = page.content else { return nil }
        return try await cache.pdfData(assetID, store: store)
    }

    /// The page's ink, in paint order.
    /// A page's ink alone.
    ///
    /// **Not what to draw with.** `draw` takes `layers(for:pixelsPerPoint:)`,
    /// which carries placed images as well and keeps the page's own order;
    /// painting from this would silently leave a placed image out, which is
    /// the fault that `isUntouched` used to have.
    public func inkStrokes(for page: Page) async throws -> [InkStroke] {
        try await store.objects(on: page.id).compactMap { object in
            if case .ink(let stroke) = object.payload { stroke } else { nil }
        }
    }

    /// Everything painted over the page, in the page's own order, with any
    /// placed image already decoded at a size that suits `pixelsPerPoint`.
    ///
    /// `includingInk: false` is for the ink editor, which paints the strokes it
    /// is editing itself. A placed image is not ink and stays either way, or
    /// the page would appear to lose it the moment someone started drawing.
    ///
    /// A placed image whose asset is not on this device throws rather than
    /// being skipped: a page quietly missing part of itself is worse than one
    /// that says it cannot be drawn.
    public func layers(for page: Page, pixelsPerPoint: CGFloat,
                       includingInk: Bool = true, excludingObjectIDs: Set<PageObjectID> = []) async throws -> [PageLayer] {
        let objects = try await store.objects(on: page.id).filter { !excludingObjectIDs.contains($0.id) }
        return try await preparedLayers(objects, pixelsPerPoint: pixelsPerPoint, includingInk: includingInk)
    }

    /// Prepare just the requested objects, preserving their store paint order.
    /// Filtering happens before asset decoding so unrelated unavailable images
    /// cannot prevent a selection preview from rendering.
    private func preparedLayers(_ objects: [PageObject], pixelsPerPoint: CGFloat,
                                includingInk: Bool) async throws -> [PageLayer] {
        var layers: [PageLayer] = []
        for object in objects {
            switch object.payload {
            case .ink(let stroke):
                if includingInk { layers.append(.ink(stroke)) }
            case .image(let placed):
                let longestEdge = max(placed.frame.width, placed.frame.height) * pixelsPerPoint
                let image = try await cache.uprightImage(
                    placed.assetID, maxPixelSize: max(1, Int(longestEdge.rounded(.up))), store: store)
                layers.append(.image(image, placed.frame))
            case .text(let textBox):
                layers.append(.text(textBox))
            case .comment:
                // A page comment is private: it belongs in neither a rendering
                // nor an export, which `PageCommentWorkflowTests` pins.
                break
            }
        }
        return layers
    }

    static func bitmap(width: Int, height: Int, transparent: Bool = false,
                       draw: (CGContext) -> Void) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: (transparent ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)
        else { throw RenderError.contextCreationFailed }
        if transparent { ctx.clear(CGRect(x: 0, y: 0, width: width, height: height)) }
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

    /// The page's original, upright and uncropped, with no adjustments or
    /// ink: the space text recognition stores its boxes in. Deliberately not
    /// `prepareSource`, which applies the user's crop and filters — text must
    /// be read from the paper, not from the current view of it.
    public func renderSourceForRecognition(_ page: Page, pixelsPerPoint: CGFloat) async throws -> CGImage? {
        switch page.content {
        case .template:
            return nil
        case .image(let assetID):
            let needed = Int((max(page.sourceSize.width, page.sourceSize.height) * pixelsPerPoint).rounded(.up))
            return try await cache.uprightImage(assetID, maxPixelSize: needed, store: store)
        case .pdfPage(let assetID, let index):
            let data = try await cache.pdfData(assetID, store: store)
            guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider),
                  index + 1 <= document.numberOfPages else { throw RenderError.sourceDamaged }
            return try Self.rasterizePDFPage(document, pageNumber: index + 1, sourceSize: page.sourceSize,
                                             region: CGRect(origin: .zero, size: page.sourceSize),
                                             pixelsPerPoint: pixelsPerPoint)
        }
    }

    /// Loads and prepares a page's original. Raster sources are decoded at
    /// no more than the resolution needed. PDF pages stay vector unless they
    /// need pixel filters; then only the cropped region is rasterized, so a
    /// tight crop shown large never needs a huge whole-page bitmap.
    /// `rasterizingPDFPages` turns a PDF page into pixels even when nothing
    /// about it needs pixel processing. Only compression asks for this, and
    /// only for a page with no text to lose: rasterizing is how a scanned PDF's
    /// size can change at all, since vector content is copied as it stands.
    public func prepareSource(for page: Page, pixelsPerPoint: CGFloat,
                              rasterizingPDFPages: Bool = false) async throws -> PreparedSource {
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
            guard page.transform.needsPixelProcessing || rasterizingPDFPages else {
                return .pdf(document, pageNumber: index + 1)
            }
            let region = page.geometry.cropRect
            let raster = try Self.rasterizePDFPage(document, pageNumber: index + 1, sourceSize: page.sourceSize,
                                                   region: region, pixelsPerPoint: pixelsPerPoint)
            return .image(ImageAdjustments.apply(page.transform, to: raster), covering: region)
        }
    }

    /// The page's content as an upright raster, with **no transform applied**:
    /// no crop, no rotation, no filter, and the whole sheet rather than the
    /// visible part of it.
    ///
    /// Redaction needs the paper exactly as it is. Its rectangles are given in
    /// uncropped source space, and the page keeps its transform afterwards, so
    /// a raster that had already been cropped or filtered would apply those
    /// edits a second time and move the rectangles off their words.
    public func uprightSourceRaster(for page: Page, pixelsPerPoint: CGFloat) async throws -> CGImage {
        let whole = CGRect(origin: .zero, size: page.sourceSize)
        switch page.content {
        case .image(let assetID):
            let needed = Int((max(page.sourceSize.width, page.sourceSize.height) * pixelsPerPoint).rounded(.up))
            return try await cache.uprightImage(assetID, maxPixelSize: needed, store: store)
        case .pdfPage(let assetID, let index):
            let data = try await cache.pdfData(assetID, store: store)
            guard let provider = CGDataProvider(data: data as CFData),
                  let document = CGPDFDocument(provider),
                  index + 1 <= document.numberOfPages else { throw RenderError.sourceDamaged }
            return try Self.rasterizePDFPage(document, pageNumber: index + 1, sourceSize: page.sourceSize,
                                             region: whole, pixelsPerPoint: pixelsPerPoint)
        case .template(let template):
            let width = max(1, Int((whole.width * pixelsPerPoint).rounded()))
            let height = max(1, Int((whole.height * pixelsPerPoint).rounded()))
            guard width * height <= Self.maxPixelCount else { throw RenderError.outputTooLarge }
            return try Self.bitmap(width: width, height: height) { ctx in
                ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
                ctx.scaleBy(x: CGFloat(width) / whole.width, y: CGFloat(height) / whole.height)
                Self.drawTemplate(template, size: whole.size, in: ctx)
            }
        }
    }

    /// Rasterizes `region` (source points) of a PDF page onto white.
    ///
    /// Public so compression can reduce a PDF kept as a loose file, which has
    /// no `Page` and no store to go through, without a second rasterizer.
    public static func rasterizePDFPage(_ document: CGPDFDocument, pageNumber: Int, sourceSize: CGSize,
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
    public static func draw(_ page: Page, source: PreparedSource, layers: [PageLayer], in ctx: CGContext, pageToContext: CGAffineTransform) {
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
        drawLayers(layers, in: ctx)
    }

    /// Both page export and transient previews paint the same source-space layers.
    private static func drawLayers(_ layers: [PageLayer], in ctx: CGContext) {
        for layer in layers {
            switch layer {
            case .ink(let stroke): drawInk(stroke, in: ctx)
            case .image(let image, let frame): drawPlacedImage(image, in: frame, in: ctx)
            case .text(let textBox): drawTextBox(textBox, in: ctx)
            }
        }
    }

    /// Draws a text box in source space, as **real text**.
    ///
    /// Not glyph outlines. Into a PDF context this emits text operators, so
    /// the words someone typed can be selected, copied and searched in the
    /// exported file — a picture of text would look identical and be useless,
    /// and `textInABoxIsRealTextInTheExportedPDF` reads them back out to say
    /// which one this is.
    ///
    /// The flip is the one `drawSearchableText` uses rather than a second idea
    /// of which way is up: translate to the box's bottom edge in y-down source
    /// space and scale y by −1, which leaves `CTFrameDraw` laying the first
    /// line against the box's top and running down the page.
    ///
    /// Text longer than its box is **clipped** by the frame path, with nothing
    /// to say so.
    static func drawTextBox(_ textBox: TextBox, in ctx: CGContext) {
        guard let frame = textFrame(textBox) else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.translateBy(x: textBox.frame.minX, y: textBox.frame.maxY)
        ctx.scaleBy(x: 1, y: -1)
        CTFrameDraw(frame, ctx)
    }

    /// Visible glyph bounds in the same upright source space as the text box.
    /// Selection must not require enclosing its unused width/height. Shared
    /// CoreText layout preserves wrapping, alignment, styles and font fallback.
    public static func textSelectionRects(_ textBox: TextBox) -> [CGRect] {
        guard textBox.color.alpha > 0, let frame = textFrame(textBox),
              let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                      bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let mapping = PageGeometry.yUpToYDown(in: CGRect(origin: .zero, size: textBox.frame.size))
            .concatenating(CGAffineTransform(translationX: textBox.frame.minX, y: textBox.frame.minY))
        var result: [CGRect] = []
        for (line, origin) in zip(lines, origins) {
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                for index in 0..<CTRunGetGlyphCount(run) {
                    let bounds = CTRunGetImageBounds(run, context, CFRange(location: index, length: 1))
                    guard !bounds.isNull, !bounds.isEmpty else { continue }
                    let rect = bounds.offsetBy(dx: origin.x, dy: origin.y).applying(mapping).intersection(textBox.frame)
                    if !rect.isNull, !rect.isEmpty { result.append(rect) }
                }
            }
        }
        return result
    }

    private static func textFrame(_ textBox: TextBox) -> CTFrame? {
        guard !textBox.text.isEmpty, textBox.fontSize > 0,
              textBox.frame.width > 0, textBox.frame.height > 0 else { return nil }
        let font = CTFontCreateWithName(textBox.postScriptFontName as CFString, CGFloat(textBox.fontSize), nil)
        var alignment: CTTextAlignment = switch textBox.alignment {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
        let style = withUnsafeMutablePointer(to: &alignment) { pointer -> CTParagraphStyle in
            var setting = CTParagraphStyleSetting(spec: .alignment,
                                                  valueSize: MemoryLayout<CTTextAlignment>.size,
                                                  value: pointer)
            return CTParagraphStyleCreate(&setting, 1)
        }
        let color = textBox.color
        let attributed = NSAttributedString(string: textBox.text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha),
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): style,
        ])
        let path = CGPath(rect: CGRect(origin: .zero, size: textBox.frame.size), transform: nil)
        return CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(attributed),
                                        CFRange(location: 0, length: 0), path, nil)
    }

    /// Draws a placed image into its frame in source space.
    ///
    /// The flip is the same one the page's own raster content uses, so there
    /// is one mapping from source space to the context and no second idea of
    /// which way is up in here.
    static func drawPlacedImage(_ image: CGImage, in frame: CGRect, in ctx: CGContext) {
        guard frame.width > 0, frame.height > 0 else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.concatenate(PageGeometry.yUpToYDown(in: frame))
        ctx.interpolationQuality = .high
        ctx.draw(image, in: frame)
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
        // Generated text marks (and other constant-width pens) must retain
        // their exact width. Freehand run quantization below can otherwise
        // erase a thin line or expand its caps beyond the source bounds.
        if stroke.points.allSatisfy({ stroke.width(at: $0) == stroke.width(at: first) }) {
            ctx.setLineWidth(stroke.width(at: first))
            ctx.move(to: point(first))
            for p in stroke.points.dropFirst() { ctx.addLine(to: point(p)) }
            if stroke.points.count == 1 { ctx.addLine(to: point(first)) }
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

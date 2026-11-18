import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import PaperNestCore
import PaperNestRender
import UniformTypeIdentifiers

/// Writes PDF, JPEG and PNG representations of pages. Export never changes
/// the library: it renders from the stored originals and transforms into a
/// private temporary directory.
public struct Exporter: Sendable {
    public let renderer: PageRenderer
    /// Parent of each export's private working directory.
    public let temporaryRoot: URL

    public init(renderer: PageRenderer, temporaryRoot: URL = FileManager.default.temporaryDirectory) {
        self.renderer = renderer
        self.temporaryRoot = temporaryRoot
    }

    /// Exports `pages` in the given order. Cancelling the calling task stops
    /// at the next page and removes everything written so far.
    ///
    /// **An author's limits are kept here, for every caller.** Pages from a
    /// PDF whose author switched copying off can leave only as a PDF that is
    /// just as closed, and pages whose author switched printing off are not
    /// made ready for a printer. Everything that lets content out of the app
    /// — the export sheet, printing, bulk export, the library backup, the
    /// form workspace — comes through this function, which is why the rule
    /// lives here and nowhere else.
    public func export(
        itemName: String,
        pages: [Page],
        options: ExportOptions,
        password: String? = nil,
        purpose: ExportPurpose = .file,
        progress: @Sendable (ExportProgress) -> Void = { _ in }
    ) async throws -> ExportOutput {
        try await export(itemName: itemName, pages: pages, options: options,
                         rasterQuality: nil, password: password, purpose: purpose, progress: progress)
    }

    /// The same export, with the raster resolution and quality chosen
    /// explicitly rather than taken from `options.pdfImageQuality`. Internal,
    /// because `RasterQuality` exists so compression presets need not appear
    /// as cases in the enum the export sheet's picker iterates.
    func export(
        itemName: String,
        pages: [Page],
        options: ExportOptions,
        rasterQuality: RasterQuality?,
        password: String? = nil,
        purpose: ExportPurpose = .file,
        progress: @Sendable (ExportProgress) -> Void = { _ in }
    ) async throws -> ExportOutput {
        guard !pages.isEmpty else { throw ExportError.noPages }
        // What the authors of these pages allow. Read from the originals, and
        // an original that cannot be read fails the export: not knowing is
        // not permission.
        let permissions = try await renderer.permissions(for: pages)
        if purpose == .printing, !permissions.allowsPrinting { throw ExportError.printingNotAllowed }
        if !permissions.allowsCopying, options.format != .pdf { throw ExportError.copyingNotAllowed }
        let protection = AuthorProtection(permissions)
        // All refused before a directory exists, so a refusal writes nothing.
        if let password {
            guard options.format == .pdf else { throw ExportError.passwordNotSupported }
            guard !password.isEmpty else { throw ExportError.emptyPassword }
            // ASCII only, measured rather than inferred from the spec: the
            // writer refused `"été-Ñandú-2026"` as well as `"contraseña-密码-1"`,
            // so Latin-1 is not the boundary in practice.
            //
            // Separately, only the first 32 bytes are honoured by revision 4.
            // That is a documentation point rather than a failure, since the
            // whole password still opens the file.
            guard password.allSatisfy(\.isASCII) else {
                throw ExportError.passwordNotRepresentable
            }
        }
        if !options.drawnMarks.isEmpty, !options.canCarryWatermark {
            throw ExportError.watermarkNotSupported
        }
        let directory = temporaryRoot.appendingPathComponent("PaperNestExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let base = ExportNaming.baseName(itemName)
            let files: [URL] = switch options.format {
            case .pdf: [try await writePDF(pages, title: itemName, to: directory.appendingPathComponent("\(base).pdf"),
                                           options: options, rasterQuality: rasterQuality,
                                           password: password, protection: protection, progress: progress)]
            case .jpeg, .png, .heic: try await writeImages(pages, base: base, in: directory, options: options, progress: progress)
            case .txt: [try await writeText(pages, to: directory.appendingPathComponent("\(base).txt"), progress: progress)]
            case .docx:
                switch options.docxLayout {
                case .editableText:
                    [try await writeDocx(pages, to: directory.appendingPathComponent("\(base).docx"), progress: progress)]
                case .pageImages:
                    [try await writeDocxPageImages(pages, to: directory.appendingPathComponent("\(base).docx"),
                                                   options: options, progress: progress)]
                }
            }
            // Checked, not trusted: three different writers can produce this
            // file, and one that dropped the author's limits must fail the
            // export rather than hand the file over.
            if let protection, options.format == .pdf {
                guard let written = files.first, protection.holds(in: written, userPassword: password) else {
                    throw ExportError.writeFailed
                }
            }
            return ExportOutput(directory: directory, files: files)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    // MARK: - PDF

    /// Writes recognized text invisibly over the page, so the exported PDF can
    /// be searched and its words selected in any reader. The glyphs are never
    /// painted: only their positions matter, and they come from the same
    /// source-space boxes recognition stored.
    private static func drawSearchableText(_ lines: [RecognizedLine], geometry: PageGeometry,
                                           pageToContext: CGAffineTransform, in ctx: CGContext) {
        guard !lines.isEmpty else { return }
        let size = geometry.sourceSize
        // Draw in source space and let the page's own transform carry the
        // crop and rotation. Placing a rotated line by its bounding box
        // instead would squeeze it into a sliver.
        ctx.saveGState()
        ctx.concatenate(geometry.sourceToPage.concatenating(pageToContext))
        ctx.setTextDrawingMode(.invisible)
        for line in lines where !line.text.isEmpty {
            let box = CGRect(x: line.box.x * size.width, y: line.box.y * size.height,
                             width: line.box.width * size.width, height: line.box.height * size.height)
            guard box.width > 0.5, box.height > 0.5 else { continue }
            let font = CTFontCreateWithName("Helvetica" as CFString, box.height * 0.8, nil)
            let attributed = NSAttributedString(string: line.text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
            ])
            let ctLine = CTLineCreateWithAttributedString(attributed)
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading))
            guard width > 0 else { continue }
            ctx.saveGState()
            // Source space is y-down; text is drawn y-up from its baseline.
            // The horizontal stretch goes on the CTM, not the text matrix,
            // which `CTLineDraw` overrides from the line's own runs: it makes
            // a word's position in the PDF match where it sits on the page.
            ctx.translateBy(x: box.minX, y: box.maxY)
            ctx.scaleBy(x: box.width / width, y: -1)
            ctx.textPosition = CGPoint(x: 0, y: descent)
            CTLineDraw(ctLine, ctx)
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    /// `rasterQuality` overrides what `options.pdfImageQuality` would ask for,
    /// so a compression preset can pick its own resolution and quality without
    /// a new case appearing in the export sheet's picker.
    private func writePDF(_ pages: [Page], title: String, to url: URL, options: ExportOptions,
                          rasterQuality: RasterQuality? = nil, password: String? = nil,
                          protection: AuthorProtection? = nil,
                          progress: @Sendable (ExportProgress) -> Void) async throws -> URL {
        var defaultBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        var info: [CFString: Any] = [kCGPDFContextCreator: Brand.pdfCreator, kCGPDFContextTitle: title]
        if let protection {
            // The author's limits, under an owner password nobody holds. A
            // password the exporter asked for only opens the file.
            protection.apply(to: &info, userPassword: password)
        } else if let password {
            // Both, deliberately. A document opens with *either* password, so
            // leaving the owner password empty would open it with an empty one
            // and the user password would protect nothing.
            info[kCGPDFContextUserPassword] = password
            info[kCGPDFContextOwnerPassword] = password
        }
        guard let ctx = CGContext(url as CFURL, mediaBox: &defaultBox, info as CFDictionary) else { throw ExportError.writeFailed }
        var closed = false
        defer { if !closed { ctx.closePDF() } }

        progress(ExportProgress(completedPages: 0, totalPages: pages.count))
        // Pages nobody has changed are copied from their source file after the
        // document is closed; a drawing of a page cannot carry its links, form
        // fields or annotations. Collected here, applied below.
        var untouched: [Int: PDFPage] = [:]
        // Each source file is opened once, and kept open until the copies have
        // been written: a copied page is read lazily from the document it came
        // from.
        var sourceDocuments: [AssetID: PDFDocument] = [:]
        // The same bytes, kept for the whole-file copy below so the source is
        // read once rather than again at the end.
        var sourceData: [AssetID: Data] = [:]
        for (index, page) in pages.enumerated() {
            try Task.checkCancellation()
            let pageSize = page.geometry.pageSize
            let layout = PaperLayout(pageSize: pageSize, paper: options.paperSize)
            // The resolution the page will be drawn at, which also decides
            // how large a placed image needs decoding. Same arithmetic as
            // `pdfSource`, which is where the page's own content gets it.
            let pageScale = layout.contentRect.width / pageSize.width
            let drawnQuality = rasterQuality ?? options.pdfImageQuality.rasterQuality
            let layers = try await renderer.layers(
                for: page, pixelsPerPoint: drawnQuality.maxDPI / 72 * pageScale)
            let textLayer = options.includesRecognizedText
                ? try await renderer.recognizedLines(for: page) : []

            let untouchedCandidate = Self.isUntouched(
                page, options: options, hasPaintedObjects: !layers.isEmpty,
                hasTextLayer: !textLayer.isEmpty)

            // The copy of the source page is two things at once: what
            // pass-through writes, and the yardstick for whether re-encoding
            // the page is worth doing at all. Read it only when one of those
            // is actually in play.
            var sourceCopy: PDFPage?
            var carriesText = true
            if case .pdfPage(let assetID, let sourceIndex) = page.content,
               untouchedCandidate || rasterQuality != nil {
                if sourceDocuments[assetID] == nil, let data = try await renderer.sourcePDFData(for: page) {
                    sourceDocuments[assetID] = PDFDocument(data: data)
                    sourceData[assetID] = data
                }
                if let document = sourceDocuments[assetID] {
                    sourceCopy = document.page(at: sourceIndex)?.copy() as? PDFPage
                    carriesText = Self.carriesText(document, at: sourceIndex)
                }
            }

            // Under a compression preset, a PDF page with no text of its own is
            // a scan, and re-encoding it is the only way its size can change:
            // vector content is copied as it stands, so every preset would
            // otherwise hand back the page exactly as it arrived. Two things
            // have to hold. The page must carry no text, because rasterizing
            // real text destroys every word for a reader, a search and an
            // export. And the re-encode must actually come out smaller than the
            // page already is — at 300 dpi a preset *upsamples* most scans, and
            // a "compression" that doubled the file would be worse than none.
            //
            // A page that already needs pixel processing (a filter, brightness
            // or contrast) is excluded: the ordinary path rasterizes it at the
            // same quality anyway, so measuring a candidate only to fall back
            // would rasterize it twice for identical bytes.
            var reEncoded: PageRenderer.PreparedSource?
            if let quality = rasterQuality, let sourceCopy, !carriesText,
               !page.transform.needsPixelProcessing,
               let budget = Self.byteCount(of: sourceCopy) {
                reEncoded = try await reEncodedPDFPage(page, layout: layout, quality: quality, under: budget)
            }

            // Pass-through stands down for a page being re-encoded: a copied
            // page ignores the preset entirely, which is the whole bug. This
            // guard has to stay ahead of the pass-through branch.
            if reEncoded == nil, let copy = sourceCopy, untouchedCandidate {
                // The copy was taken before the placeholder is committed, so a
                // source that cannot be read back falls through and is drawn
                // exactly as it was before pass-through existed, rather than
                // leaving an empty page where the content should be.
                var emptyBox = CGRect(origin: .zero, size: layout.paperSize)
                let emptyBoxData = Data(bytes: &emptyBox, count: MemoryLayout<CGRect>.size)
                ctx.beginPDFPage([kCGPDFContextMediaBox: emptyBoxData] as CFDictionary)
                ctx.endPDFPage()
                untouched[index] = copy
                progress(ExportProgress(completedPages: index + 1, totalPages: pages.count))
                continue
            }

            // Drawn from the candidate that was already measured, so a
            // compressed page is rasterized once rather than twice.
            let source: PageRenderer.PreparedSource
            if let reEncoded {
                source = reEncoded
            } else {
                source = try await pdfSource(
                    for: page, layout: layout,
                    quality: rasterQuality ?? options.pdfImageQuality.rasterQuality)
            }

            var box = CGRect(origin: .zero, size: layout.paperSize)
            let boxData = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
            ctx.beginPDFPage([kCGPDFContextMediaBox: boxData] as CFDictionary)
            // Paper space is y-down in our model; PDF user space is y-up.
            let pageToContext = layout.pageToPaper(pageSize: pageSize)
                .concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: layout.paperSize.height))
            PageRenderer.draw(page, source: source, layers: layers, in: ctx, pageToContext: pageToContext)
            if !textLayer.isEmpty {
                Self.drawSearchableText(textLayer, geometry: page.geometry, pageToContext: pageToContext, in: ctx)
            }
            if !options.drawnMarks.isEmpty {
                // Over the paper, not the page fitted onto it: a corner mark
                // belongs in the corner of what the reader holds. Drawn as
                // outlines, after the invisible text layer, so a search or a
                // copy finds the page's words and never the watermark's.
                ctx.saveGState()
                ctx.translateBy(x: 0, y: layout.paperSize.height)
                ctx.scaleBy(x: 1, y: -1)
                for mark in options.drawnMarks { WatermarkDrawing.draw(mark, pageSize: layout.paperSize, in: ctx) }
                ctx.restoreGState()
            }
            ctx.endPDFPage()
            progress(ExportProgress(completedPages: index + 1, totalPages: pages.count))
        }
        ctx.closePDF()
        closed = true
        // Every page copied untouched, in the source's own order, all of
        // them, and nothing else asked for: this export *is* the file that
        // was imported. Hand that back rather than the rebuild, which would
        // keep the widget boxes and lose the form they belong to.
        if untouched.count == pages.count,
           let asset = Self.wholeSourceAsset(of: pages, options: options, rasterQuality: rasterQuality),
           let document = sourceDocuments[asset], document.pageCount == pages.count,
           let data = sourceData[asset], password == nil {
            try data.write(to: url, options: .atomic)
        } else if untouched.count == pages.count, let password, protection == nil,
                  let asset = Self.wholeSourceAsset(of: pages, options: options, rasterQuality: rasterQuality),
                  let document = sourceDocuments[asset], document.pageCount == pages.count,
                  !document.isEncrypted, let data = sourceData[asset] {
            // The same file under the password: the original written again,
            // not rebuilt from its pages, so its form keeps its fields and its
            // links stay links. Only from a source that is not encrypted
            // already — what PDFKit writes from one is not relied on — and
            // only without an author's limits, which the rebuild keeps.
            try Self.writeProtectedCopy(of: data, to: url, password: password)
        } else if !untouched.isEmpty {
            try Self.replaceWithSourcePages(untouched, in: url, password: password, protection: protection)
        }
        // The copies are read lazily from the documents they came from, which
        // must therefore outlive the write. Scope alone is not a guarantee
        // once the optimizer is involved, and every run here is Debug.
        withExtendedLifetime(sourceDocuments) {}
        return url
    }

    /// The one source file an export is simply a copy of, or nil.
    ///
    /// Rebuilding a document is what loses a form. An `AcroForm` lives in the
    /// document **catalog**, not on a page, and PDFKit offers no way to carry
    /// one across when pages are copied into a new document — so an exported
    /// page keeps its widget boxes and none of them is a field any more.
    /// Links and bookmarks go the same way. The answer is not to rebuild the
    /// document when there is nothing to rebuild: hand back the file that was
    /// imported, byte for byte.
    ///
    /// Strict on purpose. Each of these is a way a copy would hand back
    /// something other than what was asked for:
    ///
    /// - **Another format**, or **different paper** — a copy is the original's
    ///   format and the original's paper.
    /// - **A password** is not checked here: the file on disk is unprotected,
    ///   so the caller never hands it back as it is. It writes the same file
    ///   again under the password instead (`writeProtectedCopy`).
    /// - **Pages from more than one file**, or **out of the source's order**,
    ///   or **a subset**: handing back the whole file would restore pages
    ///   somebody deleted, which is the worst thing this could do. The caller
    ///   checks the count against the source as well, because this cannot see
    ///   how many pages the file has.
    /// - **An edited page** — a crop, a rotation or a filter.
    ///
    /// Whether anything is *painted* on the pages is not checked here: the
    /// caller already knows, because it is exactly the pages it copied
    /// untouched.
    static func wholeSourceAsset(of pages: [Page], options: ExportOptions,
                                 rasterQuality: RasterQuality?) -> AssetID? {
        guard options.format == .pdf, options.paperSize == .original else { return nil }
        // A compression preset is **not** a reason to rebuild. The caller
        // only reaches here when no page was re-encoded, which under a preset
        // means nothing could be made smaller — and the rebuild was measured
        // coming out *larger* than the source it was built from, which broke
        // the invariant that compressing is never worse than not compressing.
        // Handing the source back is both smaller and honest: the compression
        // result reports no saving, which is what happened.
        _ = rasterQuality
        guard let first = pages.first else { return nil }
        guard case .pdfPage(let asset, index: 0) = first.content else { return nil }
        for (offset, page) in pages.enumerated() {
            guard page.transform == .identity,
                  case .pdfPage(asset, index: offset) = page.content else { return nil }
        }
        return asset
    }

    /// The source PDF written again under `password` — every page, its form
    /// and its links as they are, because the document itself is written
    /// rather than its pages copied into a new one (which keeps the widget
    /// boxes and loses the form). PDFKit encrypts it with AES, as it does the
    /// rebuild. Both passwords are the one asked for, as elsewhere here: a
    /// document opens with either, so an empty owner password would open it.
    static func writeProtectedCopy(of data: Data, to url: URL, password: String) throws {
        guard let document = PDFDocument(data: data), !document.isLocked, !document.isEncrypted else {
            throw ExportError.writeFailed
        }
        // Beside the file the context wrote, then over it, as the pass-through does.
        let staged = url.deletingLastPathComponent().appendingPathComponent("protected-\(UUID().uuidString).pdf")
        guard document.write(to: staged, withOptions: [.userPasswordOption: password, .ownerPasswordOption: password]) else {
            try? FileManager.default.removeItem(at: staged)
            throw ExportError.writeFailed
        }
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: staged)
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw ExportError.writeFailed
        }
    }

    /// Vector PDF pages pass through untouched; raster content is limited to
    /// the quality's resolution and, for lossy settings, JPEG-encoded so the
    /// PDF embeds it with DCT compression.
    private func pdfSource(for page: Page, layout: PaperLayout, quality: RasterQuality) async throws -> PageRenderer.PreparedSource {
        let pageScale = layout.contentRect.width / page.geometry.pageSize.width
        let pixelsPerPoint = quality.maxDPI / 72 * pageScale
        // A redrawn page is paper: its annotations follow the author's print flags.
        let source = try await renderer.prepareSource(for: page, pixelsPerPoint: pixelsPerPoint, annotations: .paper)
        guard case .image(let image, let covering) = source, let jpegQuality = quality.jpegQuality else { return source }
        let maxPixels = Int((max(covering.width, covering.height) * pixelsPerPoint).rounded(.up))
        let limited = try Self.downsample(image, maxPixelSize: maxPixels)
        guard let data = Self.encode(limited, type: .jpeg, quality: jpegQuality, dpi: nil),
              let provider = CGDataProvider(data: data as CFData),
              let jpeg = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return source }
        return .image(jpeg, covering: covering)
    }

    /// A PDF page re-encoded as a JPEG at `quality`, or nil to leave the page
    /// exactly as it is.
    ///
    /// Nil is a normal answer and often the right one:
    ///
    /// - The re-encode came out no smaller than `budget`, the bytes the page
    ///   already costs. At 300 dpi a preset upsamples most scans, so Light
    ///   usually lands here and the page is copied untouched instead.
    /// - The page is too large to rasterize at this resolution (`maxPixelCount`
    ///   is 100M; an A0 page at 300 dpi is about 139M). Such a page used to
    ///   compress by being copied, and that has to keep working rather than
    ///   failing the whole export.
    /// - JPEG encoding did not produce bytes, so there is nothing to compare.
    ///
    /// Cancellation is never swallowed: it is the one error that must travel.
    private func reEncodedPDFPage(_ page: Page, layout: PaperLayout, quality: RasterQuality,
                                  under budget: Int) async throws -> PageRenderer.PreparedSource? {
        guard let jpegQuality = quality.jpegQuality else { return nil }
        let pageScale = layout.contentRect.width / page.geometry.pageSize.width
        let pixelsPerPoint = quality.maxDPI / 72 * pageScale
        let rastered: PageRenderer.PreparedSource
        do {
            rastered = try await renderer.prepareSource(for: page, pixelsPerPoint: pixelsPerPoint,
                                                        rasterizingPDFPages: true, annotations: .paper)
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            return nil
        }
        guard case .image(let image, let covering) = rastered else { return nil }
        let maxPixels = Int((max(covering.width, covering.height) * pixelsPerPoint).rounded(.up))
        guard let limited = try? Self.downsample(image, maxPixelSize: maxPixels),
              let data = Self.encode(limited, type: .jpeg, quality: jpegQuality, dpi: nil),
              data.count < budget,
              let provider = CGDataProvider(data: data as CFData),
              let jpeg = CGImage(jpegDataProviderSource: provider, decode: nil,
                                 shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return .image(jpeg, covering: covering)
    }

    static func downsample(_ image: CGImage, maxPixelSize: Int) throws -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxPixelSize, maxPixelSize > 0 else { return image }
        let scale = CGFloat(maxPixelSize) / CGFloat(longest)
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw ExportError.writeFailed }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = ctx.makeImage() else { throw ExportError.writeFailed }
        return result
    }

    // MARK: - Images

    private func writeImages(_ pages: [Page], base: String, in directory: URL, options: ExportOptions,
                             progress: @Sendable (ExportProgress) -> Void) async throws -> [URL] {
        // Exhaustive on purpose. This was `format == .jpeg ? .jpeg : .png`,
        // where a new case fell silently into PNG and wrote PNG bytes into a
        // file named for something else.
        let type: UTType = switch options.format {
        case .jpeg: .jpeg
        case .heic: .heic
        case .png: .png
        case .pdf, .txt, .docx: .png
        }
        let ext = options.format.fileExtension
        let pixelsPerPoint = CGFloat(options.imageDPI) / 72
        let zip: (writer: ZipWriter, url: URL)? = if options.writesArchive(pageCount: pages.count) {
            (try ZipWriter(url: directory.appendingPathComponent("\(base).zip")), directory.appendingPathComponent("\(base).zip"))
        } else {
            nil
        }
        var files: [URL] = []
        progress(ExportProgress(completedPages: 0, totalPages: pages.count))
        for (index, page) in pages.enumerated() {
            try Task.checkCancellation()
            // Rendered onto opaque white, so JPEG never turns dark ink on a
            // transparent page into black-on-black. A picture that leaves the
            // app is paper: the page's annotations follow the author's print
            // flags, as they do in a PDF export of the same page.
            var image = try await renderer.renderImage(page, pixelsPerPoint: pixelsPerPoint, annotations: .paper)
            if !options.drawnMarks.isEmpty {
                image = try WatermarkDrawing.applying(options.drawnMarks, to: image, pageSize: page.geometry.pageSize)
            }
            guard let data = Self.encode(image, type: type, quality: options.jpegQuality, dpi: options.imageDPI) else {
                throw ExportError.writeFailed
            }
            let name = pages.count == 1 ? "\(base).\(ext)" : ExportNaming.numbered(base, index: index + 1, total: pages.count, ext: ext)
            if let zip {
                try zip.writer.addFile(named: name, data: data)
            } else {
                let url = directory.appendingPathComponent(name)
                try data.write(to: url, options: .atomic)
                files.append(url)
            }
            progress(ExportProgress(completedPages: index + 1, totalPages: pages.count))
        }
        if let zip {
            try zip.writer.finish()
            files = [zip.url]
        }
        return files
    }

    static func encode(_ image: CGImage, type: UTType, quality: Double, dpi: Int?) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        var properties: [CFString: Any] = [:]
        if type == .jpeg { properties[kCGImageDestinationLossyCompressionQuality] = quality }
        if let dpi {
            properties[kCGImagePropertyDPIWidth] = dpi
            properties[kCGImagePropertyDPIHeight] = dpi
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

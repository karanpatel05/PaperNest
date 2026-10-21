import CoreGraphics
import Foundation
import ImageIO
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
    public func export(
        itemName: String,
        pages: [Page],
        options: ExportOptions,
        progress: @Sendable (ExportProgress) -> Void = { _ in }
    ) async throws -> ExportOutput {
        guard !pages.isEmpty else { throw ExportError.noPages }
        let directory = temporaryRoot.appendingPathComponent("PaperNestExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let base = ExportNaming.baseName(itemName)
            let files: [URL] = switch options.format {
            case .pdf: [try await writePDF(pages, title: itemName, to: directory.appendingPathComponent("\(base).pdf"), options: options, progress: progress)]
            case .jpeg, .png: try await writeImages(pages, base: base, in: directory, options: options, progress: progress)
            }
            return ExportOutput(directory: directory, files: files)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    // MARK: - PDF

    private func writePDF(_ pages: [Page], title: String, to url: URL, options: ExportOptions,
                          progress: @Sendable (ExportProgress) -> Void) async throws -> URL {
        var defaultBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let info: [CFString: Any] = [kCGPDFContextCreator: Brand.pdfCreator, kCGPDFContextTitle: title]
        guard let ctx = CGContext(url as CFURL, mediaBox: &defaultBox, info as CFDictionary) else { throw ExportError.writeFailed }
        var closed = false
        defer { if !closed { ctx.closePDF() } }

        progress(ExportProgress(completedPages: 0, totalPages: pages.count))
        for (index, page) in pages.enumerated() {
            try Task.checkCancellation()
            let pageSize = page.geometry.pageSize
            let layout = PaperLayout(pageSize: pageSize, paper: options.paperSize)
            let source = try await pdfSource(for: page, layout: layout, quality: options.pdfImageQuality)

            var box = CGRect(origin: .zero, size: layout.paperSize)
            let boxData = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
            ctx.beginPDFPage([kCGPDFContextMediaBox: boxData] as CFDictionary)
            // Paper space is y-down in our model; PDF user space is y-up.
            let pageToContext = layout.pageToPaper(pageSize: pageSize)
                .concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: layout.paperSize.height))
            PageRenderer.draw(page, source: source, in: ctx, pageToContext: pageToContext)
            ctx.endPDFPage()
            progress(ExportProgress(completedPages: index + 1, totalPages: pages.count))
        }
        ctx.closePDF()
        closed = true
        return url
    }

    /// Vector PDF pages pass through untouched; raster content is limited to
    /// the quality's resolution and, for lossy settings, JPEG-encoded so the
    /// PDF embeds it with DCT compression.
    private func pdfSource(for page: Page, layout: PaperLayout, quality: PDFImageQuality) async throws -> PageRenderer.PreparedSource {
        let pageScale = layout.contentRect.width / page.geometry.pageSize.width
        let pixelsPerPoint = quality.maxDPI / 72 * pageScale
        let source = try await renderer.prepareSource(for: page, pixelsPerPoint: pixelsPerPoint)
        guard case .image(let image, let covering) = source, let jpegQuality = quality.jpegQuality else { return source }
        let maxPixels = Int((max(covering.width, covering.height) * pixelsPerPoint).rounded(.up))
        let limited = try Self.downsample(image, maxPixelSize: maxPixels)
        guard let data = Self.encode(limited, type: .jpeg, quality: jpegQuality, dpi: nil),
              let provider = CGDataProvider(data: data as CFData),
              let jpeg = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return source }
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
        let type: UTType = options.format == .jpeg ? .jpeg : .png
        let ext = options.format.fileExtension
        let pixelsPerPoint = CGFloat(options.imageDPI) / 72
        let zip: (writer: ZipWriter, url: URL)? = if pages.count > 1, options.packaging == .zip {
            (try ZipWriter(url: directory.appendingPathComponent("\(base).zip")), directory.appendingPathComponent("\(base).zip"))
        } else {
            nil
        }
        var files: [URL] = []
        progress(ExportProgress(completedPages: 0, totalPages: pages.count))
        for (index, page) in pages.enumerated() {
            try Task.checkCancellation()
            // Rendered onto opaque white, so JPEG never turns dark ink on a
            // transparent page into black-on-black.
            let image = try await renderer.renderImage(page, pixelsPerPoint: pixelsPerPoint)
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

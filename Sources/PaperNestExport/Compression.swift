import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import PaperNestCore
import PaperNestRender
import UniformTypeIdentifiers

/// How hard to try when reducing a document's size.
///
/// Named for the effect rather than a resolution, because the number that
/// matters to someone compressing a file is how small it gets, not the dpi it
/// got there with. The values sit alongside the export sheet's quality tiers:
/// `light` matches its balanced setting, `strong` its compact one, and
/// `smallest` goes below anything the sheet offers.
public enum CompressionPreset: String, Codable, Sendable, CaseIterable {
    case light, strong, smallest

    var rasterQuality: RasterQuality {
        switch self {
        case .light: RasterQuality(maxDPI: 300, jpegQuality: 0.85)
        case .strong: RasterQuality(maxDPI: 150, jpegQuality: 0.6)
        case .smallest: RasterQuality(maxDPI: 110, jpegQuality: 0.4)
        }
    }
}

/// What a compressed image file is written as.
///
/// JPEG is the default and that is a decision, not an oversight: compression
/// exists to make a file easier to send, and handing back something the
/// recipient cannot open is a worse outcome than a larger file that works.
public enum CompressionFormat: String, Codable, Sendable, CaseIterable {
    /// Opens everywhere.
    case jpeg
    /// About a third of the JPEG at the same quality — 94,742 bytes against
    /// 284,377, measured — but older systems, many Windows installs and
    /// plenty of upload forms cannot read one. The caller opts in.
    case heic

    var type: UTType {
        switch self {
        case .jpeg: .jpeg
        case .heic: .heic
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .heic: "heic"
        }
    }
}

/// What a compression run produced, and what it actually saved.
///
/// `isSmaller` and `savedByteCount` exist so a caller can tell "this made the
/// file smaller by N" apart from "this source cannot be reduced". Re-encoding
/// an already-compact original makes it *larger*, and a document of vector PDF
/// pages passes through untouched, so "no saving" is a normal, honest outcome
/// and never a negative number dressed up as a positive one.
public struct CompressionResult: Sendable {
    public let preset: CompressionPreset
    /// The originals the document is made of, before anything was written.
    public let originalByteCount: Int64
    public let output: ExportOutput

    public init(preset: CompressionPreset, originalByteCount: Int64, output: ExportOutput) {
        self.preset = preset
        self.originalByteCount = originalByteCount
        self.output = output
    }

    public var compressedByteCount: Int64 { output.totalByteCount }

    /// True only when the output really is smaller than what it came from.
    public var isSmaller: Bool { originalByteCount > 0 && compressedByteCount < originalByteCount }

    /// How many bytes were saved, or zero when nothing was.
    public var savedByteCount: Int64 { isSmaller ? originalByteCount - compressedByteCount : 0 }

    /// 0...1, or nil when there is nothing to compare against.
    public var savedFraction: Double? {
        guard originalByteCount > 0 else { return nil }
        return Double(savedByteCount) / Double(originalByteCount)
    }
}

extension Exporter {
    /// Writes `pages` as a PDF at `preset`, and reports what that cost and
    /// saved against `originalByteCount`.
    ///
    /// Pass the originals' size from `LibraryStore.originalByteCount(of:)`:
    /// the paper the document is made of, rather than the size of a previous
    /// export, which would depend on the settings that export was made with.
    ///
    /// This writes only to its own temporary directory. Originals are
    /// immutable and nothing in the library is touched, so it is an export
    /// that happens to be measured, not an edit.
    public func compress(
        itemName: String,
        pages: [Page],
        originalByteCount: Int64,
        preset: CompressionPreset,
        progress: @Sendable (ExportProgress) -> Void = { _ in }
    ) async throws -> CompressionResult {
        let options = ExportOptions(format: .pdf, paperSize: .original)
        let output = try await export(itemName: itemName, pages: pages, options: options,
                                      rasterQuality: preset.rasterQuality, progress: progress)
        return CompressionResult(preset: preset, originalByteCount: originalByteCount, output: output)
    }
}

/// Why a file could not be reduced.
public enum CompressionError: Error, Equatable, Sendable {
    /// The bytes are not an image this can decode and re-encode — a document,
    /// an archive, a video. Refusing is the honest answer: writing a
    /// "compressed" file that was really a broken re-encode would be worse
    /// than leaving the original alone.
    case unsupportedFormat
}

extension CompressionPreset {
    /// The longest edge an image file is reduced to.
    ///
    /// A loose file has no page size, so a preset's resolution cannot be
    /// expressed as dpi here the way it is for a document page; it shows up as
    /// pixels instead.
    var maxPixelSize: Int {
        switch self {
        case .light: 2400
        case .strong: 1600
        case .smallest: 1200
        }
    }
}

extension Exporter {
    /// Re-encodes an image file smaller, and reports what that actually saved.
    ///
    /// Most photos arrive already compressed, so re-encoding one can easily
    /// make it larger; `CompressionResult` reports that as no saving rather
    /// than a negative one. Originals are immutable, so this writes a new file
    /// in its own temporary directory and never replaces what the library
    /// stores — the caller removes the directory when it is done.
    ///
    /// A PDF is handled page by page instead: pages that carry text are copied
    /// untouched, and pages that do not are re-encoded at the preset and kept
    /// only when they beat the page they would replace. A PDF whose pages all
    /// carry text therefore comes back readable and reports no saving — it is
    /// a file this can read and simply cannot make smaller, which is not the
    /// same as one it cannot read.
    ///
    /// Throws `CompressionError.unsupportedFormat` for bytes that are neither
    /// a re-encodable image nor a readable PDF, having written nothing.
    public func compress(fileNamed name: String, data: Data, preset: CompressionPreset,
                         format: CompressionFormat = .jpeg) async throws -> CompressionResult {
        // `format` does not apply here: HEIC is not a PDF image filter, so a
        // document's pages cannot use it whatever the caller asked for.
        //
        // A PDF is reduced page by page rather than re-encoded as one image:
        // its pages are not all photographs, and the ones that carry text must
        // keep carrying it.
        if let document = PDFDocument(data: data), document.pageCount > 0 {
            return try Self.compressPDF(named: name, document: document, data: data,
                                        preset: preset, temporaryRoot: temporaryRoot)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw CompressionError.unsupportedFormat }

        // Everything that can fail happens before a directory exists, so a
        // refusal leaves nothing behind.
        let reduced = try Self.downsample(image, maxPixelSize: preset.maxPixelSize)
        guard let encoded = Self.encode(reduced, type: format.type,
                                        quality: preset.rasterQuality.jpegQuality ?? 0.85, dpi: nil)
        else { throw ExportError.writeFailed }

        let directory = temporaryRoot.appendingPathComponent("PaperNestExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let base = ExportNaming.baseName((name as NSString).deletingPathExtension)
            let url = directory.appendingPathComponent("\(base).\(format.fileExtension)")
            try encoded.write(to: url)
            return CompressionResult(preset: preset, originalByteCount: Int64(data.count),
                                     output: ExportOutput(directory: directory, files: [url]))
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}


extension Exporter {
    /// Reduces a PDF held as loose bytes, page by page.
    ///
    /// The output is assembled fresh in PDFKit and the untouched pages are
    /// `copy()`d, so whatever they carry — links, annotations, a form field's
    /// name — comes with them. Everything that can fail happens before the
    /// temporary directory exists, so a refusal still writes nothing.
    static func compressPDF(named name: String, document: PDFDocument, data: Data,
                            preset: CompressionPreset, temporaryRoot: URL) throws -> CompressionResult {
        // A protected PDF is refused, measured rather than assumed. A locked
        // document hands back no text, so every page looks like a scan; the
        // locked `CGPDFDocument` then draws nothing, and the resulting white
        // page beats any budget — a blank sheet reported as a 99% saving (845
        // bytes from 8,110, one grey level). Even where the content does come
        // through, as with an owner password that only restricts copying,
        // assembling the output fresh drops the author's restrictions and
        // hands back an unrestricted copy. Neither is ours to do.
        guard !document.isEncrypted, !document.isLocked else {
            throw CompressionError.unsupportedFormat
        }
        guard let provider = CGDataProvider(data: data as CFData),
              let readable = CGPDFDocument(provider) else { throw CompressionError.unsupportedFormat }

        let output = PDFDocument()
        output.documentAttributes = document.documentAttributes
        // A copied page is read lazily from the document it came from, so each
        // rebuilt page's document has to stay alive until the output has been
        // serialized. Letting one go out of scope leaves a blank page behind,
        // and the file still looks like a triumph of compression.
        var rebuilt: [PDFDocument] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { throw ExportError.writeFailed }
            if !Self.carriesText(document, at: index),
               let reduced = Self.reEncodedPage(readable, pageNumber: index + 1, page: page,
                                                preset: preset, keeping: &rebuilt) {
                output.insert(reduced, at: output.pageCount)
                continue
            }
            guard let copy = page.copy() as? PDFPage else { throw ExportError.writeFailed }
            output.insert(copy, at: output.pageCount)
        }
        guard output.pageCount == document.pageCount,
              let encoded = output.dataRepresentation() else { throw ExportError.writeFailed }
        withExtendedLifetime(rebuilt) {}

        let directory = temporaryRoot.appendingPathComponent("PaperNestExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let base = ExportNaming.baseName((name as NSString).deletingPathExtension)
            let url = directory.appendingPathComponent("\(base).pdf")
            try encoded.write(to: url)
            return CompressionResult(preset: preset, originalByteCount: Int64(data.count),
                                     output: ExportOutput(directory: directory, files: [url]))
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    /// One page as a JPEG at the preset, or nil to keep the page as it is.
    ///
    /// Nil whenever the page cannot be rasterized at this resolution (an A0
    /// page at 300 dpi is past the 100M-pixel cap), cannot be encoded, or —
    /// the common case — comes out no smaller than the page it would replace.
    /// Light is 300 dpi, which upsamples most scans, so it usually declines.
    private static func reEncodedPage(_ readable: CGPDFDocument, pageNumber: Int, page: PDFPage,
                                      preset: CompressionPreset,
                                      keeping rebuilt: inout [PDFDocument]) -> PDFPage? {
        // The size has to be the *upright* crop box, not PDFKit's media box.
        // `drawPDFContent` scales content to the upright crop box and applies
        // the page's rotation, so taking 612×792 from a `/Rotate 90` page —
        // an ordinary landscape phone scan — squeezes 792×612 of content into
        // a portrait bitmap and puts it on an unrotated portrait page.
        guard let cgPage = readable.page(at: pageNumber) else { return nil }
        let box = cgPage.getBoxRect(.cropBox)
        let upright = PageGeometry.uprightPDFSize(box: box, rotationDegrees: Int(cgPage.rotationAngle))
        guard upright.width > 0, upright.height > 0 else { return nil }
        let quality = preset.rasterQuality
        let region = CGRect(origin: .zero, size: upright)
        guard let raster = try? PageRenderer.rasterizePDFPage(
                  readable, pageNumber: pageNumber, sourceSize: upright,
                  region: region, pixelsPerPoint: quality.maxDPI / 72),
              let jpeg = Self.encode(raster, type: .jpeg, quality: quality.jpegQuality ?? 0.85, dpi: nil),
              let source = CGDataProvider(data: jpeg as CFData),
              let image = CGImage(jpegDataProviderSource: source, decode: nil,
                                  shouldInterpolate: true, intent: .defaultIntent),
              let encoded = Self.singlePagePDF(image, size: upright),
              let budget = Self.byteCount(of: page),
              encoded.count < budget,
              let source = PDFDocument(data: encoded),
              let replacement = source.page(at: 0)?.copy() as? PDFPage
        else { return nil }
        rebuilt.append(source)
        return replacement
    }

    /// A one-page PDF of `image` filling a page of `size`.
    private static func singlePagePDF(_ image: CGImage, size: CGSize) -> Data? {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        ctx.beginPDFPage(nil)
        ctx.draw(image, in: box)
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }
}

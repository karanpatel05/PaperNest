import CoreGraphics
import Foundation
import ImageIO
import PaperNestCore
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
    /// Throws `CompressionError.unsupportedFormat` for bytes that are not a
    /// re-encodable image, having written nothing.
    public func compress(fileNamed name: String, data: Data, preset: CompressionPreset) async throws -> CompressionResult {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw CompressionError.unsupportedFormat }

        // Everything that can fail happens before a directory exists, so a
        // refusal leaves nothing behind.
        let reduced = try Self.downsample(image, maxPixelSize: preset.maxPixelSize)
        guard let encoded = Self.encode(reduced, type: .jpeg,
                                        quality: preset.rasterQuality.jpegQuality ?? 0.85, dpi: nil)
        else { throw ExportError.writeFailed }

        let directory = temporaryRoot.appendingPathComponent("PaperNestExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let base = ExportNaming.baseName((name as NSString).deletingPathExtension)
            let url = directory.appendingPathComponent("\(base).jpg")
            try encoded.write(to: url)
            return CompressionResult(preset: preset, originalByteCount: Int64(data.count),
                                     output: ExportOutput(directory: directory, files: [url]))
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}

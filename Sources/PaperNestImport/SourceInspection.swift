import CoreGraphics
import Foundation
import ImageIO
import PaperNestCore
import PDFKit

/// Detects file types from their leading bytes. Extensions are not trusted:
/// a renamed file must not be stored under the wrong type.
public enum FileTypeSniffer {
    /// ISO base media format: a `ftyp` box at offset 4, then a brand that
    /// says the payload is HEIF-with-HEVC. Brands outside this list (`avif`,
    /// for instance) are deliberately not claimed.
    static func isHEIC(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 12, Array(bytes[4..<8]) == Array("ftyp".utf8) else { return false }
        let brand = String(decoding: bytes[8..<12], as: UTF8.self)
        return ["heic", "heix", "heim", "heis", "hevc", "hevm", "hevs", "mif1", "msf1"].contains(brand)
    }

    /// A RIFF container whose payload is WebP: `RIFF` at 0, `WEBP` at 8.
    /// `RIFF` alone is not enough — WAV and AVI open identically, and
    /// claiming one of those would import an audio file as a page.
    static func isWebP(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 12
            && Array(bytes[0..<4]) == Array("RIFF".utf8)
            && Array(bytes[8..<12]) == Array("WEBP".utf8)
    }

    public static func kind(of data: Data) -> AssetKind? {
        let bytes = [UInt8](data.prefix(1024))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
        if isHEIC(bytes) { return .heic }
        if isWebP(bytes) { return .webp }
        // "%PDF-" may be preceded by junk bytes; readers accept it within the first 1 KB.
        let pdfMarker: [UInt8] = Array("%PDF-".utf8)
        if bytes.count >= pdfMarker.count {
            for start in 0...(bytes.count - pdfMarker.count) where bytes[start..<start + pdfMarker.count].elementsEqual(pdfMarker) {
                return .pdf
            }
        }
        return nil
    }
}

/// Facts about a raster original needed to create its page.
struct ImageFacts {
    var uprightPixelSize: CGSize
    var pointSize: CGSize
}

enum ImageInspector {
    /// Above this many pixels decoding risks exhausting memory on phones.
    static let maxPixelCount: CGFloat = 200_000_000

    static func inspect(_ data: Data, expected: AssetKind, filename: String) throws -> ImageFacts {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0
        else {
            throw ImportError.damaged(filename: filename)
        }
        guard width * height <= maxPixelCount else { throw ImportError.tooLarge(filename: filename) }
        // ImageIO decodes truncated files without complaint, filling the
        // missing part with gray, so completeness is checked structurally.
        guard isStructurallyComplete(data, kind: expected) else { throw ImportError.damaged(filename: filename) }
        // Decode a small version to prove the pixel data itself is readable,
        // not just the header.
        let probe: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard CGImageSourceCreateThumbnailAtIndex(source, 0, probe as CFDictionary) != nil else {
            throw ImportError.damaged(filename: filename)
        }
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        // EXIF orientations 5...8 are rotated a quarter turn.
        let upright = (5...8).contains(orientation) ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        var dpi: CGSize?
        if let dx = (props[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue,
           let dy = (props[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue {
            dpi = (5...8).contains(orientation) ? CGSize(width: dy, height: dx) : CGSize(width: dx, height: dy)
        }
        return ImageFacts(uprightPixelSize: upright, pointSize: ImageResolutionPolicy.pointSize(pixelSize: upright, dpi: dpi))
    }
}

extension ImageInspector {
    /// JPEG: the last start-of-scan (FF DA) must be followed by an
    /// end-of-image marker (FF D9). Inside entropy-coded data every FF byte
    /// is stuffed, so FF D9 can only be the real marker.
    /// PNG: an IEND chunk must be present.
    static func isStructurallyComplete(_ data: Data, kind: AssetKind) -> Bool {
        let bytes = [UInt8](data)
        switch kind {
        case .jpeg:
            guard let lastScan = lastIndex(of: [0xFF, 0xDA], in: bytes) else { return false }
            return lastIndex(of: [0xFF, 0xD9], in: bytes).map { $0 > lastScan } ?? false
        case .png:
            return lastIndex(of: Array("IEND".utf8), in: bytes) != nil
        case .heic:
            // ISO-BMFF has no end marker. The boxes are walked instead: a
            // truncated file runs past its own last box.
            return boxChainIsComplete(bytes)
        case .webp:
            // RIFF carries its own length: a 32-bit little-endian size at
            // offset 4, counting everything after it. A truncated file claims
            // more than it has.
            guard bytes.count >= 12 else { return false }
            let declared = UInt32(bytes[4]) | UInt32(bytes[5]) << 8 | UInt32(bytes[6]) << 16 | UInt32(bytes[7]) << 24
            return Int(declared) + 8 <= bytes.count
        case .pdf:
            return true
        case .file:
            // Bytes we do not interpret have no structure to check. A file
            // item keeps whatever it was given.
            return true
        }
    }

    /// Walks the top-level box chain. Each box is a 4-byte big-endian size
    /// then a 4-byte type; the last one must end exactly at the end of the
    /// file.
    static func boxChainIsComplete(_ bytes: [UInt8]) -> Bool {
        var offset = 0
        while offset + 8 <= bytes.count {
            var size = 0
            for byte in bytes[offset..<(offset + 4)] { size = size << 8 | Int(byte) }
            if size == 0 { return offset + 8 == bytes.count }   // "to end of file"
            if size == 1 {
                guard offset + 16 <= bytes.count else { return false }
                var large = 0
                for byte in bytes[(offset + 8)..<(offset + 16)] { large = large << 8 | Int(byte) }
                size = large
            }
            guard size >= 8 else { return false }
            offset += size
        }
        return offset == bytes.count
    }

    private static func lastIndex(of pattern: [UInt8], in bytes: [UInt8]) -> Int? {
        guard bytes.count >= pattern.count else { return nil }
        var i = bytes.count - pattern.count
        while i >= 0 {
            if bytes[i] == pattern[0], bytes[i..<i + pattern.count].elementsEqual(pattern) { return i }
            i -= 1
        }
        return nil
    }
}

/// Facts about a PDF original needed to create its pages.
struct PDFFacts {
    /// Bytes to store: the original, or for a password-protected file the
    /// unlocked copy (see `PDFInspector.open`).
    var storedData: Data
    var pageSizes: [CGSize]
}

enum PDFInspector {
    static func open(_ data: Data, password: String?, filename: String) throws -> PDFFacts {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider) else {
            throw ImportError.damaged(filename: filename)
        }
        guard document.isUnlocked else {
            return try unlockedCopy(of: data, pageCount: document.numberOfPages, password: password, filename: filename)
        }
        guard document.allowsCopying, document.allowsPrinting else { throw ImportError.restrictedPDF(filename: filename) }
        return try facts(for: document, stored: data, filename: filename)
    }

    /// The library keeps a copy that opens without the password, so the
    /// password itself is never stored. PDFKit's `dataRepresentation()` of
    /// an unlocked document stays encrypted (verified on macOS 26), so the
    /// pages are copied into a new, unencrypted document instead; the result
    /// is verified before it is accepted.
    private static func unlockedCopy(of data: Data, pageCount: Int, password: String?, filename: String) throws -> PDFFacts {
        guard let password, !password.isEmpty else { throw ImportError.passwordRequired(filename: filename) }
        guard let kitDocument = PDFDocument(data: data), kitDocument.unlock(withPassword: password) else {
            throw ImportError.incorrectPassword(filename: filename)
        }
        guard kitDocument.allowsCopying, kitDocument.allowsPrinting else { throw ImportError.restrictedPDF(filename: filename) }
        let copy = PDFDocument()
        for index in 0..<kitDocument.pageCount {
            guard let page = kitDocument.page(at: index)?.copy() as? PDFPage else {
                throw ImportError.protectedPDFUnsupported(filename: filename)
            }
            copy.insert(page, at: copy.pageCount)
        }
        guard let unlocked = copy.dataRepresentation(),
              let check = CGDataProvider(data: unlocked as CFData).flatMap(CGPDFDocument.init),
              check.isUnlocked, !check.isEncrypted, check.numberOfPages == pageCount
        else {
            throw ImportError.protectedPDFUnsupported(filename: filename)
        }
        return try facts(for: check, stored: unlocked, filename: filename)
    }

    private static func facts(for document: CGPDFDocument, stored: Data, filename: String) throws -> PDFFacts {
        guard document.numberOfPages > 0 else { throw ImportError.empty(filename: filename) }
        var sizes: [CGSize] = []
        for number in 1...document.numberOfPages {
            guard let page = document.page(at: number) else { throw ImportError.damaged(filename: filename) }
            let box = page.getBoxRect(.cropBox)
            guard box.width > 0, box.height > 0 else { throw ImportError.damaged(filename: filename) }
            sizes.append(PageGeometry.uprightPDFSize(box: box, rotationDegrees: Int(page.rotationAngle)))
        }
        return PDFFacts(storedData: stored, pageSizes: sizes)
    }
}

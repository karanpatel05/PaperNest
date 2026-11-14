import CoreGraphics
import Foundation
import PaperNestCore

public enum ExportFormat: String, Codable, Sendable, CaseIterable {
    case pdf, jpeg, png
    /// Plain text, from what the pages really carry. `ExportOptions`' paper,
    /// resolution and quality do not apply to it.
    case txt
    /// Images as HEIC, which is a third the size of the same page as JPEG
    /// (94,742 bytes against 284,377, measured) at the same quality and keeps
    /// the dpi asked for.
    ///
    /// The cost is compatibility, and it is the whole caveat: exporting exists
    /// to send a file somewhere, and older systems, many Windows installs and
    /// plenty of web forms cannot open a HEIC. JPEG stays the safe default.
    case heic
    /// A Word file holding the same text as `.txt`, one paragraph per line.
    /// The words, not the layout: `ExportOptions`' paper, resolution and
    /// quality do not apply to it either.
    case docx

    /// Whether this format carries the words alone, with no picture of the
    /// page.
    ///
    /// The sheet reads this to decide which options to show: resolution,
    /// image quality and how to package several pages all mean nothing for a
    /// text file, and a control that does nothing is worse than no control.
    /// Kept on the format rather than in the screen so the two cannot
    /// disagree about which is which.
    public var keepsOnlyWords: Bool {
        switch self {
        case .txt, .docx: true
        case .pdf, .jpeg, .png, .heic: false
        }
    }

    /// Whether this format can be protected with a password.
    ///
    /// Only a PDF can. Writing an unprotected JPEG, TXT or DOCX when the
    /// caller asked for protection would be a silent false promise, which is
    /// why `export` refuses it — this is the same rule, where a screen can
    /// read it and not offer the field at all.
    public var canCarryPassword: Bool { self == .pdf }

    public var fileExtension: String {
        switch self {
        case .pdf: "pdf"
        case .jpeg: "jpg"
        case .png: "png"
        case .heic: "heic"
        case .txt: "txt"
        case .docx: "docx"
        }
    }
}

/// How raster content (scans, filtered pages) is embedded in a PDF. Vector
/// PDF pages without filters are always copied as vectors, whatever is chosen.
public enum PDFImageQuality: String, Codable, Sendable, CaseIterable {
    /// Lossless; largest files.
    case best
    /// JPEG at high quality, up to 300 dpi.
    case balanced
    /// JPEG at moderate quality, up to 150 dpi.
    case compact

    var jpegQuality: Double? {
        switch self {
        case .best: nil
        case .balanced: 0.85
        case .compact: 0.6
        }
    }

    var maxDPI: CGFloat {
        switch self {
        case .best: 600
        case .balanced: 300
        case .compact: 150
        }
    }
}

/// The resolution and lossy quality raster content is written at.
///
/// Separate from `PDFImageQuality` so a compression preset can ask for values
/// of its own without adding a case to that enum, which is `CaseIterable` and
/// drives the export sheet's picker.
struct RasterQuality: Hashable, Sendable {
    var maxDPI: CGFloat
    /// Nil means lossless.
    var jpegQuality: Double?
}

extension PDFImageQuality {
    var rasterQuality: RasterQuality { RasterQuality(maxDPI: maxDPI, jpegQuality: jpegQuality) }
}

public enum ImagePackaging: String, Codable, Sendable, CaseIterable {
    /// One file per page.
    case separateFiles
    /// One ZIP archive with deterministic, numbered entries.
    case zip
}

public struct ExportOptions: Hashable, Sendable {
    public var format: ExportFormat
    /// PDF only. Content is fitted whole, never cropped.
    public var paperSize: PaperSize
    public var pdfImageQuality: PDFImageQuality
    /// JPEG/PNG only.
    public var imageDPI: Int
    /// JPEG only, 0.1...1.
    public var jpegQuality: Double
    /// JPEG/PNG with more than one page.
    public var packaging: ImagePackaging
    /// PDF only. Writes each page's recognized text as an invisible layer, so
    /// a scan can be searched and selected outside PaperNest. Only text that
    /// is current for the page is written; nothing is invented.
    public var includesRecognizedText: Bool

    public init(
        format: ExportFormat = .pdf,
        paperSize: PaperSize = .original,
        pdfImageQuality: PDFImageQuality = .balanced,
        imageDPI: Int = 200,
        jpegQuality: Double = 0.85,
        packaging: ImagePackaging = .zip,
        includesRecognizedText: Bool = true
    ) {
        self.format = format
        self.paperSize = paperSize
        self.pdfImageQuality = pdfImageQuality
        self.imageDPI = min(max(imageDPI, 36), 600)
        self.jpegQuality = min(max(jpegQuality, 0.1), 1)
        self.packaging = packaging
        self.includesRecognizedText = includesRecognizedText
    }

    public static let imageDPIChoices = [72, 150, 200, 300]
}

public struct ExportProgress: Sendable, Equatable {
    public var completedPages: Int
    public var totalPages: Int

    public init(completedPages: Int, totalPages: Int) {
        self.completedPages = completedPages
        self.totalPages = totalPages
    }

    public var fraction: Double { totalPages == 0 ? 1 : Double(completedPages) / Double(totalPages) }
}

/// Files produced by an export, inside a private temporary directory that
/// the caller removes once the user has saved or shared them.
public struct ExportOutput: Sendable {
    public var directory: URL
    public var files: [URL]

    public var totalByteCount: Int64 {
        files.reduce(0) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    public func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// What an export is for. The author of a PDF can allow one and not the other.
public enum ExportPurpose: Sendable {
    /// A file to keep, share or copy.
    case file
    /// The PDF handed to the system's print panel.
    case printing
}

public enum ExportError: Error, Equatable, Sendable {
    case noPages
    case writeFailed
    /// A page comes from a PDF whose author does not allow copying, and the
    /// format asked for would hand its words or pictures out unprotected.
    /// Only a PDF can keep the author's limits, so only a PDF is written.
    case copyingNotAllowed
    /// A page comes from a PDF whose author does not allow printing.
    case printingNotAllowed
    case archiveTooLarge
    /// A text export where no page has any text. Writing a file holding
    /// nothing but page separators would look like a successful export of an
    /// empty document, which is not what happened.
    case noTextToExport
    /// A password was supplied for a format that cannot carry one. Writing an
    /// unprotected JPEG, TXT or DOCX when the caller asked for protection
    /// would be a silent false promise, so it is refused instead.
    case passwordNotSupported
    /// An empty password was supplied. It would be written as both the user
    /// and the owner password, producing a file that opens with nothing while
    /// the caller believes it is protected. An empty text field is the most
    /// likely source of exactly this value.
    case emptyPassword
    /// A password containing characters the writer cannot store: in practice
    /// anything outside ASCII. Measured on this platform — PDFKit's
    /// `write(to:withOptions:)` returned false for `"contraseña-密码-1"`, and
    /// an export with `"été-Ñandú-2026"` failed to write even though those
    /// characters are Latin-1. Refused up front so it fails where it can be
    /// explained, rather than as a write error after the fact.
    ///
    /// This is a real limitation for French and Spanish users, and whoever
    /// builds the screen has to say so rather than rejecting their password
    /// with a generic error.
    case passwordNotRepresentable
}

/// Filenames for exported files.
public enum ExportNaming {
    /// Characters unsafe on at least one target file system or share target.
    private static let unsafe = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.controlCharacters).union(.newlines)

    public static func baseName(_ name: String, fallback: String = "Document") -> String {
        let replaced = name.unicodeScalars.map { unsafe.contains($0) ? "-" : String($0) }.joined()
        let trimmed = replaced.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
        let limited = String(trimmed.prefix(120))
        return limited.isEmpty ? fallback : limited
    }

    /// `Name-001.jpg`; the number is padded to fit `total` (at least 3 digits)
    /// so names sort in page order.
    public static func numbered(_ base: String, index: Int, total: Int, ext: String) -> String {
        let width = max(3, String(total).count)
        let number = String(index)
        return "\(base)-\(String(repeating: "0", count: max(0, width - number.count)))\(number).\(ext)"
    }
}

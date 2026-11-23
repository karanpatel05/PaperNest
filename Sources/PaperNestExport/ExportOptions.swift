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
    /// A Word file, in one of two layouts chosen by `ExportOptions.docxLayout`:
    /// the same text as `.txt`, one paragraph per line, or each page as a
    /// picture. The brief asks for both and for them to be named apart.
    case docx

    /// Whether this format, **in its default layout**, carries the words
    /// alone, with no picture of the page.
    ///
    /// A screen should ask `ExportOptions.keepsOnlyWords` instead: a Word
    /// file of page images is a `.docx` that carries pictures and no words,
    /// and only the options know which layout was chosen. This stays as the
    /// property of the format alone, true for TXT and for Word's default.
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

/// What a Word export holds. The product brief asks for both, "clearly
/// named": a Word file of words to edit, and one that looks like the pages.
/// They are different promises, so neither may be described as the other —
/// above all, the picture layout is not an editable or OCR conversion.
public enum DocxLayout: String, Codable, Sendable, CaseIterable {
    /// One paragraph per line of text the pages really carry. Refused when
    /// no page has any (`ExportError.noTextToExport`).
    case editableText
    /// Each page as one picture filling a Word page of the page's own size,
    /// ink and marks included. No words, so it needs none: a blank or
    /// handwritten notebook exports this way.
    case pageImages
}

public enum ImagePackaging: String, Codable, Sendable, CaseIterable {
    /// One file per page.
    case separateFiles
    /// One ZIP archive with deterministic, numbered entries.
    case zip
}

public struct ExportOptions: Hashable, Sendable {
    public var format: ExportFormat
    /// PDF, and Word page images. Content is fitted whole, never cropped.
    public var paperSize: PaperSize
    public var pdfImageQuality: PDFImageQuality
    /// JPEG/PNG/HEIC, and the pictures in Word page images.
    public var imageDPI: Int
    /// JPEG, and the pictures in Word page images (which are JPEG), 0.1...1.
    public var jpegQuality: Double
    /// JPEG/PNG with more than one page.
    public var packaging: ImagePackaging
    /// PDF only. Writes each page's recognized text as an invisible layer, so
    /// a scan can be searched and selected outside PaperNest. Only text that
    /// is current for the page is written; nothing is invented.
    public var includesRecognizedText: Bool
    /// Word only: words to edit, or pictures of the pages.
    public var docxLayout: DocxLayout
    /// PDF only. Writes each page's comments as notes — PDF text annotations,
    /// the sticky notes other PDF readers show beside the page. Off unless
    /// asked: a comment stays private until its author chooses to send it.
    public var includesComments: Bool
    /// A mark drawn over every exported page, or nil for none.
    ///
    /// Nil unless the export sheet sets it, so the backup, printing, the
    /// form workspace and Compress — which build their own options — never
    /// draw one. It lives only here: the library stores nothing about it.
    public var watermark: Watermark?
    /// The small PaperNest mark a free export carries (`Watermark.attribution`),
    /// drawn after `watermark`. Set by the export sheet, bulk export,
    /// Compress and printing for someone without Pro; nil everywhere else,
    /// the backup and the form workspace included.
    public var attribution: Watermark?

    public init(
        format: ExportFormat = .pdf,
        paperSize: PaperSize = .original,
        pdfImageQuality: PDFImageQuality = .balanced,
        imageDPI: Int = 200,
        jpegQuality: Double = 0.85,
        packaging: ImagePackaging = .zip,
        includesRecognizedText: Bool = true,
        docxLayout: DocxLayout = .editableText,
        includesComments: Bool = false,
        watermark: Watermark? = nil,
        attribution: Watermark? = nil
    ) {
        self.format = format
        self.paperSize = paperSize
        self.pdfImageQuality = pdfImageQuality
        self.imageDPI = min(max(imageDPI, 36), 600)
        self.jpegQuality = min(max(jpegQuality, 0.1), 1)
        self.packaging = packaging
        self.includesRecognizedText = includesRecognizedText
        self.docxLayout = docxLayout
        self.includesComments = includesComments
        self.watermark = watermark
        self.attribution = attribution
    }

    public static let imageDPIChoices = [72, 150, 200, 300]

    /// Whether the file these options produce carries the words alone, with
    /// no picture of the page — which is what decides that resolution,
    /// quality and paper mean nothing for it, and that the export is refused
    /// when no page has any text.
    ///
    /// On the options rather than the format because Word is both: its
    /// editable-text layout keeps only words, its page-image layout keeps
    /// only pictures. A screen that asked the format would hide the
    /// resolution of a Word file made of pictures, and tell its reader that
    /// pictures are left out of it.
    public var keepsOnlyWords: Bool {
        format == .docx ? docxLayout == .editableText : format.keepsOnlyWords
    }

    /// Whether exporting `pageCount` pages with these options writes one ZIP
    /// rather than the file itself.
    ///
    /// Only pictures are ever packed: several JPEG, PNG or HEIC pages, when
    /// ZIP was chosen. A PDF, a text file and a Word file hold every page in
    /// one file of their own, whatever `packaging` says — `packaging` is not
    /// even shown for them, so a value left over from an earlier choice must
    /// not decide it. The writer and the screen both read this, so the
    /// clipboard is never refused a single `.docx` because of a ZIP that was
    /// never going to be written.
    public func writesArchive(pageCount: Int) -> Bool {
        switch format {
        case .jpeg, .png, .heic: pageCount > 1 && packaging == .zip
        case .pdf, .txt, .docx: false
        }
    }
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
    /// A watermark was asked for in a format with no picture of the page to
    /// draw it on — plain text or editable Word. Writing the file without it
    /// would be a silent false promise, so it is refused, as a password is.
    case watermarkNotSupported
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

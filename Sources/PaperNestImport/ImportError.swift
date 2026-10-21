import Foundation

/// Import failures, each carrying the file's display name so the UI can say
/// which file failed when several are imported at once.
public enum ImportError: Error, Equatable, Sendable {
    /// Not a PDF, JPEG or PNG (detected from the bytes, not the extension).
    case unsupportedType(filename: String)
    case unreadable(filename: String)
    /// Recognized type but the content cannot be decoded.
    case damaged(filename: String)
    case empty(filename: String)
    /// The PDF needs a password to open. Ask the user, then retry.
    case passwordRequired(filename: String)
    case incorrectPassword(filename: String)
    /// The PDF opened with the password but could not be stored in a form
    /// that opens without it. Nothing was imported.
    case protectedPDFUnsupported(filename: String)
    /// The PDF's author restricted copying or printing. Importing would let
    /// export remove those restrictions, so such files are declined.
    case restrictedPDF(filename: String)
    /// Dimensions beyond what the app can safely decode.
    case tooLarge(filename: String)

    public var filename: String {
        switch self {
        case .unsupportedType(let f), .unreadable(let f), .damaged(let f), .empty(let f), .passwordRequired(let f),
             .incorrectPassword(let f), .protectedPDFUnsupported(let f), .restrictedPDF(let f), .tooLarge(let f):
            f
        }
    }
}

import CoreGraphics
import Foundation
import PDFKit
import PaperNestCore

/// An author's limits, written back into a PDF that PaperNest has rebuilt.
///
/// A page that came from a PDF with copying or printing switched off keeps
/// that limit for as long as the original file is what leaves the app. The
/// moment a PDF has to be *rebuilt* — something was drawn on a page, some
/// pages were left out, the paper changed — the new file is PaperNest's own
/// and starts with no limits at all. Measured on a USCIS form: the same pages
/// copied into a fresh `PDFDocument` and written plainly came out unencrypted
/// with copying allowed. This puts the limits back.
///
/// The owner password is made up here, used once and never kept. Nobody can
/// lift the limits with it, PaperNest included — which is the position the
/// reader was in with the original.
struct AuthorProtection: Sendable {
    let permissions: DocumentPermissions
    /// 32 ASCII characters: the most a PDF owner password honours.
    let ownerPassword: String

    /// Nil for a document nobody restricted: such an export is written
    /// exactly as it always was.
    init?(_ permissions: DocumentPermissions) {
        guard permissions.isRestricted else { return nil }
        self.permissions = permissions
        ownerPassword = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    /// For `CGPDFContext`. `userPassword` is the one the person exporting
    /// asked for, if any. It opens the file as a reader, never as its owner:
    /// otherwise anyone could lift an author's limits by exporting with a
    /// password of their own.
    func apply(to info: inout [CFString: Any], userPassword: String?) {
        info[kCGPDFContextOwnerPassword] = ownerPassword
        info[kCGPDFContextAllowsCopying] = permissions.allowsCopying
        info[kCGPDFContextAllowsPrinting] = permissions.allowsPrinting
        if let userPassword { info[kCGPDFContextUserPassword] = userPassword }
    }

    /// For PDFKit's writer, which replaces the file the context wrote whenever
    /// untouched pages are copied in — and drops its encryption unless told.
    func writeOptions(userPassword: String?) -> [PDFDocumentWriteOption: Any] {
        // Reading aloud, filling in and commenting stay possible in whatever
        // opens the export; changing or reassembling the document does not.
        var allowed = PDFAccessPermissions.allowsContentAccessibility.rawValue
            | PDFAccessPermissions.allowsFormFieldEntry.rawValue
            | PDFAccessPermissions.allowsCommenting.rawValue
        if permissions.allowsCopying { allowed |= PDFAccessPermissions.allowsContentCopying.rawValue }
        if permissions.allowsPrinting {
            allowed |= PDFAccessPermissions.allowsLowQualityPrinting.rawValue
                | PDFAccessPermissions.allowsHighQualityPrinting.rawValue
        }
        var options: [PDFDocumentWriteOption: Any] = [
            .ownerPasswordOption: ownerPassword,
            .accessPermissionsOption: NSNumber(value: allowed),
        ]
        if let userPassword { options[.userPasswordOption] = userPassword }
        return options
    }

    /// Whether a written file is at least as closed as its sources were, read
    /// the way anyone else will read it: opened with nothing, or with the
    /// reader's password. The export is checked against this before it is
    /// handed over, so a writer that quietly drops the limits fails the
    /// export instead of shipping it.
    func holds(in url: URL, userPassword: String?) -> Bool {
        guard let document = CGPDFDocument(url as CFURL), document.isEncrypted else { return false }
        if !document.isUnlocked {
            guard let userPassword, document.unlockWithPassword(userPassword) else { return false }
        }
        if document.allowsCopying, !permissions.allowsCopying { return false }
        if document.allowsPrinting, !permissions.allowsPrinting { return false }
        return true
    }
}

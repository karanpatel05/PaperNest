import Foundation

/// What the author of a PDF allows to be done with it.
///
/// A PDF can be written so that it opens for anyone but may not be copied
/// from, or may not be printed: the author sets an owner password nobody is
/// given and switches the permission off. Government forms are the everyday
/// case — every USCIS form allows printing and filling and forbids copying.
///
/// PaperNest opens such a file and keeps to its limits. They are never stored
/// beside the document: they are read from the original itself, which is
/// kept byte for byte, so they cannot drift from the file and they follow its
/// pages into any document those pages are later merged into.
///
/// Only these two are tracked. They are the two a reader's actions can break:
/// taking the contents out, and putting them on paper.
public struct DocumentPermissions: Hashable, Sendable {
    /// Whether text and pictures may be taken out of the document.
    public var allowsCopying: Bool
    public var allowsPrinting: Bool

    public init(allowsCopying: Bool, allowsPrinting: Bool) {
        self.allowsCopying = allowsCopying
        self.allowsPrinting = allowsPrinting
    }

    /// Nothing switched off: every picture, every notebook and most PDFs.
    public static let unrestricted = DocumentPermissions(allowsCopying: true, allowsPrinting: true)

    /// What to assume when a document's limits could not be read: everything
    /// off. Not knowing is not permission.
    public static let unknown = DocumentPermissions(allowsCopying: false, allowsPrinting: false)

    public var isRestricted: Bool { !allowsCopying || !allowsPrinting }

    /// The limits of two sources taken together. Something is allowed only
    /// where both authors allow it.
    public func combined(with other: DocumentPermissions) -> DocumentPermissions {
        DocumentPermissions(allowsCopying: allowsCopying && other.allowsCopying,
                            allowsPrinting: allowsPrinting && other.allowsPrinting)
    }
}

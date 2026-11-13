import Foundation

/// A place on a page that leads somewhere: out to the web, or to another
/// page of the same document.
///
/// The box is normalized to the page's upright, uncropped source with a
/// top-left origin, like a page's text and its ink, so it stays on its words
/// through a crop or a rotation.
public struct PageLink: Hashable, Sendable {
    public enum Target: Hashable, Sendable {
        /// An address outside the document. Only kinds a reader would expect
        /// a document to open — see `PageLink.opens(_:)`.
        case url(URL)
        /// A page of *this* document, not an index into the file it came from.
        case page(PageID)
    }

    public var box: NormalizedRect
    public var target: Target

    public init(box: NormalizedRect, target: Target) {
        self.box = box
        self.target = target
    }

    /// Whether a link to `url` is one PaperNest will offer to open.
    ///
    /// A document is not a trusted source of instructions. A web page, an
    /// email address and a phone number are what a reader expects a link in
    /// a PDF to be; a `file:` path, an app's private scheme or a script is
    /// not, and is left as plain paper rather than made tappable.
    public static func opens(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto", "tel"].contains(scheme)
    }
}

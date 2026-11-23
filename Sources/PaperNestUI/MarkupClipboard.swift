import Observation
import PaperNestCore

/// What the lasso last copied or cut, ready to paste onto any page of any
/// document in the open library while the app runs.
///
/// Held in memory only, on purpose. The marks themselves are already stored
/// in the library; this is a note of which ones to lay down again, and a
/// table or file of it would be a second record of page content that could
/// drift from the first. A paste is checked by the store like anything from
/// outside the app, so a picture whose bytes have gone since is refused rather
/// than drawn as nothing.
///
/// Other apps do not see it: copying marks onto the system clipboard as a
/// picture is not part of this.
@MainActor @Observable
final class MarkupClipboard {
    struct Content {
        /// The marks as they were when copied, in the space of their page.
        let objects: [PageObject]
        /// The page they were copied from, laid out as it was then, so a copy
        /// lands where it sat as the reader saw it.
        let geometry: PageGeometry
        let pageID: PageID
    }

    static let shared = MarkupClipboard()

    private(set) var content: Content?

    var hasContent: Bool { content != nil }

    /// Keeps what the lasso holds for pasting. Only marks painted on a page
    /// are kept; a selection with none leaves the clipboard as it was.
    func copy(_ objects: [PageObject], from page: Page) {
        let painted = objects.filter { object in
            switch object.payload {
            case .ink, .text, .image: return object.pageID == page.id
            case .comment: return false
            }
        }
        guard !painted.isEmpty else { return }
        content = Content(objects: painted, geometry: page.geometry, pageID: page.id)
    }

    func clear() { content = nil }
}

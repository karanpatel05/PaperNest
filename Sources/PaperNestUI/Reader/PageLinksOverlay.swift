import PaperNestCore
import PaperNestRender
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// The links a PDF page carries, made tappable over it.
///
/// A link to another page turns to that page. A link out of the document is
/// **asked about first, with its whole address shown**: the words under a
/// link say whatever their author liked, and the address is the only honest
/// account of where it goes.
struct PageLinksOverlay: View {
    let model: DocumentModel
    let page: Page
    /// Source space to this view's space, as every layer over the page gets.
    let sourceToView: CGAffineTransform
    /// Turns to another page of the document.
    let showPage: (PageID) -> Void

    @Environment(LibrarySession.self) private var session
    @Environment(\.openURL) private var openURL
    @State private var links: [PageLink] = []
    @State private var asked: URL?

    /// Everything a page's links depend on: what it shows, what a crop
    /// hides, and which pages there are to lead to.
    private struct Stamp: Hashable {
        let id: PageID
        let content: PageContent
        let crop: NormalizedRect
        let pages: [PageID]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                let rect = link.box.denormalized(in: page.sourceSize).applying(sourceToView)
                Button { follow(link) } label: { Color.clear.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                    .offset(x: rect.minX, y: rect.minY)
                    .accessibilityLabel(describe(link))
                    .accessibilityAddTraits(.isLink)
                    .accessibilityIdentifier("page-link")
                    .help(describe(link))
                    #if os(macOS)
                    .onHover { inside in
                        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                    #endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: Stamp(id: page.id, content: page.content, crop: page.transform.crop, pages: model.pages.map(\.id))) {
            guard let renderer = session.environment?.renderer else { return }
            let found = (try? await renderer.links(on: page, in: model.pages)) ?? []
            if !Task.isCancelled { links = found }
        }
        .alert(L10n.linkOpenTitle, isPresented: Binding(get: { asked != nil }, set: { if !$0 { asked = nil } }),
               presenting: asked) { url in
            Button(L10n.linkOpen) { openURL(url) }
            Button(L10n.linkCopy) { Clipboard.write(text: url.absoluteString) }
            Button(L10n.cancel, role: .cancel) {}
        } message: { url in
            Text(verbatim: url.absoluteString)
        }
    }

    private func follow(_ link: PageLink) {
        switch link.target {
        case .page(let id): showPage(id)
        case .url(let url): asked = url
        }
    }

    private func describe(_ link: PageLink) -> String {
        switch link.target {
        case .url(let url):
            return L10n.linkToAddress(url.absoluteString)
        case .page(let id):
            let number = (model.pages.firstIndex { $0.id == id } ?? 0) + 1
            return L10n.linkToPage(number)
        }
    }
}

/// What someone typed when asked which page to go to.
enum PageNumberEntry {
    /// The page to show, counted from zero, or nil when what was typed is
    /// not a number. A number past either end means that end: asking for
    /// page 500 of a 12-page document is asking for the last page.
    static func pageIndex(for text: String, pageCount: Int) -> Int? {
        guard pageCount > 0,
              let number = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return min(max(number, 1), pageCount) - 1
    }
}

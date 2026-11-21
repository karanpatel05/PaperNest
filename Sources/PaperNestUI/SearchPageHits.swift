import PaperNestCore
import PaperNestStore
import SwiftUI

/// While searching, the pages that matched: which document, which page, and
/// the words around each match, the matching words in bold. A tap opens the
/// document at that page.
///
/// Under the documents rather than instead of them: the list above says which
/// documents match, this says where. A title match is in the list above and
/// has no page, so it is not repeated here.
struct SearchPageHitsList: View {
    let hits: [LibraryModel.PageHit]
    /// A picture of a hit's page, at the given size in pixels. Shown for
    /// handwriting, so the writing can be seen beside the words read off it.
    var preview: ((LibraryModel.PageHit, CGFloat) async -> CGImage?)?
    let open: (LibraryModel.PageHit) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.searchInPages)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                    if index > 0 { Divider().padding(.leading, 50) }
                    Button { open(hit) } label: { row(hit) }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityHint(L10n.searchHitHint)
                        .accessibilityIdentifier("search-hit-\(index)")
                        // The page it opens, for tests and for anyone checking.
                        .accessibilityValue(String(hit.pageNumber))
                }
            }
            .modifier(PremiumCard())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search-page-hits")
    }

    private func row(_ hit: LibraryModel.PageHit) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: Self.symbol(for: hit.source))
                .font(.body)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.searchHitPlace(hit.itemName, hit.pageNumber))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Self.attributed(hit.snippet))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Text(Self.sourceName(hit.source, mayBeMisread: hit.mayBeMisread))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if hit.source == .handwritten, let preview {
                HitPagePreview(hit: hit, load: preview)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(14)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    /// The snippet as text, its matches emphasised. Built from the runs, so
    /// what a page says is never read as markdown or as a localization key.
    static func attributed(_ snippet: SearchSnippet) -> AttributedString {
        var result = AttributedString()
        for run in snippet.runs {
            var part = AttributedString(run.text)
            if run.isMatch {
                part.inlinePresentationIntent = .stronglyEmphasized
                part.foregroundColor = Color.primary
            }
            result += part
        }
        return result
    }

    static func symbol(for source: SearchHit.Source) -> String {
        switch source {
        case .recognized: "text.viewfinder"
        case .pageText: "doc.text"
        case .typed: "character.cursor.ibeam"
        case .handwritten: "pencil.and.scribble"
        case .title: "textformat"
        }
    }

    static func sourceName(_ source: SearchHit.Source, mayBeMisread: Bool = false) -> String {
        switch source {
        case .recognized: L10n.searchSourceRecognized
        case .pageText: L10n.searchSourcePageText
        case .typed: L10n.searchSourceTyped
        // Vision's confidence comes in steps, so it is said in words, not as
        // a percentage it does not have.
        case .handwritten: mayBeMisread ? L10n.searchSourceHandwrittenUnsure : L10n.searchSourceHandwritten
        case .title: L10n.searchSourceTitle
        }
    }
}

/// A small picture of the page a handwriting hit is on. Silent to VoiceOver:
/// the row already says which page it is.
private struct HitPagePreview: View {
    let hit: LibraryModel.PageHit
    let load: (LibraryModel.PageHit, CGFloat) async -> CGImage?
    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?
    private let width: CGFloat = 44

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: displayScale).resizable().scaledToFit()
            } else {
                Color.secondary.opacity(0.12)
            }
        }
        .frame(width: width, height: width * 1.3)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.separator) }
        .accessibilityHidden(true)
        .task(id: hit.pageID) { image = await load(hit, width * 1.3 * displayScale) }
    }
}

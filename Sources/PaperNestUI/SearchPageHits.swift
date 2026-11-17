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
                Text(Self.sourceName(hit.source))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
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
        case .title: "textformat"
        }
    }

    static func sourceName(_ source: SearchHit.Source) -> String {
        switch source {
        case .recognized: L10n.searchSourceRecognized
        case .pageText: L10n.searchSourcePageText
        case .typed: L10n.searchSourceTyped
        case .title: L10n.searchSourceTitle
        }
    }
}

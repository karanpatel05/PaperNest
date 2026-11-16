import PaperNestCore
import PaperNestStore
import SwiftUI

/// The words Home puts beside a recent document. The size is the store's:
/// a file's own bytes, or the originals a document's pages are made of. A
/// notebook of drawn pages has no stored original, so it shows its page count.
@MainActor
enum HomeRecentText {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    static func modified(_ date: Date) -> String { formatter.string(from: date) }

    static func size(_ bytes: Int64?) -> String? {
        bytes.flatMap { $0 > 0 ? FileKind.size($0) : nil }
    }

    static func detail(_ summary: LibraryStore.ItemSummary, bytes: Int64?) -> String {
        modified(summary.item.modifiedAt) + " · " + (size(bytes) ?? L10n.pageCount(summary.pageCount))
    }

    /// The same words the library's own cells use: a file by its size, a
    /// document by its pages.
    static func accessibilityLabel(_ summary: LibraryStore.ItemSummary) -> String {
        L10n.itemAccessibilityLabel(name: summary.item.name,
            pages: summary.file.map { FileKind.size($0.byteCount) } ?? L10n.pageCount(summary.pageCount))
    }
}

/// A document's first page, or the symbol for what it is when it has none.
struct HomeThumbnail: View {
    let summary: LibraryStore.ItemSummary
    var pixelSize: CGFloat = 180

    var body: some View {
        Group {
            if let page = summary.coverPage {
                PageImageView(page: page, pixelSize: pixelSize)
            } else {
                Image(systemName: summary.file.map { FileKind.symbol(for: $0.uti) }
                      ?? (summary.item.kind == .notebook ? "pencil.tip" : "doc.text"))
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Recent documents as rounded rows: the phone's layout, and the wide
/// layout's at accessibility text sizes.
struct HomeRecentList<Actions: View>: View {
    let items: [LibraryStore.ItemSummary]
    let sizes: [ItemID: Int64]
    let open: (LibraryStore.ItemSummary) -> Void
    @ViewBuilder let actions: (LibraryStore.ItemSummary) -> Actions

    var body: some View {
        VStack(spacing: 4) {
            ForEach(items) { summary in
                HStack(spacing: 0) {
                    Button { open(summary) } label: { row(summary) }
                        .buttonStyle(.plain)
                    Menu { actions(summary) } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44)
                    }
                    .menuStyle(.borderlessButton)
                    .foregroundStyle(Theme.navy)
                    .accessibilityLabel(L10n.more)
                }
                .padding(4)
                .background(Theme.lavender.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border, lineWidth: 1) }
                .contextMenu { actions(summary) }
            }
        }
    }

    private func row(_ summary: LibraryStore.ItemSummary) -> some View {
        HStack(spacing: 12) {
            HomeThumbnail(summary: summary)
                .frame(width: 36, height: 44)
                .background(Theme.lavender, in: RoundedRectangle(cornerRadius: 8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.item.name).font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.navy).lineLimit(2)
                Text(HomeRecentText.modified(summary.item.modifiedAt)).font(.caption)
                    .foregroundStyle(Theme.secondaryText).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if summary.item.isFavorite {
                Image(systemName: "star.fill").font(.caption).foregroundStyle(Theme.accent)
                    .accessibilityLabel(L10n.favorites)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HomeRecentText.accessibilityLabel(summary))
        .accessibilityValue(HomeRecentText.modified(summary.item.modifiedAt))
    }
}

/// Responsive preview cards for the spacious Mac and iPad Home.
struct HomeRecentCards<Actions: View>: View {
    let items: [LibraryStore.ItemSummary]
    let open: (LibraryStore.ItemSummary) -> Void
    @ViewBuilder let actions: (LibraryStore.ItemSummary) -> Actions

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 360), spacing: 16)], spacing: 16) {
            ForEach(items) { summary in
                VStack(alignment: .leading, spacing: 0) {
                    Button { open(summary) } label: { card(summary) }
                        .buttonStyle(.plain)
                    HStack(spacing: 4) {
                        Text(HomeRecentText.modified(summary.item.modifiedAt))
                            .font(.caption).foregroundStyle(Theme.secondaryText)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        Menu { actions(summary) } label: {
                            Image(systemName: "ellipsis").frame(width: 44, height: 44)
                        }
                        .menuStyle(.borderlessButton).fixedSize()
                        .accessibilityLabel(L10n.more + ", " + summary.item.name)
                    }.padding(.horizontal, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.lavender.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border, lineWidth: 1) }
                .contextMenu { actions(summary) }
            }
        }
    }

    private func card(_ summary: LibraryStore.ItemSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                HomeThumbnail(summary: summary, pixelSize: 180)
                    .frame(width: 60, height: 78)
                    .shadow(color: Theme.paperShadow.opacity(0.5), radius: 3, y: 2)
                    .frame(maxWidth: .infinity)
                if summary.item.isFavorite {
                    Image(systemName: "star.fill").font(.caption)
                        .foregroundStyle(Theme.accent)
                }
            }
            .frame(height: 84)
            Text(summary.item.name).font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.navy).lineLimit(2).multilineTextAlignment(.leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HomeRecentText.accessibilityLabel(summary))
        .accessibilityValue(summary.item.isFavorite
            ? HomeRecentText.modified(summary.item.modifiedAt) + ", " + L10n.favorites
            : HomeRecentText.modified(summary.item.modifiedAt))
    }
}

#if os(macOS)
/// One line of the Mac's recent-documents table.
struct HomeRecentRow: Identifiable, Sendable {
    let summary: LibraryStore.ItemSummary
    /// Zero when nothing is stored for it, which sorts below everything that has a size.
    let bytes: Int64
    var id: ItemID { summary.id }
    var name: String { summary.item.name }
    var modified: Date { summary.item.modifiedAt }
}

/// Recent documents as a sortable table: the Mac layout.
struct HomeRecentTable<Actions: View>: View {
    let items: [LibraryStore.ItemSummary]
    let sizes: [ItemID: Int64]
    let open: (LibraryStore.ItemSummary) -> Void
    @ViewBuilder let actions: (LibraryStore.ItemSummary) -> Actions
    @State private var selection: Set<ItemID> = []
    @State private var order = [KeyPathComparator(\HomeRecentRow.modified, order: .reverse)]

    private var rows: [HomeRecentRow] {
        items.map { HomeRecentRow(summary: $0, bytes: sizes[$0.id] ?? 0) }.sorted(using: order)
    }

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $order) {
            TableColumn(L10n.sortName, value: \.name) { row in
                HStack(spacing: 8) {
                    HomeThumbnail(summary: row.summary, pixelSize: 64)
                        .frame(width: 18, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    Text(row.name).lineLimit(1)
                    if row.summary.item.isFavorite {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(Theme.accent)
                            .accessibilityLabel(L10n.favorites)
                    }
                }
            }
            TableColumn(L10n.fileModified, value: \.modified) { row in
                Text(HomeRecentText.modified(row.modified)).foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 180)
            TableColumn(L10n.fileSize, value: \.bytes) { row in
                Text(verbatim: HomeRecentText.size(row.bytes) ?? "—").foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 90)
        }
        .contextMenu(forSelectionType: ItemID.self) { ids in
            if ids.count == 1, let summary = items.first(where: { ids.contains($0.id) }) {
                actions(summary)
            }
        } primaryAction: { ids in
            if let summary = items.first(where: { ids.contains($0.id) }) { open(summary) }
        }
        .scrollDisabled(true)
        // The table sits inside Home's own scroll view, so it is as tall as
        // its rows rather than a second scrolling region. Measured on macOS
        // 26: 30 points a row with this thumbnail, 26 for the header, and the
        // table's own insets.
        .frame(height: CGFloat(rows.count) * 30 + 42)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border, lineWidth: 1) }
    }
}
#endif

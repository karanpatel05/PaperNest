import PaperNestCore
import SwiftUI

/// Folders have no colour of their own, so a card takes one by position.
enum FolderTint {
    static func color(at index: Int) -> Color {
        [Theme.accent, .blue, .green, .orange][index % 4]
    }
}

/// A folder as a card: its name and how many items it really holds.
struct FolderCard: View {
    let folder: Folder
    let count: Int
    let tint: Color
    let open: () -> Void
    let rename: () -> Void
    let delete: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill").font(.title).foregroundStyle(tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name).font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.navy).lineLimit(2).multilineTextAlignment(.leading)
                    Text(L10n.itemCount(count)).font(.caption).foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay { RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border, lineWidth: 1) }
            .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
        .buttonStyle(PremiumButtonStyle())
        .contextMenu {
            Button(L10n.open, action: open)
            Button(L10n.rename, action: rename)
            Button(L10n.deleteFolder, role: .destructive, action: delete)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(folder.name)
        .accessibilityValue(L10n.itemCount(count))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("folder-card")
    }
}

/// Every folder, on its own screen. The wide layouts reach it from the
/// sidebar's Folders row and from Home's See All.
struct FoldersView: View {
    @Bindable var model: LibraryModel
    let open: (Folder) -> Void
    let newFolder: () -> Void
    let rename: (Folder) -> Void
    let delete: (Folder) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ViewThatFits(in: .horizontal) {
                    HStack { title; Spacer(minLength: 12); create }
                    VStack(alignment: .leading, spacing: 8) { title; create }
                }
                if model.folders.isEmpty {
                    ContentUnavailableView(L10n.foldersEmpty, systemImage: "folder",
                                           description: Text(L10n.foldersEmptyDetail))
                        .frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 260 : 190),
                                                 spacing: 14)], spacing: 14) {
                        ForEach(Array(model.folders.enumerated()), id: \.element.id) { index, folder in
                            FolderCard(folder: folder, count: model.counts.folders[folder.id, default: 0],
                                       tint: FolderTint.color(at: index),
                                       open: { open(folder) }, rename: { rename(folder) }, delete: { delete(folder) })
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1400, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(Theme.homeBackground)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var title: some View {
        Text(L10n.folders).font(.largeTitle.bold()).foregroundStyle(Theme.navy)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("folders-title")
    }

    private var create: some View {
        Button(action: newFolder) {
            Label(L10n.newFolder, systemImage: "folder.badge.plus").frame(minHeight: 44)
        }
        .accessibilityIdentifier("folders-new")
    }
}

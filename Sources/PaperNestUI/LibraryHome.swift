import PaperNestCore
import PaperNestStore
import SwiftUI

/// Home. One set of quick actions, the documents touched most recently and,
/// on the wide layouts, the folders. Every count and row comes from the
/// library store.
///
/// The phone keeps it short — greeting, three actions, five documents —
/// because Scan and Files are one tap away in the bar underneath. iPad and
/// Mac have the room for a banner, thumbnails or a table, and folder cards.
struct DashboardView: View {
    @Bindable var model: LibraryModel
    var compact: Bool
    var openFile: (LibraryStore.ItemSummary) -> Void
    var showLibrary: () -> Void
    var showFolders: () -> Void
    var openFolder: (Folder) -> Void
    var newFolder: () -> Void
    var renameFolder: (Folder) -> Void
    var deleteFolder: (Folder) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Matches the `.title2` the name beside it is set in, and grows with it.
    @ScaledMetric(relativeTo: .title2) private var headerMarkSize: CGFloat = 29
    @State private var showProfile = false
    @State private var creatingNotebook = false
    @State private var createdItemID: ItemID?
    @State private var renaming: LibraryStore.ItemSummary?
    @State private var renameText = ""
    @State private var exporting: LibraryStore.ItemSummary?

    /// The phone shows five; the wide layouts have room for a few more.
    private var recent: [LibraryStore.ItemSummary] {
        Array(model.dashboardItems.prefix(compact ? 5 : LibraryModel.homeRecentLimit))
    }

    /// How many folder cards Home shows before See All takes over.
    private static let folderLimit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 18 : 22) {
            header
            if compact { greeting } else { HomeBanner() }
            HomeQuickActionsRow(actions: quickActions, tinted: compact)
            recentSection
            if !compact && !model.folders.isEmpty { foldersSection }
        }
        .foregroundStyle(Theme.navy)
        .sheet(isPresented: $creatingNotebook, onDismiss: openCreatedNotebook) {
            NotebookCreationSheet(model: model) { createdItemID = $0 }
        }
        .sheet(item: $exporting) { ExportLoader(itemID: $0.id, currentPageID: nil) }
        .alert(L10n.renameTitle, isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), presenting: renaming) { item in
            TextField(L10n.renamePlaceholder, text: $renameText)
            Button(L10n.cancel, role: .cancel) { renaming = nil }
            Button(L10n.ok) {
                let name = renameText
                Task { await model.rename(item.id, to: name) }
                renaming = nil
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            Task { await model.importFiles(files, chooseLocation: true) }
            return true
        }
        #if os(macOS)
        .onPasteCommand(of: Clipboard.pasteableTypes) { _ in
            guard let content = Clipboard.read() else { return }
            switch content {
            case .files(let urls): Task { await model.importFiles(urls, chooseLocation: true) }
            case .image(let data):
                Task { await model.importImages([data], name: L10n.pastedImageName(Date().formatted()), chooseLocation: true) }
            }
        }
        #endif
    }

    // MARK: - Header

    private var header: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    headerTitle
                    HStack(spacing: 20) { headerControls }
                }
            } else {
                HStack(spacing: 10) {
                    headerTitle
                    Spacer(minLength: 8)
                    headerControls
                }
            }
        }
    }

    /// The phone has no sidebar to carry the brand, so Home does. On the wide
    /// layouts the sidebar has it, and this is the screen's own title.
    @ViewBuilder private var headerTitle: some View {
        if compact {
            HStack(spacing: 10) {
                if !dynamicTypeSize.isAccessibilitySize {
                    BrandMark.image(size: headerMarkSize).foregroundStyle(Theme.accent)
                }
                Text(verbatim: Brand.displayName).font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("home-brand")
            }
        } else {
            Text(L10n.homeTitle).font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("home-title")
        }
    }

    @ViewBuilder private var headerControls: some View {
        if compact {
            // Draws nothing in a build without iCloud. The wide layouts show
            // sync in the sidebar instead.
            CloudSyncStatusView(session: model.session, style: .compact)
        }
        Button { showProfile = true } label: {
            Image(systemName: "person.crop.circle")
                .font(.title)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.profile)
        .accessibilityIdentifier("home-profile")
        #if os(macOS)
        .help(L10n.profile)
        #endif
        .sheet(isPresented: $showProfile) { ProfileView(session: model.session, store: .shared) }
    }

    private var greeting: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 4) {
                Text(HomeGreeting.text(at: context.date)).font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("home-greeting")
                Text(L10n.homeSubtitle).font(.subheadline).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Quick actions

    /// New Note, Import File and New Folder everywhere. iPad adds Scan, which
    /// its sidebar does not have; the phone has Scan in its bottom bar; the
    /// Mac has no camera to scan with.
    private var quickActions: [HomeQuickAction] {
        var actions: [HomeQuickAction] = []
        #if os(iOS)
        if !compact {
            actions.append(HomeQuickAction(id: "home-scan", title: L10n.scan, symbol: "doc.viewfinder",
                                           isEnabled: DocumentCameraView.isSupported,
                                           hint: DocumentCameraView.isSupported ? "" : L10n.scanUnsupported) {
                model.isShowingScanner = true
            })
        }
        #endif
        actions.append(HomeQuickAction(id: "home-new-note", title: L10n.homeNewNote, symbol: "pencil.line") {
            creatingNotebook = true
        })
        actions.append(HomeQuickAction(id: "home-import", title: L10n.homeImportFile, symbol: "square.and.arrow.down") {
            model.isShowingFileImporter = true
        })
        actions.append(HomeQuickAction(id: "home-new-folder", title: L10n.newFolder, symbol: "folder.badge.plus",
                                       action: newFolder))
        return actions
    }

    private func openCreatedNotebook() {
        guard let id = createdItemID else { return }
        createdItemID = nil
        model.open(id)
    }

    // MARK: - Recent documents

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(L10n.homeRecentDocuments, identifier: "home-recent-heading") {
                Button {
                    model.contentKind = .all
                    showLibrary()
                } label: { seeAllLabel }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.homeSeeAll + ", " + L10n.homeRecentDocuments)
                    .accessibilityIdentifier("home-see-all")
            }
            if recent.isEmpty {
                ContentUnavailableView(L10n.premiumEmpty, systemImage: "doc",
                                       description: Text(L10n.premiumEmptyDetail))
                    .frame(maxWidth: .infinity)
            } else {
                // A container of its own, so the identifier names the list
                // and each row keeps its own label for VoiceOver and tests.
                recentContent
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("home-recent")
            }
        }
    }

    @ViewBuilder private var recentContent: some View {
        #if os(macOS)
        HomeRecentTable(items: recent, sizes: model.dashboardSizes, open: open, actions: actions)
        #else
        if compact || dynamicTypeSize.isAccessibilitySize {
            HomeRecentList(items: recent, sizes: model.dashboardSizes, open: open, actions: actions)
        } else {
            HomeRecentCards(items: recent, open: open, actions: actions)
        }
        #endif
    }

    // MARK: - Folders

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(L10n.folders, identifier: "home-folders-heading") {
                Button(action: showFolders) { seeAllLabel }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.homeSeeAll + ", " + L10n.folders)
                    .accessibilityIdentifier("home-folders-all")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 260 : 170), spacing: 14)],
                      spacing: 14) {
                ForEach(Array(model.folders.prefix(Self.folderLimit).enumerated()), id: \.element.id) { index, folder in
                    FolderCard(folder: folder, count: model.counts.folders[folder.id, default: 0],
                               tint: FolderTint.color(at: index),
                               open: { openFolder(folder) }, rename: { renameFolder(folder) },
                               delete: { deleteFolder(folder) })
                }
            }
        }
    }

    // MARK: - Pieces

    private func sectionHeader<Trailing: View>(_ title: String, identifier: String,
                                               @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(identifier)
            Spacer(minLength: 8)
            trailing().font(.subheadline).frame(minHeight: 44)
        }
    }

    private var seeAllLabel: some View {
        HStack(spacing: 4) {
            Text(L10n.homeSeeAll)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).accessibilityHidden(true)
        }
        .foregroundStyle(Theme.accent)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func actions(_ summary: LibraryStore.ItemSummary) -> some View {
        Button(L10n.open) { open(summary) }
        Button(L10n.rename) { renameText = summary.item.name; renaming = summary }
        Button(summary.item.isFavorite ? L10n.removeFavorite : L10n.addFavorite) {
            Task { await model.setFavorite(summary.id, !summary.item.isFavorite) }
        }
        Menu(L10n.moveToFolder) {
            Button(L10n.noFolder) { Task { await model.move([summary.id], to: nil) } }
            ForEach(model.folders) { folder in
                Button(folder.name) { Task { await model.move([summary.id], to: folder.id) } }
            }
        }
        if summary.pageCount > 0 { Button(L10n.export) { exporting = summary } }
        Button(L10n.delete, role: .destructive) { Task { await model.moveToRecentlyDeleted([summary.id]) } }
    }

    private func open(_ summary: LibraryStore.ItemSummary) {
        if summary.file != nil {
            openFile(summary)
        } else {
            if compact {
                model.open(summary.id)
            } else {
                // Home already lives in the detail NavigationStack. Changing
                // split selection here rebuilds its root and discards the push.
                model.path = [summary.id]
            }
        }
    }
}

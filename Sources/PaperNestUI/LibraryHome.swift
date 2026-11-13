import PaperNestCore
import PaperNestStore
import SwiftUI

/// Content-first dashboard. All counts and rows come from the library store.
struct DashboardView: View {
    @Bindable var model: LibraryModel
    var compact: Bool
    var openFile: (LibraryStore.ItemSummary) -> Void
    var showLibrary: () -> Void
    var newFolder: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Matches the `.title` the name beside it is set in, and grows with it.
    @ScaledMetric(relativeTo: .title) private var headerMarkSize: CGFloat = 29
    @State private var filter = DashboardFilter.recent
    @State private var showProfile = false
    @State private var selectedTool: ToolsSheet.Tool?
    @State private var renaming: LibraryStore.ItemSummary?
    @State private var renameText = ""
    @State private var exporting: LibraryStore.ItemSummary?

    private var recent: [LibraryStore.ItemSummary] {
        Array(model.dashboardItems.filter { filter != .favorites || $0.item.isFavorite }.prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            search
            captureActions
            tools
            if !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ForEach(model.folders.filter { $0.name.localizedStandardContains(model.searchText) }) { folder in
                    Button {
                        model.searchText = ""
                        model.contentKind = .all
                        showLibrary()
                        model.sidebarSelection = .folder(folder.id)
                    } label: { Label(folder.name, systemImage: "folder") }
                }
            }
            // My Space reads as the next thing down the page rather than a
            // sidebar off to the right. It used to sit in a fixed 240-point
            // column beside Recent on iPad and Mac, which squeezed its folder
            // grid into one narrow strip while Recent had the rest of a very
            // wide window. Stacked, the grid flows across the full width and
            // both sections get the room they need. The phone already did
            // this; now every size does.
            recentSection
            space
        }
        .foregroundStyle(Theme.primaryText)
        .sheet(item: $selectedTool) { ToolsSheet(model: model, initialTool: $0) }
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

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack { filters; Spacer(); seeAll }
                VStack(alignment: .leading) { filters; seeAll }
            }
            if recent.isEmpty {
                ContentUnavailableView(L10n.premiumEmpty, systemImage: "doc",
                                       description: Text(L10n.premiumEmptyDetail))
            } else {
                VStack(spacing: 0) {
                    ForEach(recent) { summary in
                        HStack(spacing: 0) {
                            Button { open(summary) } label: {
                                recentRow(summary)
                            }.buttonStyle(.plain)
                            Menu { actions(summary) } label: {
                                Image(systemName: "ellipsis").frame(width: 44, height: 44)
                            }.menuStyle(.borderlessButton)
                                .accessibilityLabel(L10n.more)
                        }
                        .contextMenu { actions(summary) }
                        if summary.id != recent.last?.id { Divider().padding(.leading, 68) }
                    }
                }.padding(4).modifier(PremiumCard())
                    .accessibilityIdentifier("home-recent")
            }
        }
    }


    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if dynamicTypeSize.isAccessibilitySize {
                Text(verbatim: Brand.displayName).font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 20) { headerControls }
            } else {
                HStack(spacing: 10) {
                    BrandMark.image(size: headerMarkSize).foregroundStyle(Theme.accent)
                    Text(verbatim: Brand.displayName).font(.title2.bold())
                    Spacer(minLength: 8)
                    headerControls
                }
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: 6) {
                    Text(greeting(at: context.date)).font(compact ? .title3.bold() : .title.bold())
                    Text(L10n.premiumWelcome).font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    @ViewBuilder private var headerControls: some View {
        // Draws nothing in a build without iCloud.
        CloudSyncStatusView(session: model.session, style: compact ? .compact : .labeled)
        Button { showProfile = true } label: {
            Label(L10n.profile, systemImage: "person.crop.circle")
                .labelStyle(.iconOnly)
                .font(.title)
                .foregroundStyle(Theme.primaryText)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
        }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.profile)
            .accessibilityIdentifier("home-profile")
            .sheet(isPresented: $showProfile) { ProfileView(session: model.session, store: .shared) }

    }

    private var search: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(L10n.searchPrompt, text: $model.searchText)
                .textFieldStyle(.plain).onSubmit { model.contentKind = .all; showLibrary() }
                #if os(iOS)
                .submitLabel(.search)
                #endif
                .accessibilityIdentifier("home-search")
        }.padding(.horizontal, 12).frame(minHeight: 44).modifier(PremiumCard())
    }

    private var toolColumns: [GridItem] {
        compact
            ? [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)]
            : [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 220 : 130), spacing: 12, alignment: .top)]
    }

    private var captureActions: some View {
        LazyVGrid(columns: toolColumns, spacing: 12) {
            #if os(iOS)
            Button { model.isShowingScanner = true } label: {
                homeActionLabel(L10n.scan, symbol: "doc.viewfinder")
            }.disabled(!DocumentCameraView.isSupported)
                .accessibilityHint(DocumentCameraView.isSupported ? "" : L10n.scanUnsupported)
                .accessibilityIdentifier("home-scan")
            #endif
            Button { model.isShowingFileImporter = true } label: {
                homeActionLabel(L10n.importFiles, symbol: "square.and.arrow.down")
            }.accessibilityIdentifier("home-import")
        }.buttonStyle(PremiumButtonStyle())
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.toolsTitle).font(.subheadline.bold()).accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("home-tools-heading")
                Spacer(minLength: 8)
                Button(L10n.homeSeeAll) { model.isShowingTools = true }
                    .font(.subheadline).frame(minHeight: 44)
                    .accessibilityLabel(L10n.homeSeeAll + ", " + L10n.toolsTitle)
                    .accessibilityIdentifier("home-tools-all")
            }
            LazyVGrid(columns: toolColumns, spacing: 12) {
                ForEach(ToolsSheet.Tool.allCases) { tool in
                    Button { selectedTool = tool } label: {
                        homeActionLabel(tool.compactTitle, symbol: tool.systemImage)
                    }.buttonStyle(PremiumButtonStyle())
                        .accessibilityLabel(tool.title)
                        .accessibilityIdentifier("home-tool-\(tool.rawValue)")
                        .accessibilityValue(tool.prompt)
                }
            }
        }
    }

    private func homeActionLabel(_ title: String, symbol: String) -> some View {
        Group {
            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 10) {
                    homeActionIcon(symbol)
                    Text(title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    homeActionIcon(symbol)
                    Text(title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(Theme.primaryText).multilineTextAlignment(.leading)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 76 : 44)
        .modifier(PremiumCard()).contentShape(RoundedRectangle(cornerRadius: Theme.radius))
        .accessibilityElement(children: .ignore).accessibilityLabel(title)
    }

    private func homeActionIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).resizable().scaledToFit().frame(width: 22, height: 22)
            .foregroundStyle(Theme.accent).frame(width: 26, height: 28)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var filters: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) { filterChoices }
        } else {
            HStack(spacing: 4) { filterChoices }
        }
    }

    @ViewBuilder private var filterChoices: some View {
        filterButton(.recent, title: L10n.homeRecent)
        filterButton(.favorites, title: L10n.favorites)
    }

    private func filterButton(_ value: DashboardFilter, title: String) -> some View {
        Button { filter = value } label: {
            Text(title).font(.subheadline.weight(filter == value ? .semibold : .regular))
                .padding(.horizontal, 12).frame(minHeight: 44)
                .background(filter == value ? Theme.selection : .clear, in: Capsule())
        }.buttonStyle(.plain)
            .accessibilityIdentifier("home-filter-\(value.rawValue)")
            .accessibilityValue(filter == value ? L10n.selectionOn : L10n.selectionOff)
    }

    private var seeAll: some View {
        Button(L10n.homeSeeAll) {
            model.contentKind = .all
            showLibrary()
            if filter == .favorites { model.sidebarSelection = .favorites }
        }.font(.subheadline).frame(minHeight: 44).accessibilityIdentifier("home-see-all")
    }

    /// How wide a My Space card is allowed to get.
    ///
    /// 95 points was sized for the narrow column this section used to sit in
    /// on iPad and Mac. Stacked under Recent the row is several times wider,
    /// and at the old minimum the grid answered by making the cards *smaller*
    /// still — enough that "Documents" broke across two lines. A regular-width
    /// window gets cards with room for their own labels.
    private var spaceCardMinimum: CGFloat {
        if dynamicTypeSize.isAccessibilitySize { return 220 }
        return compact ? 95 : 150
    }

    private var space: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.studioMySpace).font(.subheadline.bold())
                Spacer()
                Button(action: newFolder) { Image(systemName: "folder.badge.plus").frame(width: 44, height: 44) }
                    .accessibilityLabel(L10n.newFolder).accessibilityIdentifier("home-new-folder")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: spaceCardMinimum))], spacing: 12) {
                collection(L10n.premiumNotes, count: model.dashboardItems.filter { $0.item.kind == .notebook }.count, color: Theme.accent) {
                    model.contentKind = .notes; showLibrary()
                }
                collection(L10n.toolsDocuments, count: model.dashboardItems.filter { $0.item.kind != .notebook }.count, color: .blue) {
                    model.contentKind = .documents; showLibrary()
                }
                ForEach(Array(model.folders.prefix(2).enumerated()), id: \.element.id) { index, folder in
                    collection(folder.name, count: model.counts.folders[folder.id, default: 0], color: index == 0 ? .orange : .green) {
                        model.contentKind = .all
                        showLibrary()
                        model.sidebarSelection = .folder(folder.id)
                    }
                }
            }
        }
    }

    private func collection(_ title: String, count: Int, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: "folder").font(.title2).foregroundStyle(color)
                Text(title).font(.subheadline.bold()).lineLimit(2)
                Text(L10n.itemCount(count)).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 70)
                .padding(10).background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radius))
        }.buttonStyle(PremiumButtonStyle())
    }

    private func recentRow(_ summary: LibraryStore.ItemSummary) -> some View {
        HStack(spacing: 12) {
            Group {
                if let page = summary.coverPage {
                    PageImageView(page: page, pixelSize: 180)
                } else {
                    Image(systemName: summary.file.map { FileKind.symbol(for: $0.uti) } ?? "doc.text")
                        .font(.title2).foregroundStyle(Theme.accent)
                }
            }.frame(width: 34, height: 42)
                .background(Theme.preview, in: RoundedRectangle(cornerRadius: 6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.item.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(summary.item.modifiedAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if summary.item.isFavorite {
                Image(systemName: "star.fill").font(.caption).foregroundStyle(Theme.accent)
                    .accessibilityLabel(L10n.favorites)
            }
        }.padding(.horizontal, 8).padding(.vertical, 6).contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.itemAccessibilityLabel(name: summary.item.name,
                pages: summary.file.map { FileKind.size($0.byteCount) } ?? L10n.pageCount(summary.pageCount)))
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

    private func greeting(at date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: L10n.premiumMorning
        case 12..<18: L10n.premiumAfternoon
        default: L10n.premiumEvening
        }
    }
}

private enum DashboardFilter: String { case recent, favorites }

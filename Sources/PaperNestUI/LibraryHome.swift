import PaperNestCore
import PaperNestStore
import SwiftUI

/// Live dashboard backed by the existing library session; no reference/sample data.
struct DashboardView: View {
    @Bindable var model: LibraryModel
    var compact: Bool
    var openFile: (LibraryStore.ItemSummary) -> Void
    var showLibrary: () -> Void
    var newFolder: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var creatingNotebook = false
    @State private var createdItem: ItemID?
    @State private var filter: DashboardFilter = .all

    private var recent: [LibraryStore.ItemSummary] {
        model.recentItems.filter {
            switch filter {
            case .all: true
            case .notes: $0.item.kind == .notebook
            case .documents: $0.item.kind != .notebook
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            quickActions
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L10n.homeRecent).font(.title3.bold())
                    Spacer()
                    Button(L10n.homeSeeAll, action: showLibrary)
                        .font(.subheadline.weight(.medium))
                        .accessibilityIdentifier("home-see-all")
                }
                if !compact {
                    if dynamicTypeSize.isAccessibilitySize {
                        Picker(L10n.homeRecent, selection: $filter) { filterOptions }
                            .pickerStyle(.menu)
                    } else {
                        Picker(L10n.homeRecent, selection: $filter) { filterOptions }
                            .pickerStyle(.segmented).frame(maxWidth: 440)
                    }
                }
                if recent.isEmpty {
                    ContentUnavailableView(L10n.premiumEmpty, systemImage: "doc.badge.plus", description: Text(L10n.premiumEmptyDetail))
                } else if compact {
                    VStack(spacing: 8) { ForEach(recent) { item in recentButton(item, layout: .list) } }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("home-recent")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 280 : 165, maximum: 260), spacing: 16)], spacing: 16) {
                        ForEach(recent) { item in recentButton(item, layout: .grid) }
                    }.accessibilityElement(children: .contain)
                        .accessibilityIdentifier("home-recent")
                }
            }

        }
        .foregroundStyle(.primary)
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            model.sidebarSelection = .all
            Task { await model.importFiles(files) }
            return true
        }
        #if os(macOS)
        .onPasteCommand(of: Clipboard.pasteableTypes) { _ in
            guard let content = Clipboard.read() else { return }
            model.sidebarSelection = .all
            switch content {
            case .files(let urls): Task { await model.importFiles(urls) }
            case .image(let data):
                let name = L10n.pastedImageName(Date().formatted(date: .abbreviated, time: .shortened))
                Task { await model.importImages([data], name: name) }
            }
        }
        #endif
        .sheet(isPresented: $creatingNotebook, onDismiss: {
            if let id = createdItem { createdItem = nil; openDocument(id) }
        }) { NotebookCreationSheet(model: model) { createdItem = $0 } }
    }

    @ViewBuilder private var filterOptions: some View {
        Text(L10n.allDocuments).tag(DashboardFilter.all)
        Text(L10n.premiumNotes).tag(DashboardFilter.notes)
        Text(L10n.toolsDocuments).tag(DashboardFilter.documents)
    }

    @ViewBuilder private var header: some View {
        if compact {
            VStack(alignment: .leading, spacing: 20) {
                if dynamicTypeSize.isAccessibilitySize {
                    Text(Brand.displayName).font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Button { model.isShowingSettings = true } label: {
                        Label(L10n.settingsTitle, systemImage: "gearshape")
                    }.font(.body).accessibilityIdentifier("library-settings")
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.title2).padding(10).background(Theme.gradient, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityHidden(true)
                        Text(Brand.displayName).font(.title2.bold())
                        Spacer()
                        Button { model.isShowingSettings = true } label: { Image(systemName: "gearshape").font(.title3).padding(8) }
                            .accessibilityLabel(L10n.settingsTitle).accessibilityIdentifier("library-settings")
                    }
                }
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField(L10n.searchPrompt, text: $model.searchText, prompt: Text(L10n.searchPrompt).foregroundStyle(.white.opacity(0.85)))
                        .font(.subheadline).onSubmit(showLibrary)
                        #if os(iOS)
                        .submitLabel(.search)
                        #endif
                        .accessibilityIdentifier("home-search")
                }.padding(12).background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))

            }
            .foregroundStyle(.white).padding(20)
            .background(Theme.headerGradient, in: RoundedRectangle(cornerRadius: 22))
        } else {
            HStack(alignment: .top) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(greeting(at: context.date)).font(.largeTitle.bold())
                        Text(L10n.premiumWelcome).font(.body).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Menu {
                    Button(L10n.newNotebook) { creatingNotebook = true }
                    Button(L10n.importFiles) { model.isShowingFileImporter = true }
                    Button(L10n.newFolder, action: newFolder)
                } label: {
                    Label(L10n.premiumNew, systemImage: "plus").font(.headline)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .foregroundStyle(.white).background(Theme.gradient, in: Capsule())
                }.menuStyle(.borderlessButton).fixedSize()
            }
        }
    }

    private var quickActions: some View {
        LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                  ? [GridItem(.flexible())]
                  : compact
                    ? Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
                    : [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
            action(compact ? L10n.premiumNote : L10n.newNotebook, hint: L10n.premiumNotesHint, icon: "note.text", color: .orange, id: "home-new-note") { creatingNotebook = true }
            #if os(iOS)
            action(compact ? L10n.premiumScan : L10n.scan, hint: L10n.premiumScanHint, icon: "doc.viewfinder", color: .blue, id: "library-scan") { model.isShowingScanner = true }
                .disabled(!DocumentCameraView.isSupported)
                .opacity(DocumentCameraView.isSupported ? 1 : 0.45)
                .accessibilityHint(DocumentCameraView.isSupported ? "" : L10n.scanUnsupported)
            #endif
            action(compact ? L10n.premiumImport : L10n.importFiles, hint: L10n.premiumImportHint, icon: "doc.badge.arrow.up", color: .green, id: "library-import") { model.isShowingFileImporter = true }
            action(compact ? L10n.premiumFolder : L10n.newFolder, hint: L10n.premiumFolderHint, icon: "folder.fill", color: .orange, id: "home-new-folder", run: newFolder)
        }
    }

    private func action(_ title: String, hint: String, icon: String, color: Color, id: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 24, weight: .medium)).accessibilityHidden(true)
                    .foregroundStyle(color).frame(width: 46, height: 42)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                Text(title).font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.center)
                if !compact { Text(hint).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            }.frame(maxWidth: .infinity, minHeight: compact ? 92 : 112, alignment: .top)
                .padding(compact ? 8 : 14).modifier(PremiumCard())
        }.buttonStyle(PremiumButtonStyle()).accessibilityIdentifier(id)
    }

    private func recentButton(_ summary: LibraryStore.ItemSummary, layout: LibraryLayout) -> some View {
        Button {
            if summary.file != nil { openFile(summary) } else { openDocument(summary.id) }
        } label: {
            ItemCell(summary: summary, showsDeletionDate: false, layout: layout, reservesMenuSpace: false)
        }.buttonStyle(PremiumButtonStyle())
        .contextMenu {
            Button(summary.item.isFavorite ? L10n.removeFavorite : L10n.addFavorite) { Task { await model.setFavorite(summary.id, !summary.item.isFavorite) } }
        }
    }

    private func openDocument(_ id: ItemID) {
        if !compact { model.sidebarSelection = .all }
        model.open(id)
    }

    private func greeting(at date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: L10n.premiumMorning
        case 12..<18: L10n.premiumAfternoon
        default: L10n.premiumEvening
        }
    }
}

private enum DashboardFilter: Hashable { case all, notes, documents }

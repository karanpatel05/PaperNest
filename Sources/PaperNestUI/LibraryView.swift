import PaperNestCore
import PaperNestRender
import PaperNestStore
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Bindable var model: LibraryModel
    @AppStorage("libraryLayout") private var layout: LibraryLayout = .grid
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var renaming: LibraryStore.ItemSummary?
    @State private var renameText = ""
    @State private var confirmingDelete: LibraryStore.ItemSummary?
    @State private var exporting: LibraryStore.ItemSummary?
    @State private var isDropTargeted = false

    static let importableTypes: [UTType] = [.pdf, .jpeg, .png]

    private var reloadKey: String {
        "\(model.scope)|\(model.searchText)|\(model.session.changeToken)"
    }

    private var title: String { model.scopeTitle }

    var body: some View {
        content
            .background(Theme.libraryBackground)
            .navigationTitle(title)
            #if os(macOS)
            .navigationSubtitle(model.hasLoaded ? L10n.itemCount(model.items.count) : "")
            #endif
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $model.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: L10n.searchPrompt)
            #else
            .searchable(text: $model.searchText, prompt: L10n.searchPrompt)
            #endif
            .toolbar { toolbar }
            .dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(\.isFileURL)
                guard !files.isEmpty, model.scope != .recentlyDeleted else { return false }
                Task { await model.importFiles(files) }
                return true
            } isTargeted: { isDropTargeted = $0 }
            #if os(macOS)
            .onPasteCommand(of: Clipboard.pasteableTypes) { _ in paste() }
            #endif
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                if model.isImporting {
                    ProgressView(L10n.importing)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding()
                }
            }
            .task(id: reloadKey) {
                // Brief debounce so typing in search doesn't query per keystroke.
                if !model.searchText.isEmpty { try? await Task.sleep(for: .milliseconds(150)) }
                guard !Task.isCancelled else { return }
                await model.reload()
            }
            .alert(L10n.renameTitle, isPresented: renameBinding, presenting: renaming) { summary in
                TextField(L10n.renamePlaceholder, text: $renameText)
                Button(L10n.cancel, role: .cancel) {}
                Button(L10n.ok) { Task { await model.rename(summary.id, to: renameText) } }
            }
            .confirmationDialog(confirmingDelete.map { L10n.deletePermanentlyTitle($0.item.name) } ?? "",
                                isPresented: deleteBinding, titleVisibility: .visible, presenting: confirmingDelete) { summary in
                Button(L10n.deletePermanently, role: .destructive) { Task { await model.deletePermanently([summary.id]) } }
                Button(L10n.cancel, role: .cancel) {}
            } message: { _ in
                Text(L10n.deletePermanentlyMessage)
            }
            .sheet(item: $exporting) { summary in
                ExportLoader(itemID: summary.id, currentPageID: nil)
            }
    }

    @ViewBuilder
    private var content: some View {
        if !model.hasLoaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    #if os(iOS)
                    if model.scope != .recentlyDeleted, model.searchText.isEmpty {
                        CaptureActions(model: model)
                    }
                    #endif
                    if model.items.isEmpty {
                        emptyState.frame(maxWidth: .infinity, minHeight: 300)
                    } else {
                        collectionHeader
                        if layout == .grid {
                            LazyVGrid(columns: columns, spacing: 18) {
                                ForEach(model.items) { summary in cell(for: summary) }
                            }
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(model.items) { summary in cell(for: summary) }
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 1200)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("library-collection")
            .accessibilityValue(layout == .grid ? L10n.gridView : L10n.listView)
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 280 : 150, maximum: 280), spacing: 16)]
    }

    private var collectionHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(L10n.itemCount(model.items.count))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("library-count")
            Spacer(minLength: 0)
            if model.scope != .recentlyDeleted {
                sortMenu
            }
            Picker(L10n.libraryLayout, selection: $layout) {
                Image(systemName: "square.grid.2x2").tag(LibraryLayout.grid)
                    .accessibilityLabel(L10n.gridView)
                Image(systemName: "list.bullet").tag(LibraryLayout.list)
                    .accessibilityLabel(L10n.listView)
            }
            .pickerStyle(.segmented)
            .frame(width: 96)
            .accessibilityIdentifier("library-layout")
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker(L10n.sortBy, selection: $model.sortOrder) {
                ForEach(LibrarySort.allCases, id: \.self) { order in
                    Text(order.title).tag(order)
                }
            }
            .pickerStyle(.inline)
        } label: {
            #if os(macOS)
            Text(model.sortOrder.title)
            #else
            Label(L10n.sortBy, systemImage: "arrow.up.arrow.down")
                .labelStyle(.iconOnly)
                .frame(minWidth: 32, minHeight: 32)
            #endif
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        .fixedSize()
        #endif
        .help(L10n.sortBy)
        .accessibilityLabel(L10n.sortBy)
        .accessibilityValue(model.sortOrder.title)
        .accessibilityIdentifier("library-sort")
    }

    @ViewBuilder
    private func cell(for summary: LibraryStore.ItemSummary) -> some View {
        Group {
            if model.scope == .recentlyDeleted {
                ItemCell(summary: summary, showsDeletionDate: true, layout: layout)
            } else {
                NavigationLink(value: summary.id) {
                    ItemCell(summary: summary, showsDeletionDate: false, layout: layout)
                }
                .buttonStyle(.plain)
            }
        }
        .contextMenu { itemActions(for: summary) }
        .overlay(alignment: layout == .grid ? .bottomTrailing : .trailing) {
            Menu {
                itemActions(for: summary)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .padding(.trailing, layout == .grid ? 0 : 6)
            .accessibilityLabel(L10n.more)
            .accessibilityIdentifier("item-more")
        }
    }

    /// The same actions for the context menu and the ⋯ button.
    @ViewBuilder
    private func itemActions(for summary: LibraryStore.ItemSummary) -> some View {
        if model.scope == .recentlyDeleted {
            Button(L10n.recover) { Task { await model.recover([summary.id]) } }
            Button(L10n.deletePermanently, role: .destructive) { confirmingDelete = summary }
        } else {
            Button(L10n.rename) {
                renameText = summary.item.name
                renaming = summary
            }
            Button(summary.item.isFavorite ? L10n.removeFavorite : L10n.addFavorite) {
                Task { await model.setFavorite(summary.id, !summary.item.isFavorite) }
            }
            let destinations = model.folders.filter { $0.id != summary.item.folderID }
            if summary.item.folderID != nil || !destinations.isEmpty {
                Menu(L10n.moveToFolder) {
                    if summary.item.folderID != nil {
                        Button(L10n.noFolder) { Task { await model.move([summary.id], to: nil) } }
                    }
                    ForEach(destinations) { folder in
                        Button(folder.name) { Task { await model.move([summary.id], to: folder.id) } }
                    }
                }
            }
            Button(L10n.export) { exporting = summary }
                .disabled(summary.pageCount == 0)
            Divider()
            Button(L10n.delete, role: .destructive) { Task { await model.moveToRecentlyDeleted([summary.id]) } }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !model.searchText.isEmpty, model.scope != .recentlyDeleted {
            ContentUnavailableView(L10n.noResultsTitle, systemImage: "magnifyingglass",
                                   description: Text(L10n.noResultsMessage(model.searchText)))
        } else {
            switch model.scope {
            case .favorites:
                ContentUnavailableView(L10n.emptyFavoritesTitle, systemImage: "star", description: Text(L10n.emptyFavoritesMessage))
            case .recentlyDeleted:
                ContentUnavailableView(L10n.emptyDeletedTitle, systemImage: "trash",
                                       description: Text(L10n.emptyDeletedMessage(days: RetentionPolicy.recentlyDeletedDays)))
            case .folder(.some):
                ContentUnavailableView {
                    Label(L10n.emptyFolderTitle, systemImage: "folder")
                } description: {
                    Text(L10n.emptyFolderMessage)
                } actions: {
                    Button(L10n.importFiles) { model.isShowingFileImporter = true }
                        .buttonStyle(.borderedProminent)
                }
            case .all, .folder(nil):
                ContentUnavailableView {
                    Label(L10n.emptyLibraryTitle, systemImage: "doc.viewfinder")
                } description: {
                    #if os(macOS)
                    Text(L10n.emptyLibraryMessageMac)
                    #else
                    Text(L10n.emptyLibraryMessageTouch)
                    #endif
                } actions: {
                    Button(L10n.importFiles) { model.isShowingFileImporter = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        #if os(macOS)
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.isShowingFileImporter = true
            } label: {
                Label(L10n.importFiles, systemImage: "square.and.arrow.down")
            }
            .disabled(model.scope == .recentlyDeleted)
        }
        #endif
        #if os(iOS)
        // The Mac uses the standard Settings window (⌘,) instead.
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.isShowingSettings = true
            } label: {
                Label(L10n.settingsTitle, systemImage: "gearshape")
            }
            .accessibilityIdentifier("library-settings")
        }
        #endif
    }

    private func paste() {
        guard model.scope != .recentlyDeleted, let content = Clipboard.read() else { return }
        switch content {
        case .files(let urls):
            Task { await model.importFiles(urls) }
        case .image(let data):
            let name = L10n.pastedImageName(Date().formatted(date: .abbreviated, time: .shortened))
            Task { await model.importImages([data], name: name) }
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } })
    }
}

enum LibraryLayout: String {
    case grid, list
}

struct ItemCell: View {
    let summary: LibraryStore.ItemSummary
    let showsDeletionDate: Bool
    var layout: LibraryLayout = .grid
    /// Leaves room for the ⋯ button that `LibraryView` overlays.
    var reservesMenuSpace = true
    /// Gray on the white library; white on the gray iPhone home.
    var tileBackground = Theme.preview

    var body: some View {
        Group {
            if layout == .grid {
                VStack(alignment: .leading, spacing: 10) {
                    preview
                        .frame(height: reservesMenuSpace ? 190 : 150)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    metadata
                        .padding(.trailing, reservesMenuSpace ? 36 : 0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(spacing: 14) {
                    preview.frame(width: 60, height: 76).clipShape(RoundedRectangle(cornerRadius: 6))
                    metadata.frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .padding(.trailing, 36)
                .background(Theme.preview)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.itemAccessibilityLabel(name: summary.item.name, pages: L10n.pageCount(summary.pageCount)))
        .accessibilityAddTraits(showsDeletionDate ? [] : .isButton)
    }

    private var preview: some View {
        ZStack {
            tileBackground
            if let cover = summary.coverPage {
                PageImageView(page: cover, pixelSize: 560)
                    .padding(layout == .grid ? 16 : 6)
            } else {
                Image(systemName: "doc.text").font(.largeTitle).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(summary.item.name).font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary).lineLimit(2)
                if summary.item.isFavorite {
                    Image(systemName: "star.fill").font(.caption).foregroundStyle(Theme.accent)
                }
            }
            Text(verbatim: "\(secondaryText) · \(L10n.pageCount(summary.pageCount))")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    private var secondaryText: String {
        if showsDeletionDate, let deleted = summary.item.deletedAt {
            return L10n.deletedOn(deleted.formatted(date: .abbreviated, time: .omitted))
        }
        let date = summary.item.modifiedAt.formatted(date: .abbreviated, time: .omitted)
        return date
    }
}

/// Prompts for one queued PDF password at a time.
struct PasswordPrompt: ViewModifier {
    @Bindable var model: LibraryModel
    @State private var password = ""

    func body(content: Content) -> some View {
        let pending = model.passwordQueue.first
        content.alert(pending.map { L10n.passwordTitle($0.filename) } ?? "",
                      isPresented: Binding(get: { pending != nil && model.presentedError == nil }, set: { _ in }),
                      presenting: pending) { item in
            SecureField(L10n.passwordField, text: $password)
            Button(L10n.cancel, role: .cancel) {
                password = ""
                model.cancelPassword(item)
            }
            Button(L10n.passwordOpen) {
                let entered = password
                password = ""
                Task { await model.submitPassword(entered, for: item) }
            }
        } message: { item in
            Text(item.lastAttemptFailed ? "\(L10n.importIncorrectPassword)\n\(L10n.passwordMessage)" : L10n.passwordMessage)
        }
    }
}

extension LibrarySort {
    var title: String {
        switch self {
        case .dateModified: L10n.sortDateModified
        case .dateAdded: L10n.sortDateAdded
        case .name: L10n.sortName
        }
    }
}

/// Scan and Import, side by side (stacked when they don't fit).
struct CaptureActions: View {
    @Bindable var model: LibraryModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { buttons }
            VStack(spacing: 12) { buttons }
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var buttons: some View {
        #if os(iOS)
        Button { model.isShowingScanner = true } label: {
            Label(L10n.scan, systemImage: "doc.viewfinder")
                .font(.headline).frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!DocumentCameraView.isSupported)
        .accessibilityIdentifier("library-scan")
        .accessibilityHint(DocumentCameraView.isSupported ? "" : L10n.scanUnsupported)
        #endif

        Button { model.isShowingFileImporter = true } label: {
            Label(L10n.importFiles, systemImage: "square.and.arrow.down")
                .font(.headline).frame(maxWidth: .infinity, minHeight: 28)
                .foregroundStyle(.primary)
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
        .accessibilityIdentifier("library-import")
    }
}

/// What the library presents from any of its screens (the iPhone home,
/// a scope's grid): the file importer, the camera, Settings, errors and
/// password prompts. Attached once, at the root.
struct LibraryPresentations: ViewModifier {
    @Bindable var model: LibraryModel

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $model.isShowingFileImporter, allowedContentTypes: LibraryView.importableTypes,
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): Task { await model.importFiles(urls) }
                case .failure: model.reportPickerFailure()
                }
            }
            .alert(model.presentedError?.title ?? "", isPresented: errorBinding, presenting: model.presentedError) { _ in
                Button(L10n.ok, role: .cancel) {}
            } message: { error in
                Text(error.message)
            }
            .modifier(PasswordPrompt(model: model))
            #if os(iOS)
            .sheet(isPresented: $model.isShowingSettings) {
                SettingsView(session: model.session)
            }
            .fullScreenCover(isPresented: $model.isShowingScanner) {
                DocumentCameraView { outcome in
                    model.isShowingScanner = false
                    switch outcome {
                    case .scanned(let images):
                        let name = L10n.scanName(Date().formatted(date: .abbreviated, time: .shortened))
                        Task { await model.importImages(images, name: name) }
                    case .cancelled:
                        break
                    case .failed:
                        model.presentedError = PresentedError(title: L10n.genericErrorTitle, message: L10n.scanFailed)
                    }
                }
                .ignoresSafeArea()
            }
            #endif
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.presentedError != nil }, set: { if !$0 { model.presentedError = nil } })
    }
}

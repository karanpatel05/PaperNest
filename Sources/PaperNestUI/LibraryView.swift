import PaperNestCore
import PaperNestRender
import PaperNestStore
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Bindable var model: LibraryModel
    @AppStorage("libraryLayout") private var documentLayout: LibraryLayout = .list
    @AppStorage("notebookLibraryLayout") private var notebookLayout: LibraryLayout = .grid
    private var layout: LibraryLayout { model.contentKind == .notes ? notebookLayout : documentLayout }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var renaming: LibraryStore.ItemSummary?
    @State private var renameText = ""
    @State private var confirmingDelete: LibraryStore.ItemSummary?
    @State private var exporting: LibraryStore.ItemSummary?
    @State private var isDropTargeted = false
    @State private var isSelecting = false
    @State private var selection: Set<ItemID> = []
    @State private var isComposing = false
    @State private var toolsRequest: DocumentToolsRequest?
    @State private var createdItemID: ItemID?
    @State private var bulkExport: BulkExportRequest?
    @State private var fileDetails: FileDetailsRequest?
    @State private var filePreview: FilePreviewRequest?
    @State private var creatingNotebook = false

    /// Anything can be kept: a type we cannot make pages from becomes a
    /// file item instead. Pages-only flows use `pageTypes`.
    static let importableTypes: [UTType] = [.item]
    static let pageTypes: [UTType] = [.pdf, .jpeg, .png]

    private var reloadKey: String {
        "\(model.contentKind)|\(model.scope)|\(model.searchText)|\(model.session.changeToken)"
    }

    private var title: String { model.contentKind == .notes ? L10n.premiumNotes : model.scopeTitle }

    /// Keep the previous scope's rows out of Notes while its async reload finishes.
    private var visibleItems: [LibraryStore.ItemSummary] {
        model.items.filter { model.contentKind.includes($0.item.kind) }
    }

    var body: some View {
        content
            .background(Theme.libraryBackground)
            .navigationTitle(title)
            #if os(macOS)
            .navigationSubtitle(model.hasLoaded ? L10n.itemCount(visibleItems.count) : "")
            #endif
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $model.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: L10n.searchPrompt)
            #else
            .searchable(text: $model.searchText, prompt: L10n.searchPrompt)
            #endif
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) {
                if isSelecting { selectionBar }
            }
            .onChange(of: model.scope) { _, _ in endSelection() }
            .onChange(of: model.contentKind) { _, _ in endSelection() }
            .onChange(of: model.searchText) { _, _ in endSelection() }
            .onChange(of: visibleItems.map(\.id)) { _, ids in selection.formIntersection(ids) }
            .dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(\.isFileURL)
                guard !files.isEmpty, model.scope != .recentlyDeleted else { return false }
                Task { await model.importFiles(files, chooseLocation: true) }
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
            .sheet(isPresented: $creatingNotebook, onDismiss: openCreatedItem) {
                NotebookCreationSheet(model: model) { createdItemID = $0 }
            }
            .sheet(item: $toolsRequest, onDismiss: openCreatedItem) { request in
                DocumentToolsSheet(request: request) { createdItemID = $0 }
            }
            .sheet(item: $bulkExport) { request in
                BulkExportSheet(request: request)
            }
            .sheet(item: $fileDetails) { request in
                FileDetailsSheet(request: request)
            }
            .modifier(FilePreviewPresentation(request: $filePreview))
    }

    private func openCreatedItem() {
        guard let id = createdItemID else { return }
        createdItemID = nil
        endSelection()
        model.open(id)
    }

    @ViewBuilder
    private var content: some View {
        if !model.hasLoaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.scope != .recentlyDeleted, model.contentKind != .notes, model.searchText.isEmpty {
                        if model.scope == .all || model.scope == .favorites { documentFilters }
                        folderNavigation
                    }
                    if visibleItems.isEmpty {
                        emptyState.frame(maxWidth: .infinity, minHeight: 300)
                    } else {
                        collectionHeader
                        if layout == .grid {
                            LazyVGrid(columns: columns, spacing: 18) {
                                ForEach(visibleItems) { summary in cell(for: summary) }
                                if model.contentKind == .notes, model.scope != .recentlyDeleted, !isSelecting { newNotebookTile }
                            }
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(visibleItems) { summary in cell(for: summary) }
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

    private var documentFilters: some View {
        HStack(spacing: 6) {
            scopeButton(L10n.homeRecent, symbol: "clock", scope: .all, identifier: "library-filter-recent")
            scopeButton(L10n.favorites, symbol: "star", scope: .favorites, identifier: "library-filter-favorites")
        }.padding(4).modifier(PremiumCard())
    }

    private func scopeButton(_ title: String, symbol: String, scope: LibraryStore.Scope, identifier: String) -> some View {
        Button {
            if scope == .all { model.sortOrder = .dateModified }
            model.sidebarSelection = scope
        } label: {
            Label(title, systemImage: symbol).font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(model.scope == scope ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
            .accessibilityIdentifier(identifier)
            .accessibilityValue(model.scope == scope ? L10n.selectionOn : L10n.selectionOff)
    }

    private var newNotebookTile: some View {
        Button { creatingNotebook = true } label: {
            VStack(spacing: 12) {
                Image(systemName: "plus").font(.title)
                Text(L10n.newNotebook).font(.subheadline).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 218)
            .background(Theme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 3])) }
        }.buttonStyle(.plain)
            .accessibilityIdentifier("notes-create-tile")
            .accessibilityValue(L10n.newNotebook)
    }

    private var folderNavigation: some View {
        let children = model.folders.filter { $0.parentID == model.currentFolderID }
        return VStack(alignment: .leading, spacing: 12) {
            if let currentID = model.currentFolderID,
               let current = model.folders.first(where: { $0.id == currentID }) {
                Button {
                    model.sidebarSelection = current.parentID.map { .folder($0) } ?? .all
                } label: {
                    Label(current.name, systemImage: "chevron.left")
                        .font(.subheadline).frame(minHeight: 44)
                }.accessibilityIdentifier("library-folder-parent")
            }
            if !children.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(children) { folder in
                            Button { model.sidebarSelection = .folder(folder.id) } label: {
                                VStack(spacing: 5) {
                                    Image(systemName: "folder.fill").font(.title2).foregroundStyle(Theme.accent)
                                    Text(folder.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    Text(L10n.itemCount(model.counts.folders[folder.id, default: 0]))
                                        .font(.caption).foregroundStyle(.secondary)
                                }.frame(width: dynamicTypeSize.isAccessibilitySize ? 180 : 100).frame(minHeight: 76)
                                    .padding(10).background(Theme.selection.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain)
                                .accessibilityIdentifier("library-folder-\(folder.id)")
                                .accessibilityValue(L10n.itemCount(model.counts.folders[folder.id, default: 0]))
                        }
                    }
                }
            }
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 280 : 150, maximum: 280), spacing: 16)]
    }

    private var collectionHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(L10n.itemCount(visibleItems.count))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("library-count")
            Spacer(minLength: 0)
            if model.scope != .recentlyDeleted {
                sortMenu
            }
            Picker(L10n.libraryLayout, selection: Binding(get: { layout }, set: { value in
                if model.contentKind == .notes { notebookLayout = value } else { documentLayout = value }
            })) {
                Image(systemName: "square.grid.2x2").tag(LibraryLayout.grid)
                    .accessibilityLabel(L10n.gridView)
                Image(systemName: "list.bullet").tag(LibraryLayout.list)
                    .accessibilityLabel(L10n.listView)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
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
            if isSelecting {
                Button {
                    if !selection.insert(summary.id).inserted { selection.remove(summary.id) }
                } label: {
                    ItemCell(summary: summary, showsDeletionDate: false, layout: layout, isSelected: selection.contains(summary.id))
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: selection.contains(summary.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundStyle(Theme.accent)
                                .background(.background, in: Circle()).padding(8)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityValue([selection.contains(summary.id) ? L10n.selectionOn : L10n.selectionOff,
                                     summary.item.colorLabel?.title].compactMap { $0 }.joined(separator: ", "))
                .accessibilityAddTraits(selection.contains(summary.id) ? [.isSelected] : [])
            } else if model.scope == .recentlyDeleted {
                ItemCell(summary: summary, showsDeletionDate: true, layout: layout)
            } else if summary.file != nil {
                Button { filePreview = FilePreviewRequest(summary: summary) } label: {
                    ItemCell(summary: summary, showsDeletionDate: false, layout: layout)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: summary.id) {
                    ItemCell(summary: summary, showsDeletionDate: false, layout: layout)
                }
                .buttonStyle(.plain)
            }
        }
        .contextMenu { if !isSelecting { itemActions(for: summary) } }
        .overlay(alignment: layout == .grid ? (summary.item.kind == .notebook ? .topTrailing : .bottomTrailing) : .trailing) {
            if !isSelecting {
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
            Button(L10n.duplicate) { duplicate([summary.id]) }
                .disabled(isComposing)
            Button(L10n.extractPages) { toolsRequest = DocumentToolsRequest(operation: .extract(summary)) }
                .disabled(summary.pageCount == 0)
            // One page is already its own document.
            Button(L10n.splitPages) { split(summary) }
                .disabled(summary.pageCount < 2 || isComposing)
            ColorLabelMenu { color in Task { await model.setColorLabel(color, for: [summary.id]) } }
            if let file = summary.file {
                Button(L10n.fileShowDetails) { fileDetails = FileDetailsRequest(summary: summary) }
                if FileKind.isArchive(file.uti) {
                    Button(L10n.fileExtract) { extractArchive(summary) }
                        .disabled(isComposing)
                }
            }
            Divider()
            Button(L10n.delete, role: .destructive) { Task { await model.moveToRecentlyDeleted([summary.id]) } }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !model.searchText.isEmpty, model.scope != .recentlyDeleted {
            ContentUnavailableView(L10n.noResultsTitle, systemImage: "magnifyingglass",
                                   description: Text(L10n.noResultsMessage(model.searchText)))
        } else if model.contentKind == .notes {
            ContentUnavailableView {
                Label(L10n.emptyNotesTitle, systemImage: "book.closed")
            } description: {
                Text(L10n.emptyNotesMessage)
            } actions: {
                Button(L10n.newNotebook) { creatingNotebook = true }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("notes-create-empty")
            }
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
        ToolbarItem(placement: .primaryAction) {
            if model.contentKind == .notes {
                Button { creatingNotebook = true } label: {
                    Label(L10n.newNotebook, systemImage: "plus")
                }
                .accessibilityIdentifier("notes-create")
                .disabled(isSelecting || isComposing)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            if isSelecting || (model.scope != .recentlyDeleted && !visibleItems.isEmpty) {
                Button(isSelecting ? L10n.done : L10n.selectItems) {
                    if isSelecting { endSelection() } else { isSelecting = true }
                }
                .accessibilityIdentifier("library-select")
                .disabled(isComposing)
            }
        }
        #if os(macOS)
        ToolbarItemGroup(placement: .primaryAction) {
            if model.contentKind != .notes {
                Button {
                    model.isShowingFileImporter = true
                } label: {
                    Label(L10n.importFiles, systemImage: "square.and.arrow.down")
                }
                .disabled(model.scope == .recentlyDeleted)
            }
        }
        #endif
        #if os(iOS)
        ToolbarItem(placement: .primaryAction) {
            if model.contentKind != .notes, model.scope != .recentlyDeleted {
                Button { model.isShowingFileImporter = true } label: {
                    Label(L10n.importFiles, systemImage: "square.and.arrow.down")
                }.accessibilityIdentifier("library-import")
            }
        }
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
            Task { await model.importFiles(urls, chooseLocation: true) }
        case .image(let data):
            let name = L10n.pastedImageName(Date().formatted(date: .abbreviated, time: .shortened))
            Task { await model.importImages([data], name: name, chooseLocation: true) }
        }
    }

    private var selectedItems: [LibraryStore.ItemSummary] {
        visibleItems.filter { selection.contains($0.id) }
    }

    private var selectionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                selectionSummary
                Spacer(minLength: 8)
                selectionControls
            }
            VStack(alignment: .leading, spacing: 12) {
                selectionSummary
                selectionControls
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding().background(.regularMaterial)
        .disabled(isComposing)
    }

    private var selectionSummary: some View {
        Text(L10n.selectionCount(selection.count)).font(.subheadline)
            .accessibilityIdentifier("selection-count")
    }

    @ViewBuilder
    private var selectionControls: some View {
        Button(selection.count == visibleItems.count ? L10n.deselectAll : L10n.selectAll) {
            selection = selection.count == visibleItems.count ? [] : Set(visibleItems.map(\.id))
        }
        Menu {
            Button(L10n.duplicate) { duplicate(selectedItems.map(\.id)) }
            Button(L10n.mergeDocuments) {
                toolsRequest = DocumentToolsRequest(operation: .merge(selectedItems, model.currentFolderID))
            }.disabled(selectedItems.count < 2 || selectedItems.contains { $0.pageCount == 0 })
            Menu(L10n.moveToFolder) {
                Button(L10n.noFolder) {
                    let ids = selectedItems.map(\.id)
                    Task { await model.move(ids, to: nil) }
                }
                ForEach(model.folders) { folder in
                    Button(folder.name) {
                        let ids = selectedItems.map(\.id)
                        Task { await model.move(ids, to: folder.id) }
                    }
                }
            }
            // Page-less documents are skipped by the archive writer, so the
            // action is offered as long as one selected document has pages.
            Button(L10n.exportAsZip) { bulkExport = BulkExportRequest(ids: selectedItems.map(\.id)) }
                .disabled(!selectedItems.contains { $0.pageCount > 0 || $0.file != nil })
            ColorLabelMenu { color in
                let ids = selectedItems.map(\.id)
                Task { await model.setColorLabel(color, for: ids) }
            }
            Button(L10n.delete, role: .destructive) {
                let ids = selectedItems.map(\.id)
                Task { await model.moveToRecentlyDeleted(ids) }
            }
        } label: {
            if isComposing { ProgressView() } else { Label(L10n.more, systemImage: "ellipsis.circle") }
        }
        .accessibilityIdentifier("selection-actions")
        .disabled(selection.isEmpty)
    }

    private func duplicate(_ ids: [ItemID]) {
        guard !isComposing else { return }
        isComposing = true
        Task {
            if await model.duplicate(ids) { endSelection() }
            isComposing = false
        }
    }

    private func extractArchive(_ summary: LibraryStore.ItemSummary) {
        guard !isComposing else { return }
        isComposing = true
        Task {
            _ = await model.extractArchive(summary)
            isComposing = false
        }
    }

    private func split(_ summary: LibraryStore.ItemSummary) {
        guard !isComposing else { return }
        isComposing = true
        Task {
            _ = await model.split(summary)
            isComposing = false
        }
    }

    private func endSelection() {
        selection.removeAll()
        isSelecting = false
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
    var isSelected = false
    /// Leaves room for the ⋯ button that `LibraryView` overlays.
    var reservesMenuSpace = true
    /// Gray on the white library; white on the gray iPhone home.
    var tileBackground = Theme.preview

    var body: some View {
        Group {
            if layout == .grid, summary.item.kind == .notebook {
                NotebookCover(summary: summary)
                    .overlay {
                        if isSelected { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent, lineWidth: 2) }
                    }
            } else if layout == .grid {
                VStack(alignment: .leading, spacing: 10) {
                    preview
                        .frame(height: reservesMenuSpace ? 190 : 150)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            if isSelected { RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent, lineWidth: 2) }
                        }
                    metadata
                        .padding(.trailing, reservesMenuSpace ? 36 : 0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .modifier(PremiumCard())
            } else {
                HStack(spacing: 14) {
                    preview.frame(width: 40, height: 54).clipShape(RoundedRectangle(cornerRadius: 6))
                    metadata.frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .padding(.trailing, 36)
                .background(isSelected ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .bottom) { Divider().padding(.leading, 64) }
                .overlay {
                    if isSelected { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent, lineWidth: 2) }
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.itemAccessibilityLabel(
            name: summary.item.name,
            pages: summary.file.map { FileKind.size($0.byteCount) } ?? L10n.pageCount(summary.pageCount)))
        .accessibilityValue(summary.item.colorLabel?.title ?? "")
        .accessibilityAddTraits(showsDeletionDate ? [] : .isButton)
    }

    private var preview: some View {
        ZStack {
            tileBackground
            if let cover = summary.coverPage {
                PageImageView(page: cover, pixelSize: 560)
                    .padding(layout == .grid ? 16 : 6)
            } else if let file = summary.file {
                Image(systemName: FileKind.symbol(for: file.uti))
                    .font(.system(size: layout == .grid ? 44 : 28))
                    .foregroundStyle(Theme.accent)
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
                if let color = summary.item.colorLabel {
                    Image(systemName: "circle.fill").font(.caption2).foregroundStyle(color.tint)
                        .accessibilityLabel(color.title)
                }
            }
            Text(verbatim: "\(secondaryText) · \(summary.file.map { FileKind.size($0.byteCount) } ?? L10n.pageCount(summary.pageCount))")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    private var secondaryText: String {
        if showsDeletionDate, let deleted = summary.item.deletedAt {
            return L10n.deletedOn(deleted.formatted(date: .abbreviated, time: .omitted))
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: summary.item.modifiedAt, relativeTo: .now)
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
    @State private var scannerName: String?
    @Bindable var model: LibraryModel

    func body(content: Content) -> some View {
        content
            .sheet(item: $model.importLocationRequest, onDismiss: { model.finishImportLocation() }) { _ in
                ImportLocationSheet(model: model)
            }
            .modifier(FilePreviewPresentation(request: $model.importedFilePreview))
            .fileImporter(isPresented: $model.isShowingFileImporter, allowedContentTypes: LibraryView.importableTypes,
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): Task { await model.importFiles(urls, chooseLocation: true) }
                case .failure: model.reportPickerFailure()
                }
            }
            .alert(model.presentedError?.title ?? "", isPresented: errorBinding, presenting: model.presentedError) { _ in
                Button(L10n.ok, role: .cancel) {}
            } message: { error in
                Text(error.message)
            }
            .modifier(PasswordPrompt(model: model))
            .sheet(isPresented: $model.isShowingTools) {
                ToolsSheet(model: model)
            }
            #if os(iOS)
            .sheet(isPresented: $model.isShowingSettings) {
                SettingsView(session: model.session)
            }
            .fullScreenCover(isPresented: $model.isShowingScanner) {
                ScannerWorkspaceView(onName: { scannerName = $0 }) { outcome in
                    model.isShowingScanner = false
                    switch outcome {
                    case .scanned(let images):
                        let name = scannerName ?? L10n.scanName(Date().formatted(date: .abbreviated, time: .shortened))
                        scannerName = nil
                        Task { await model.importImages(images, name: name, openAfterSaving: true, chooseLocation: true) }
                    case .cancelled:
                        break
                    case .failed:
                        model.presentedError = PresentedError(title: L10n.genericErrorTitle, message: L10n.scanFailed)
                    }
                }
            }
            #endif
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.presentedError != nil }, set: { if !$0 { model.presentedError = nil } })
    }
}

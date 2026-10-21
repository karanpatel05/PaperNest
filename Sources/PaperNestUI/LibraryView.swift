import PaperNestCore
import PaperNestRender
import PaperNestStore
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Bindable var model: LibraryModel

    @State private var renaming: LibraryStore.ItemSummary?
    @State private var renameText = ""
    @State private var confirmingDelete: LibraryStore.ItemSummary?
    @State private var exporting: LibraryStore.ItemSummary?
    @State private var isDropTargeted = false
    #if os(iOS)
    @State private var isShowingScanner = false
    @State private var isShowingSettings = false
    #endif

    static let importableTypes: [UTType] = [.pdf, .jpeg, .png]

    private var reloadKey: String {
        "\(model.scope)|\(model.searchText)|\(model.session.changeToken)"
    }

    private var title: String {
        switch model.scope {
        case .all, .folder: L10n.allDocuments
        case .favorites: L10n.favorites
        case .recentlyDeleted: L10n.recentlyDeleted
        }
    }

    var body: some View {
        content
            .navigationTitle(title)
            .searchable(text: $model.searchText, prompt: L10n.searchPrompt)
            .toolbar { toolbar }
            .fileImporter(isPresented: $model.isShowingFileImporter, allowedContentTypes: Self.importableTypes,
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    Task { await model.importFiles(urls) }
                }
            }
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
            .alert(model.presentedError?.title ?? "", isPresented: errorBinding, presenting: model.presentedError) { _ in
                Button(L10n.ok, role: .cancel) {}
            } message: { error in
                Text(error.message)
            }
            .modifier(PasswordPrompt(model: model))
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
            #if os(iOS)
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(session: model.session)
            }
            .fullScreenCover(isPresented: $isShowingScanner) {
                DocumentCameraView { outcome in
                    isShowingScanner = false
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

    @ViewBuilder
    private var content: some View {
        if !model.hasLoaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.items.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 20)], spacing: 24) {
                    ForEach(model.items) { summary in
                        cell(for: summary)
                    }
                }
                .padding(20)
            }
        }
    }

    @ViewBuilder
    private func cell(for summary: LibraryStore.ItemSummary) -> some View {
        if model.scope == .recentlyDeleted {
            ItemCell(summary: summary, showsDeletionDate: true)
                .contextMenu {
                    Button(L10n.recover) { Task { await model.recover([summary.id]) } }
                    Button(L10n.deletePermanently, role: .destructive) { confirmingDelete = summary }
                }
        } else {
            NavigationLink(value: summary.id) {
                ItemCell(summary: summary, showsDeletionDate: false)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(L10n.rename) {
                    renameText = summary.item.name
                    renaming = summary
                }
                Button(summary.item.isFavorite ? L10n.removeFavorite : L10n.addFavorite) {
                    Task { await model.setFavorite(summary.id, !summary.item.isFavorite) }
                }
                Button(L10n.export) { exporting = summary }
                    .disabled(summary.pageCount == 0)
                Divider()
                Button(L10n.delete, role: .destructive) { Task { await model.moveToRecentlyDeleted([summary.id]) } }
            }
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
            case .all, .folder:
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
        ToolbarItemGroup(placement: .primaryAction) {
            #if os(iOS)
            Button {
                isShowingScanner = true
            } label: {
                Label(L10n.scan, systemImage: "doc.viewfinder")
            }
            .disabled(!DocumentCameraView.isSupported || model.scope == .recentlyDeleted)
            #endif
            Button {
                model.isShowingFileImporter = true
            } label: {
                Label(L10n.importFiles, systemImage: "square.and.arrow.down")
            }
            .disabled(model.scope == .recentlyDeleted)
        }
        #if os(iOS)
        // The Mac uses the standard Settings window (⌘,) instead.
        ToolbarItem(placement: .secondaryAction) {
            Button {
                isShowingSettings = true
            } label: {
                Label(L10n.settingsTitle, systemImage: "gearshape")
            }
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

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.presentedError != nil }, set: { if !$0 { model.presentedError = nil } })
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } })
    }
}

struct ItemCell: View {
    let summary: LibraryStore.ItemSummary
    let showsDeletionDate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let cover = summary.coverPage {
                    PageImageView(page: cover, pixelSize: 440)
                } else {
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                        .overlay(Image(systemName: "doc").font(.largeTitle).foregroundStyle(.secondary))
                }
            }
            .frame(height: 200)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if summary.item.isFavorite {
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                    }
                    Text(summary.item.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(2)
                }
                Text(secondaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.itemAccessibilityLabel(name: summary.item.name, pages: L10n.pageCount(summary.pageCount)))
        .accessibilityAddTraits(showsDeletionDate ? [] : .isButton)
    }

    private var secondaryText: String {
        if showsDeletionDate, let deleted = summary.item.deletedAt {
            return L10n.deletedOn(deleted.formatted(date: .abbreviated, time: .omitted))
        }
        let date = summary.item.modifiedAt.formatted(date: .abbreviated, time: .omitted)
        return "\(L10n.pageCount(summary.pageCount)) · \(date)"
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

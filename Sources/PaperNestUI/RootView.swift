import PaperNestCore
import PaperNestStore
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// The app's main window: a sidebar of library scopes and a navigation
/// stack from the library grid into documents. Adapts from iPhone (stacked)
/// to iPad and Mac (side by side).
public struct RootView: View {
    @State private var model: LibraryModel
    @State private var folderPrompt: FolderPrompt?
    @State private var folderName = ""
    @State private var deletingFolder: Folder?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// The name prompt for creating or renaming a folder.
    enum FolderPrompt: Identifiable {
        case create
        case rename(Folder)

        var id: String {
            switch self {
            case .create: "create"
            case .rename(let folder): folder.id.rawValue
            }
        }
    }

    public init(session: LibrarySession) {
        #if os(iOS)
        let startsAtHome = UIDevice.current.userInterfaceIdiom == .phone
        #else
        let startsAtHome = false
        #endif
        _model = State(initialValue: LibraryModel(session: session, startsAtHome: startsAtHome))
    }

    /// iPhone (compact width) shows a home in the sidebar column: capture
    /// buttons and recent documents above the library and folders.
    private var showsHome: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    public var body: some View {
        Group {
            switch model.session.state {
            case .loading:
                ProgressView(L10n.loadingLibrary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let title, let message):
                ContentUnavailableView(title, systemImage: "exclamationmark.triangle", description: Text(message))
            case .ready:
                splitView
            }
        }
        .environment(model.session)
        .tint(Theme.accent)
        .task { await model.session.bootstrap() }
    }

    private var splitView: some View {
        NavigationSplitView {
            List(selection: $model.sidebarSelection) {
                if showsHome {
                    LibraryHomeSections(model: model)
                }
                Section(L10n.sidebarLibrary) {
                    Label(L10n.allDocuments, systemImage: "doc.on.doc").badge(model.counts.all).tag(LibraryStore.Scope.all)
                    Label(L10n.favorites, systemImage: "star").badge(model.counts.favorites).tag(LibraryStore.Scope.favorites)
                    Label(L10n.recentlyDeleted, systemImage: "trash").badge(model.counts.recentlyDeleted)
                        .tag(LibraryStore.Scope.recentlyDeleted)
                }
                Section {
                    ForEach(model.folders) { folder in
                        Label(folder.name, systemImage: "folder")
                            .badge(model.counts.folders[folder.id, default: 0])
                            .tag(LibraryStore.Scope.folder(folder.id))
                            .contextMenu {
                                Button(L10n.rename) {
                                    folderName = folder.name
                                    folderPrompt = .rename(folder)
                                }
                                Button(L10n.deleteFolder, role: .destructive) { deletingFolder = folder }
                            }
                            .accessibilityIdentifier("sidebar-folder")
                    }
                } header: {
                    HStack {
                        Text(L10n.folders)
                        Spacer()
                        Button {
                            folderName = ""
                            folderPrompt = .create
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.newFolder)
                        .accessibilityLabel(L10n.newFolder)
                        .accessibilityIdentifier("sidebar-new-folder")
                    }
                }
            }
            .listStyle(.sidebar)
            .task(id: model.session.changeToken) { await model.reloadSidebar() }
            .navigationDestination(item: $model.homeDocument) { id in
                DocumentView(itemID: id, session: model.session)
            }
            #if os(iOS)
            .toolbar {
                if showsHome {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            model.isShowingTools = true
                        } label: {
                            Label(L10n.toolsTitle, systemImage: "wrench.and.screwdriver")
                        }
                        .accessibilityIdentifier("library-tools")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            model.isShowingSettings = true
                        } label: {
                            Label(L10n.settingsTitle, systemImage: "gearshape")
                        }
                        .accessibilityIdentifier("library-settings")
                    }
                }
            }
            #endif
            .alert(folderPromptTitle, isPresented: folderPromptBinding, presenting: folderPrompt) { prompt in
                TextField(L10n.renamePlaceholder, text: $folderName)
                Button(L10n.cancel, role: .cancel) {}
                Button(L10n.ok) {
                    let name = folderName
                    switch prompt {
                    case .create: Task { await model.createFolder(named: name) }
                    case .rename(let folder): Task { await model.renameFolder(folder.id, to: name) }
                    }
                }
            }
            .confirmationDialog(deletingFolder.map { L10n.deleteFolderTitle($0.name) } ?? "",
                                isPresented: deleteFolderBinding, titleVisibility: .visible, presenting: deletingFolder) { folder in
                Button(L10n.deleteFolderConfirm, role: .destructive) { Task { await model.deleteFolder(folder.id) } }
                Button(L10n.cancel, role: .cancel) {}
            } message: { _ in
                Text(L10n.deleteFolderMessage)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .navigationTitle(showsHome ? L10n.homeTitle : Brand.displayName)
        } detail: {
            NavigationStack(path: $model.path) {
                LibraryView(model: model)
                    .navigationDestination(for: ItemID.self) { id in
                        DocumentView(itemID: id, session: model.session)
                    }
            }
        }
        .modifier(LibraryPresentations(model: model))
        .focusedSceneValue(\.libraryModel, model)
        #if DEBUG
        .task { await openDebugItemIfRequested() }
        #endif
    }

    private var folderPromptTitle: String {
        switch folderPrompt {
        case .rename: L10n.renameFolderTitle
        case .create, nil: L10n.newFolder
        }
    }

    private var folderPromptBinding: Binding<Bool> {
        Binding(get: { folderPrompt != nil }, set: { if !$0 { folderPrompt = nil } })
    }

    private var deleteFolderBinding: Binding<Bool> {
        Binding(get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } })
    }

    #if DEBUG
    /// Dev/screenshot hook, debug builds only: `-PaperNestDebugOpenItem <name>`
    /// opens that document as if it had been tapped.
    /// Screenshot hook: `-PaperNestDebugShowTools YES` opens the Tools sheet
    /// at launch, so the screen can be captured in each language without taps.
    private func openDebugItemIfRequested() async {
        if UserDefaults.standard.bool(forKey: "PaperNestDebugShowTools") { model.isShowingTools = true }
        guard let name = UserDefaults.standard.string(forKey: "PaperNestDebugOpenItem"),
              let store = model.session.environment?.store,
              let match = try? await store.items(in: .all).first(where: { $0.item.name == name })
        else { return }
        model.open(match.id)
    }
    #endif
}

struct LibraryModelKey: FocusedValueKey {
    typealias Value = LibraryModel
}

struct DocumentCommandsKey: FocusedValueKey {
    typealias Value = DocumentCommandContext
}

/// What the Page menu needs from the focused document window.
struct DocumentCommandContext {
    let model: DocumentModel
    let undoManager: UndoManager?
    let showExport: () -> Void
    let showAddPages: () -> Void
    let showReplacePage: () -> Void
    let showCrop: () -> Void
}

extension FocusedValues {
    var libraryModel: LibraryModel? {
        get { self[LibraryModelKey.self] }
        set { self[LibraryModelKey.self] = newValue }
    }

    var documentCommands: DocumentCommandContext? {
        get { self[DocumentCommandsKey.self] }
        set { self[DocumentCommandsKey.self] = newValue }
    }
}

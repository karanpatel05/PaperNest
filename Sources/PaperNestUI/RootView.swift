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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("PaperNestWelcomeCompleted") private var welcomeCompleted = false
    @State private var model: LibraryModel
    @State private var folderPrompt: FolderPrompt?
    @State private var folderName = ""
    @State private var deletingFolder: Folder?
    @State private var dashboardVisible = true
    @State private var homeFilePreview: FilePreviewRequest?
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
        #if DEBUG
        // Isolate first-launch persistence checks from the user's app settings.
        if let key = UserDefaults.standard.string(forKey: "PaperNestDebugWelcomeKey") {
            _welcomeCompleted = AppStorage(wrappedValue: false, key)
        }
        #endif
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
                if shouldShowWelcome {
                    WelcomeView { welcomeCompleted = true }
                } else {
                    splitView
                }
            }
        }
        .modifier(FilePreviewPresentation(request: $homeFilePreview))
        .environment(model.session)
        .tint(Theme.accent)
        .task { await model.session.bootstrap() }
    }

    private var shouldShowWelcome: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "PaperNestDebugSkipWelcome") { return false }
        #endif
        return !welcomeCompleted
    }

    private var splitView: some View {
        NavigationSplitView {
            ScrollViewReader { proxy in
            List(selection: sidebarBinding) {
                if showsHome {
                    Section {} header: {
                        dashboard(compact: true).textCase(nil).id("dashboard-top")
                    }
                } else {
                    Button {
                        model.sidebarSelection = .all
                        model.sidebarSelection = nil
                        model.path = []
                        dashboardVisible = true
                    } label: {
                        Label(L10n.homeTitle, systemImage: "house.fill")
                    }
                    .listRowBackground(dashboardVisible ? Theme.accent.opacity(0.12) : .clear)
                    .accessibilityIdentifier("sidebar-home")
                }
                Section(L10n.sidebarLibrary) {
                    sidebarLabel(L10n.allDocuments, symbol: "doc.on.doc").badge(usesLargeSidebar ? 0 : model.counts.all).tag(LibraryStore.Scope.all)
                    sidebarLabel(L10n.favorites, symbol: "star").badge(usesLargeSidebar ? 0 : model.counts.favorites).tag(LibraryStore.Scope.favorites)
                    sidebarLabel(L10n.recentlyDeleted, symbol: "trash").badge(usesLargeSidebar ? 0 : model.counts.recentlyDeleted)
                        .tag(LibraryStore.Scope.recentlyDeleted)
                }
                Section {
                    ForEach(model.folders) { folder in
                        sidebarLabel(folder.name, symbol: "folder")
                            .badge(usesLargeSidebar ? 0 : model.counts.folders[folder.id, default: 0])
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
                        Text(L10n.folders).id("folders-section")
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
            .scrollContentBackground(.hidden)
            .background(Theme.sidebar)
            .onChange(of: model.sidebarSelection) { _, selected in
                if selected != nil { dashboardVisible = false }
            }
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
            .navigationTitle(showsHome ? L10n.homeTitle : Brand.displayName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsHome {
                    if dynamicTypeSize.isAccessibilitySize {
                        Menu {
                            Button(L10n.homeTitle) { proxy.scrollTo("dashboard-top", anchor: .top) }
                            Button(L10n.folders) { proxy.scrollTo("folders-section", anchor: .top) }
                            Button(L10n.premiumNew) { model.isShowingTools = true }
                            Button(L10n.premiumSearch) { dashboardVisible = false; model.sidebarSelection = .all }
                        } label: {
                            HStack {
                                Text(L10n.homeTitle).font(.body)
                                Spacer()
                                Image(systemName: "chevron.up").font(.body)
                            }.padding(16).background(Theme.surface)
                        }.accessibilityIdentifier("home-navigation-menu")
                    } else {
                    HStack(spacing: 12) {
                        Button { proxy.scrollTo("dashboard-top", anchor: .top) } label: {
                            tabLabel(L10n.homeTitle, symbol: "house.fill")
                        }
                        Button { proxy.scrollTo("folders-section", anchor: .top) } label: {
                            tabLabel(L10n.folders, symbol: "folder")
                        }.accessibilityIdentifier("home-folders")
                        Button { model.isShowingTools = true } label: {
                            Image(systemName: "plus").font(.title2.weight(.medium))
                                .foregroundStyle(.white).frame(width: 50, height: 50)
                                .background(Theme.gradient, in: Circle())
                        }.accessibilityLabel(L10n.premiumNew).accessibilityIdentifier("home-create")
                        Button { dashboardVisible = false; model.sidebarSelection = .all } label: {
                            tabLabel(L10n.premiumSearch, symbol: "magnifyingglass")
                        }.accessibilityIdentifier("home-search-tab")
                    }
                    .buttonStyle(.plain).padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Theme.surface)
                    }
                }
            }
            }
            .navigationSplitViewColumnWidth(min: usesLargeSidebar ? 420 : 200,
                                            ideal: usesLargeSidebar ? 460 : 240)
        } detail: {
            NavigationStack(path: $model.path) {
                Group {
                    if dashboardVisible && !showsHome {
                        ScrollView {
                            dashboard(compact: false).padding(28)
                                .frame(maxWidth: 1400).frame(maxWidth: .infinity)
                        }
                        .background(Theme.libraryBackground)
                        .navigationTitle(L10n.homeTitle)
                        .searchable(text: $model.searchText, prompt: L10n.searchPrompt)
                        .onSubmit(of: .search) {
                            model.sidebarSelection = .all
                            dashboardVisible = false
                        }
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button { model.isShowingTools = true } label: {
                                    Label(L10n.toolsTitle, systemImage: "wrench.and.screwdriver")
                                }.accessibilityIdentifier("library-tools")
                            }
                        }
                    } else {
                        LibraryView(model: model)
                    }
                }
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

    private var sidebarBinding: Binding<LibraryStore.Scope?> {
        Binding(get: {
            dashboardVisible && !showsHome ? nil : model.sidebarSelection
        }, set: { selected in
            if selected != nil { dashboardVisible = false }
            model.sidebarSelection = selected
        })
    }

    private func tabLabel(_ title: String, symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.title3)
            Text(title).font(.caption2).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, minHeight: 44)
    }

    private func dashboard(compact: Bool) -> some View {
        DashboardView(model: model, compact: compact, openFile: { summary in
            homeFilePreview = FilePreviewRequest(summary: summary)
        }, showLibrary: {
            dashboardVisible = false
            model.sidebarSelection = .all
        }, newFolder: {
            folderName = ""
            folderPrompt = .create
        })
    }

    private var usesLargeSidebar: Bool { dynamicTypeSize.isAccessibilitySize && !showsHome }

    @ViewBuilder
    private func sidebarLabel(_ title: String, symbol: String) -> some View {
        if usesLargeSidebar {
            Text(title).fixedSize(horizontal: false, vertical: true)
        } else {
            Label(title, systemImage: symbol)
        }
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

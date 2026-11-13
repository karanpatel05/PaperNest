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
    @State private var editingGuard = DocumentEditingGuard()
    @State private var documentTabs = DocumentTabs()
    @State private var model: LibraryModel
    @State private var folderPrompt: FolderPrompt?
    @State private var folderName = ""
    @State private var deletingFolder: Folder?
    @State private var dashboardVisible = true
    @State private var folderScrollRequest = false
    @State private var homeFilePreview: FilePreviewRequest?
    @State private var showFirstProOffer = false
    @AppStorage("PaperNestFirstProOfferHandled") private var proOfferHandled = false
    @AppStorage("PaperNestFirstProOfferPending") private var proOfferPending = false
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// View-only destinations let Home and Notes participate in native list selection.
    private enum SidebarDestination: Hashable {
        case home
        case notes
        case library(LibraryStore.Scope)
    }

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

    private var sidebarTitle: String {
        #if os(iOS)
        // Home is already named in the tab/sidebar. Its dashboard owns the
        // brand and greeting; destination titles belong to the detail column.
        return ""
        #else
        return Brand.displayName
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
                    WelcomeView {
                        welcomeCompleted = true
                        guard !proOfferHandled else { return }
                        proOfferPending = true
                        Task { await presentFirstProOfferIfEligible() }
                    }
                } else {
                    splitView
                }
            }
        }
        .modifier(FilePreviewPresentation(request: $homeFilePreview))
        .sheet(isPresented: $showFirstProOffer) {
            ProPaywallView(store: .shared).onAppear { proOfferHandled = true; proOfferPending = false }
        }
        .environment(model.session)
        .environment(editingGuard)
        .disabled(editingGuard.isClosing)
        #if os(macOS)
        .background(WindowTextEditGuard(guardState: editingGuard).frame(width: 0, height: 0))
        .onAppear { editingGuard.finishWindow = { [documentTabs] in await documentTabs.confirmWindowClose() } }
        #endif
        .tint(Theme.accent)
        .task { await model.session.bootstrap(); await SubscriptionStore.shared.start(); await presentFirstProOfferIfEligible() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await SubscriptionStore.shared.refresh(); await presentFirstProOfferIfEligible() } }
        }
        .onChange(of: SubscriptionStore.shared.hasProAccess) { _, hasAccess in
            if hasAccess { model.session.resumeTextRecognition() }
        }
        .onChange(of: showsHome, initial: true) { _, compact in model.usesCompactNavigation = compact }
    }

    private func presentFirstProOfferIfEligible() async {
        guard welcomeCompleted, proOfferPending, !proOfferHandled else { return }
        let store = SubscriptionStore.shared
        await store.refresh()
        guard store.lastRefreshSucceeded else { return }
        if store.configuration.canPurchase && !store.hasProAccess && !store.eligibleTrialIDs.isEmpty {
            showFirstProOffer = true
        } else {
            proOfferHandled = true
            proOfferPending = false
        }
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
                    sidebarDestination(L10n.homeTitle, symbol: "house.fill", destination: .home)
                        .tag(SidebarDestination.home)
                        .accessibilityIdentifier("sidebar-home")
                }
                Section(L10n.sidebarLibrary) {
                    sidebarDestination(L10n.premiumNotes, symbol: "pencil.tip", destination: .notes)
                        .tag(SidebarDestination.notes)
                        .accessibilityIdentifier("sidebar-notes")

                    sidebarDestination(L10n.allDocuments, symbol: "doc.on.doc", destination: .library(.all))
                        .tag(SidebarDestination.library(.all))
                    sidebarDestination(L10n.favorites, symbol: "star", destination: .library(.favorites))
                        .badge(usesLargeSidebar ? 0 : model.counts.favorites)
                        .tag(SidebarDestination.library(.favorites))
                    sidebarDestination(L10n.recentlyDeleted, symbol: "trash", destination: .library(.recentlyDeleted))
                        .badge(usesLargeSidebar ? 0 : model.counts.recentlyDeleted)
                        .tag(SidebarDestination.library(.recentlyDeleted))
                }
                Section {
                    ForEach(model.folders) { folder in
                        sidebarDestination(folder.name, symbol: "folder", destination: .library(.folder(folder.id)))
                            .badge(usesLargeSidebar ? 0 : model.counts.folders[folder.id, default: 0])
                            .tag(SidebarDestination.library(.folder(folder.id)))
                            .contextMenu {
                                Button(L10n.rename) {
                                    folderName = folder.name
                                    folderPrompt = .rename(folder)
                                }
                                Button(L10n.deleteFolder, role: .destructive) { deletingFolder = folder }
                            }
                            .accessibilityIdentifier("sidebar-folder")
                    }
                    Button {
                        folderName = ""
                        folderPrompt = .create
                    } label: {
                        Label(L10n.newFolder, systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sidebar-new-folder")
                    // List scroll targets must identify a row, not a child of
                    // a section header. Keep this row even with no folders.
                    .id("folders-section")
                } header: {
                    Text(L10n.folders)
                }
            }
            .listStyle(.sidebar)
            .tint(showsHome ? Theme.accent : .blue)
            .scrollContentBackground(.hidden)
            .background(Theme.sidebar)
            .onChange(of: model.sidebarSelection) { _, selected in
                if selected != nil { dashboardVisible = false }
            }
            .task(id: model.session.changeToken) { await model.reloadSidebar() }
            .navigationDestination(item: $model.homeDocument) { id in
                DocumentWorkspace(initialID: id, session: model.session, tabs: documentTabs)
            }
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
            .navigationTitle(sidebarTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onChange(of: folderScrollRequest) { _, _ in
                proxy.scrollTo("folders-section", anchor: .top)
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
                        // Home appears once in navigation on every platform.
                        .navigationTitle("")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                    } else {
                        LibraryView(model: model)
                    }
                }
                    .navigationDestination(for: ItemID.self) { id in
                        DocumentWorkspace(initialID: id, session: model.session, tabs: documentTabs)
                    }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsHome && model.homeDocument == nil && model.path.isEmpty { compactNavigation }
        }
        .modifier(LibraryPresentations(model: model))
        .focusedSceneValue(\.libraryModel, model)
        #if DEBUG
        .task { await openDebugItemIfRequested() }
        #endif
    }

    private var compactNavigation: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Menu {
                    Button(L10n.homeTitle) { model.sidebarSelection = nil; dashboardVisible = true }
                    Button(L10n.premiumNotes) { model.path = []; model.contentKind = .notes; dashboardVisible = false; model.sidebarSelection = .all }
                        .accessibilityIdentifier("home-notes")
                    Button(L10n.toolsDocuments) { model.path = []; model.contentKind = .documents; dashboardVisible = false; model.sidebarSelection = .all }
                    #if os(iOS)
                    Button(L10n.scan) { model.isShowingScanner = true }.disabled(!DocumentCameraView.isSupported)
                    #endif
                    Button(L10n.folders) { model.sidebarSelection = nil; dashboardVisible = true; folderScrollRequest.toggle() }
                } label: {
                    Label(L10n.sidebarLibrary, systemImage: "line.3.horizontal")
                        .font(.body).frame(maxWidth: .infinity, minHeight: 44)
                }.accessibilityIdentifier("home-navigation-menu")
            } else {
                navigationButtons
            }
        }
        .buttonStyle(.plain).foregroundStyle(Theme.accent)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.surface)
    }

    private var navigationButtons: some View {
        HStack(spacing: 4) {
            Button {
                model.sidebarSelection = nil
                dashboardVisible = true
            } label: {
                tabLabel(L10n.homeTitle, symbol: "house.fill")
                    .background(model.sidebarSelection == nil ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 14))
            }.accessibilityIdentifier("home-tab")
            Button { model.path = []; model.contentKind = .notes; dashboardVisible = false; model.sidebarSelection = .all } label: {
                tabLabel(L10n.premiumNotes, symbol: "pencil.tip")
                    .background(model.sidebarSelection != nil && model.contentKind == .notes ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 14))
            }.accessibilityIdentifier("home-notes")
            Button { model.path = []; model.contentKind = .documents; dashboardVisible = false; model.sidebarSelection = .all } label: {
                tabLabel(L10n.toolsDocuments, symbol: "doc.on.doc")
                    .background(model.sidebarSelection != nil && model.contentKind == .documents ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 14))
            }.accessibilityIdentifier("home-documents")
            #if os(iOS)
            Button { model.isShowingScanner = true } label: {
                tabLabel(L10n.premiumScan, symbol: "doc.viewfinder")
            }.disabled(!DocumentCameraView.isSupported)
                .accessibilityHint(DocumentCameraView.isSupported ? "" : L10n.scanUnsupported)
                .accessibilityIdentifier("library-scan")
            #endif
            Button {
                model.sidebarSelection = nil
                dashboardVisible = true
                folderScrollRequest.toggle()
            } label: { tabLabel(L10n.folders, symbol: "folder") }
                .accessibilityIdentifier("home-folders")
        }
    }

    private var sidebarBinding: Binding<SidebarDestination?> {
        Binding(get: {
            if dashboardVisible && !showsHome { return .home }
            guard let scope = model.sidebarSelection else { return nil }
            if model.contentKind == .notes && scope == .all { return .notes }
            return .library(scope)
        }, set: { selected in
            Task {
            guard await editingGuard.finish?() ?? true else { return }
            switch selected {
            case .home:
                // Reset the library scope as before, so returning to the same
                // scope after Home reloads the correct content.
                model.sidebarSelection = .all
                model.sidebarSelection = nil
                model.path = []
                dashboardVisible = true
            case .notes:
                model.path = []
                model.contentKind = .notes
                dashboardVisible = false
                model.sidebarSelection = .all
            case .library(let scope):
                model.path = []
                dashboardVisible = false
                model.contentKind = scope == .all ? .documents : .all
                model.sidebarSelection = scope
            case nil:
                // Compact navigation clears selection when returning Home.
                model.sidebarSelection = nil
            }
            }
        })
    }

    private func tabLabel(_ title: String, symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.title3)
            Text(title).font(.caption2).fixedSize(horizontal: false, vertical: true)
        }.frame(minWidth: 52, maxWidth: .infinity, minHeight: 44)
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
    private func sidebarDestination(_ title: String, symbol: String, destination: SidebarDestination) -> some View {
        #if os(iOS)
        if showsHome {
            sidebarLabel(title, symbol: symbol)
        } else {
            // Let List own selection and keyboard focus together. A custom row
            // background makes iPadOS draw a separate rectangular focus halo.
            Button {
                sidebarBinding.wrappedValue = destination
            } label: {
                sidebarLabel(title, symbol: symbol)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        #else
        Button {
            sidebarBinding.wrappedValue = destination
        } label: {
            sidebarLabel(title, symbol: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #endif
    }

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
        if let path = UserDefaults.standard.string(forKey: "PaperNestDebugImportFile") {
            await model.importFiles([URL(fileURLWithPath: path)], chooseLocation: true)
            return
        }
        if UserDefaults.standard.string(forKey: "PaperNestDebugScannerImages") != nil { model.isShowingScanner = true }
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
    let showOutline: () -> Void
    /// Opens find in the document. Defaulted so a context built without it still compiles.
    var showFind: () -> Void = {}
    var showGoToPage: () -> Void = {}
    let showTextBox: () -> Void
    let showInsertImage: () -> Void
    var beforeAction: (() async -> Bool)? = nil
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

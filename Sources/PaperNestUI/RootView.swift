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
    /// The wide layouts' Folders screen, reached from the sidebar and from
    /// Home's See All. Like Home it is a destination of its own, not a scope.
    @State private var foldersVisible = false
    /// The phone's Files tab: the same root column as Home, showing the
    /// library's scopes and folders instead of the dashboard.
    @State private var compactFiles = false
    @State private var homeFilePreview: FilePreviewRequest?
    @State private var showFirstProOffer = false
    @AppStorage("PaperNestFirstProOfferHandled") private var proOfferHandled = false
    @AppStorage("PaperNestFirstProOfferPending") private var proOfferPending = false
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #else
    @Environment(\.openSettings) private var openSettings
    #endif

    /// View-only destinations let Home, Notes and Folders participate in native list selection.
    private enum SidebarDestination: Hashable {
        case home
        case notes
        case folders
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
            List(selection: sidebarBinding) {
                if showsHome {
                    if compactFiles {
                        compactFilesRows
                    } else {
                        Section {} header: {
                            dashboard(compact: true).textCase(nil).id("dashboard-top")
                        }
                    }
                } else {
                    wideSidebarRows
                }
            }
            .listStyle(.sidebar)
            // The system tints the selected row's label rather than filling the
            // row, so this has to read on the sidebar in both appearances.
            .tint(Theme.accent)
            .scrollContentBackground(.hidden)
            .background(showsHome ? Theme.libraryBackground : Theme.sidebar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !showsHome {
                    CloudSyncCard(session: model.session, action: showSyncSettings)
                        .padding(.horizontal, 12).padding(.bottom, 12).padding(.top, 6)
                }
            }
            .onChange(of: model.sidebarSelection) { _, selected in
                if selected != nil { dashboardVisible = false; foldersVisible = false }
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
            .navigationSplitViewColumnWidth(min: usesLargeSidebar ? 420 : 200,
                                            ideal: usesLargeSidebar ? 460 : 240)
        } detail: {
            NavigationStack(path: $model.path) {
                Group {
                    if dashboardVisible && !showsHome {
                        ScrollView {
                            dashboard(compact: false).padding(24)
                                .frame(maxWidth: 1400).frame(maxWidth: .infinity)
                        }
                        .background(Theme.libraryBackground)
                        // Home appears once in navigation on every platform.
                        .navigationTitle("")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                    } else if foldersVisible && !showsHome {
                        FoldersView(model: model, open: openFolder, newFolder: promptNewFolder,
                                    rename: promptRename, delete: { deletingFolder = $0 })
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
            // Hidden while the library is selecting, so its own selection bar
            // has the bottom edge to itself.
            if showsHome && model.homeDocument == nil && model.path.isEmpty && !model.isSelectingItems { compactNavigation }
        }
        .modifier(LibraryPresentations(model: model, showHome: showHomeAfterScan))
        .focusedSceneValue(\.libraryModel, model)
        #if DEBUG
        .task { await openDebugItemIfRequested() }
        #endif
    }

    // MARK: - Sidebar rows

    /// iPad and Mac: the brand, then the six places the library has.
    @ViewBuilder private var wideSidebarRows: some View {
        Section {
            sidebarDestination(L10n.homeTitle, symbol: "house.fill", destination: .home)
                .tag(SidebarDestination.home)
                .accessibilityIdentifier("sidebar-home")
            sidebarDestination(L10n.premiumNotes, symbol: "pencil.tip", destination: .notes)
                .tag(SidebarDestination.notes)
                .accessibilityIdentifier("sidebar-notes")
            sidebarDestination(L10n.allDocuments, symbol: "doc.on.doc", destination: .library(.all))
                .tag(SidebarDestination.library(.all))
                .accessibilityIdentifier("sidebar-documents")
            sidebarDestination(L10n.folders, symbol: "folder", destination: .folders)
                .badge(usesLargeSidebar ? 0 : model.folders.count)
                .tag(SidebarDestination.folders)
                .accessibilityIdentifier("sidebar-folders")
            sidebarDestination(L10n.favorites, symbol: "star", destination: .library(.favorites))
                .badge(usesLargeSidebar ? 0 : model.counts.favorites)
                .tag(SidebarDestination.library(.favorites))
                .accessibilityIdentifier("sidebar-favorites")
            sidebarDestination(L10n.recentlyDeleted, symbol: "trash", destination: .library(.recentlyDeleted))
                .badge(usesLargeSidebar ? 0 : model.counts.recentlyDeleted)
                .tag(SidebarDestination.library(.recentlyDeleted))
                .accessibilityIdentifier("sidebar-recently-deleted")
        } header: {
            HStack(spacing: 8) {
                BrandMark.image(size: 26).foregroundStyle(Theme.accent)
                // The mark is hidden from accessibility, so the name is the
                // one element here. Combining the row left the name in the
                // tree a second time.
                Text(verbatim: Brand.displayName).font(.title3.bold()).foregroundStyle(Theme.navy)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sidebar-brand")
            }
            .textCase(nil)
            .padding(.bottom, 8)
        }
    }

    /// The phone's Files tab: every document, the two special scopes, and
    /// the folders with their own management.
    @ViewBuilder private var compactFilesRows: some View {
        Section {
            sidebarDestination(L10n.allDocuments, symbol: "doc.on.doc", destination: .library(.all))
                .tag(SidebarDestination.library(.all))
                .accessibilityIdentifier("files-documents")
            sidebarDestination(L10n.favorites, symbol: "star", destination: .library(.favorites))
                .badge(model.counts.favorites)
                .tag(SidebarDestination.library(.favorites))
                .accessibilityIdentifier("files-favorites")
            sidebarDestination(L10n.recentlyDeleted, symbol: "trash", destination: .library(.recentlyDeleted))
                .badge(model.counts.recentlyDeleted)
                .tag(SidebarDestination.library(.recentlyDeleted))
                .accessibilityIdentifier("files-recently-deleted")
        } header: {
            Text(L10n.homeFiles).font(.largeTitle.bold()).foregroundStyle(Theme.navy)
                .textCase(nil).padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("files-title")
        }
        Section {
            ForEach(model.folders) { folder in
                sidebarDestination(folder.name, symbol: "folder", destination: .library(.folder(folder.id)))
                    .badge(model.counts.folders[folder.id, default: 0])
                    .tag(SidebarDestination.library(.folder(folder.id)))
                    .contextMenu {
                        Button(L10n.rename) { promptRename(folder) }
                        Button(L10n.deleteFolder, role: .destructive) { deletingFolder = folder }
                    }
                    .accessibilityIdentifier("sidebar-folder")
            }
            Button(action: promptNewFolder) {
                Label(L10n.newFolder, systemImage: "folder.badge.plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .accessibilityIdentifier("sidebar-new-folder")
        } header: {
            Text(L10n.folders)
        }
    }

    private func promptNewFolder() {
        folderName = ""
        folderPrompt = .create
    }

    private func promptRename(_ folder: Folder) {
        folderName = folder.name
        folderPrompt = .rename(folder)
    }

    private func openFolder(_ folder: Folder) {
        model.path = []
        model.contentKind = .all
        dashboardVisible = false
        foldersVisible = false
        model.sidebarSelection = .folder(folder.id)
    }

    /// A scan was saved and dealt with: Home, with nothing pushed over it.
    private func showHomeAfterScan() {
        model.path = []
        model.homeDocument = nil
        if showsHome { showCompactHome() } else { sidebarBinding.wrappedValue = .home }
    }

    private func showSyncSettings() {
        #if os(iOS)
        model.isShowingSettings = true
        #else
        openSettings()
        #endif
    }

    // MARK: - The phone's bottom bar

    private func showCompactHome() {
        compactFiles = false
        model.sidebarSelection = nil
        dashboardVisible = true
    }

    private func showCompactNotes() {
        model.path = []
        model.contentKind = .notes
        dashboardVisible = false
        model.sidebarSelection = .all
    }

    private func showCompactFiles() {
        model.path = []
        compactFiles = true
        model.sidebarSelection = nil
        dashboardVisible = true
    }

    private var compactHomeSelected: Bool { model.sidebarSelection == nil && !compactFiles }
    private var compactNotesSelected: Bool { model.sidebarSelection != nil && model.contentKind == .notes }
    private var compactFilesSelected: Bool {
        model.sidebarSelection == nil ? compactFiles : model.contentKind != .notes
    }

    /// Home, Notes, Scan, Files. Scan opens the scanner rather than a place,
    /// so it is never the selected tab.
    private var compactNavigation: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Menu {
                    Button(L10n.homeTitle, action: showCompactHome)
                    Button(L10n.premiumNotes, action: showCompactNotes)
                        .accessibilityIdentifier("home-notes")
                    #if os(iOS)
                    Button(L10n.scan) { model.isShowingScanner = true }.disabled(!DocumentCameraView.isSupported)
                    #endif
                    Button(L10n.homeFiles, action: showCompactFiles)
                        .accessibilityIdentifier("home-files")
                } label: {
                    Label(L10n.sidebarLibrary, systemImage: "line.3.horizontal")
                        .font(.body).frame(maxWidth: .infinity, minHeight: 44)
                }
                .foregroundStyle(Theme.accent)
                .accessibilityIdentifier("home-navigation-menu")
            } else {
                navigationButtons
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.surface)
        .overlay(alignment: .top) { Theme.border.frame(height: 0.5) }
    }

    private var navigationButtons: some View {
        HStack(spacing: 4) {
            Button(action: showCompactHome) {
                tabLabel(L10n.homeTitle, symbol: "house.fill", selected: compactHomeSelected)
            }
            .accessibilityIdentifier("home-tab")
            .accessibilityAddTraits(compactHomeSelected ? .isSelected : [])
            Button(action: showCompactNotes) {
                tabLabel(L10n.premiumNotes, symbol: "pencil.tip", selected: compactNotesSelected)
            }
            .accessibilityIdentifier("home-notes")
            .accessibilityAddTraits(compactNotesSelected ? .isSelected : [])
            #if os(iOS)
            Button { model.isShowingScanner = true } label: {
                tabLabel(L10n.premiumScan, symbol: "doc.viewfinder", selected: false)
            }
            .disabled(!DocumentCameraView.isSupported)
            .accessibilityHint(DocumentCameraView.isSupported ? "" : L10n.scanUnsupported)
            .accessibilityIdentifier("library-scan")
            #endif
            Button(action: showCompactFiles) {
                tabLabel(L10n.homeFiles, symbol: "folder", selected: compactFilesSelected)
            }
            .accessibilityIdentifier("home-files")
            .accessibilityAddTraits(compactFilesSelected ? .isSelected : [])
        }
    }

    private var sidebarBinding: Binding<SidebarDestination?> {
        Binding(get: {
            if !showsHome {
                if dashboardVisible { return .home }
                if foldersVisible { return .folders }
            }
            guard let scope = model.sidebarSelection else { return nil }
            // The wide sidebar has one Folders row, which stays lit while a
            // folder opened from it is showing.
            if !showsHome, case .folder(.some) = scope { return .folders }
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
                foldersVisible = false
                dashboardVisible = true
            case .folders:
                // The same reset as Home, so opening the folder that was
                // showing before reloads it.
                model.sidebarSelection = .all
                model.sidebarSelection = nil
                model.path = []
                dashboardVisible = false
                foldersVisible = true
            case .notes:
                model.path = []
                model.contentKind = .notes
                dashboardVisible = false
                foldersVisible = false
                model.sidebarSelection = .all
            case .library(let scope):
                model.path = []
                dashboardVisible = false
                foldersVisible = false
                model.contentKind = scope == .all ? .documents : .all
                model.sidebarSelection = scope
            case nil:
                // Compact navigation clears selection when returning Home.
                model.sidebarSelection = nil
            }
            }
        })
    }

    private func tabLabel(_ title: String, symbol: String, selected: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.title3)
            Text(title).font(.caption2.weight(selected ? .semibold : .regular))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(selected ? Theme.accent : Theme.secondaryText)
        .frame(minWidth: 52, maxWidth: .infinity, minHeight: 48)
        .background(selected ? Theme.lavender : .clear, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
    }

    private func dashboard(compact: Bool) -> some View {
        DashboardView(model: model, compact: compact, openFile: { summary in
            homeFilePreview = FilePreviewRequest(summary: summary)
        }, showLibrary: {
            dashboardVisible = false
            model.sidebarSelection = .all
        }, showFolders: {
            sidebarBinding.wrappedValue = .folders
        }, openFolder: openFolder, newFolder: promptNewFolder,
           renameFolder: promptRename, deleteFolder: { deletingFolder = $0 })
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

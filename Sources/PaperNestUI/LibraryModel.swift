import Foundation
import Observation
import PaperNestCore
import PaperNestImport
import PaperNestStore

/// State for one library window: which scope is shown, search, and the
/// import flows started from it.
@MainActor @Observable
public final class LibraryModel {
    public let session: LibrarySession
    /// What the library grid shows.
    private(set) var scope: LibraryStore.Scope = .all
    /// The sidebar's selection. On iPhone, NavigationSplitView sets this to
    /// nil when the user goes back to the sidebar, and a non-nil value is
    /// what shows the library again, so it must be allowed to be nil.
    /// `scope` keeps the last real choice for loading data.
    var sidebarSelection: LibraryStore.Scope? = .all {
        didSet {
            guard let selected = sidebarSelection, selected != scope else { return }
            scope = selected
            path = []
        }
    }
    var path: [ItemID] = []
    private(set) var items: [LibraryStore.ItemSummary] = []
    /// Folders for the sidebar, by name.
    private(set) var folders: [Folder] = []
    /// Item counts shown next to each sidebar entry.
    private(set) var counts = LibraryStore.ScopeCounts()
    /// Applies to every scope except Recently Deleted (always newest
    /// deletion first). Remembered across launches.
    var sortOrder: LibrarySort = LibrarySort(rawValue: UserDefaults.standard.string(forKey: "librarySort") ?? "") ?? .dateModified {
        didSet {
            UserDefaults.standard.set(sortOrder.rawValue, forKey: "librarySort")
            items = sorted(items)
        }
    }
    private(set) var hasLoaded = false
    @ObservationIgnored private var reloadGeneration = 0
    var contentKind: LibraryContentKind = .all
    var searchText = ""
    private(set) var isImporting = false
    var presentedError: PresentedError?
    /// A Pro feature that was just refused. The library screen shows the paywall for it.
    var proPaywall: ProFeature?
    /// PDFs waiting for a password, shown one at a time.
    private(set) var passwordQueue: [PendingPassword] = []
    var isShowingFileImporter = false
    var isShowingScanner = false
    var isShowingSettings = false
    var isShowingTools = false
    /// The library is in selection mode. The phone's bottom bar steps aside
    /// for it: the selection bar sits at the same edge and was drawn
    /// underneath, where its Select All and actions menu could not be reached.
    var isSelectingItems = false
    /// The newest documents, for the iPhone home's Recent row.
    private(set) var dashboardItems: [LibraryStore.ItemSummary] = []
    /// Bytes of the originals behind the documents Home lists, from the store.
    /// A notebook of drawn pages has none and is absent.
    private(set) var dashboardSizes: [ItemID: Int64] = [:]
    /// How many recent documents Home can show; sizes are read for no more.
    static let homeRecentLimit = 8
    private(set) var recentItems: [LibraryStore.ItemSummary] = []

    struct PendingPassword: Identifiable {
        let id = UUID()
        let data: Data
        let filename: String
        /// Set after a wrong attempt so the prompt can say so.
        var lastAttemptFailed = false
        var destination: Destination
    }

    /// Where an import goes once its password is known.
    enum Destination {
        case newItem(folder: FolderID?, openAfterSaving: Bool)
        case pages(into: ItemID, after: PageID?)
        /// Validated pages handed to an action, e.g. replacing a page.
        case prepared(@MainActor (DocumentImporter.Prepared) async -> Void)
    }

    /// `startsAtHome`: iPhone opens on the home (the sidebar column) rather
    /// than on All Documents.
    public init(session: LibrarySession, startsAtHome: Bool = false) {
        self.session = session
        usesCompactNavigation = startsAtHome
        if startsAtHome { sidebarSelection = nil }
    }

    /// Opens a document from anywhere: over the iPhone home when that is
    /// showing (no selection), otherwise over All Documents.
    func open(_ id: ItemID) {
        if sidebarSelection == nil {
            if usesCompactNavigation { homeDocument = id }
            else { path = [id] }
        } else if case .folder(.some) = sidebarSelection {
            // Opened from a folder, such as a note just made in it: open over
            // the folder, so Back returns there. Switching to All Documents
            // first also lost the push on iPad.
            path = [id]
        } else {
            sidebarSelection = .all
            path = [id]
        }
    }

    /// A document pushed directly over the iPhone home (Recent row).
    /// Setting the split view's selection and the library's path together
    /// loses the path on iPhone, so the home pushes the document itself.
    var usesCompactNavigation = false
    var homeDocument: ItemID?

    var environment: AppEnvironment? { session.environment }

    // MARK: - Loading

    func reload() async {
        guard let env = environment, !Task.isCancelled else { return }
        reloadGeneration &+= 1
        let generation = reloadGeneration
        let requestedScope = scope
        let requestedSearch = searchText
        let requestedKind = contentKind
        do {
            let query = requestedSearch.trimmingCharacters(in: .whitespacesAndNewlines)
            var summaries = try await env.store.items(in: requestedScope)
            if !query.isEmpty, requestedScope != .recentlyDeleted {
                let matches = Set(try await env.store.search(query))
                summaries = summaries.filter { matches.contains($0.id) }
            }
            summaries = summaries.filter { requestedKind.includes($0.item.kind) }
            let loadedFolders = try await env.store.folders()
            let loadedCounts = try await env.store.scopeCounts()
            // A canceled or older read must not publish rows that would
            // prune the user's selection in a newer search or scope.
            guard !Task.isCancelled, generation == reloadGeneration,
                  requestedScope == scope, requestedSearch == searchText, requestedKind == contentKind else { return }
            items = sorted(summaries)
            folders = loadedFolders
            counts = loadedCounts
            if case .folder(let id?) = scope, !folders.contains(where: { $0.id == id }) {
                stopShowingFolder()
            }
            hasLoaded = true
        } catch {
            guard !Task.isCancelled, generation == reloadGeneration,
                  requestedScope == scope, requestedSearch == searchText, requestedKind == contentKind else { return }
            presentedError = PresentedError(title: L10n.genericErrorTitle, message: L10n.libraryOpenFailed)
        }
    }

    struct ImportLocationRequest: Identifiable { let id = UUID() }
    enum ImportLocationChoice {
        case home
        case folder(FolderID)
        case newFolder(String)
    }
    var importLocationRequest: ImportLocationRequest?
    var importLocationChoice: ImportLocationChoice?
    var importedFilePreview: FilePreviewRequest?
    @ObservationIgnored private var locationContinuation: CheckedContinuation<ImportLocationChoice?, Never>?

    /// Resume only after the destination sheet dismisses, before navigation.
    func finishImportLocation() {
        let continuation = locationContinuation
        locationContinuation = nil
        importLocationRequest = nil
        let choice = importLocationChoice
        importLocationChoice = nil
        continuation?.resume(returning: choice)
    }

    private func chooseImportLocation() async -> ImportLocationChoice? {
        await reloadSidebar()
        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            importLocationChoice = nil
            importLocationRequest = ImportLocationRequest()
        }
    }

    private func folderForImport(_ choice: ImportLocationChoice) async throws -> FolderID? {
        switch choice {
        case .home: return nil
        case .folder(let id): return id
        case .newFolder(let name):
            guard let env = environment else { throw CocoaError(.fileWriteUnknown) }
            let folder = try await env.store.createFolder(named: name)
            session.didChange()
            return folder.id
        }
    }

    private func openImported(_ id: ItemID) async {
        guard let env = environment else { return }
        do {
            if let summary = try await env.store.items(in: .all).first(where: { $0.id == id }), summary.file != nil {
                importedFilePreview = FilePreviewRequest(summary: summary)
            } else {
                open(id)
            }
        } catch { presentedError = .saveFailed() }
    }

    // MARK: - Import

    /// A Word or Excel file laid out as pages, on iPhone and iPad where WebKit
    /// can show it; nil keeps it a file. The Mac reads Word in the importer
    /// itself, and has no way to lay out Excel.
    private func importOfficeDocument(_ url: URL, folderID: FolderID?) async -> PaperNestCore.LibraryItem? {
        #if os(iOS)
        guard let env = environment, let pdf = await OfficeDocumentRenderer.pdf(for: url) else { return nil }
        let name = url.deletingPathExtension().lastPathComponent + ".pdf"
        return try? await env.importer.importItem(.data(pdf, name: name), folderID: folderID)
        #else
        return nil
        #endif
    }

    /// Imports each file as its own document. Failures are collected and
    /// reported together; password-protected PDFs are queued for a prompt.
    func importFiles(_ urls: [URL], into target: ItemID? = nil, after pageID: PageID? = nil, chooseLocation: Bool = false) async {
        guard let env = environment, !urls.isEmpty, !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        // Keep security-scoped access alive while the destination sheet is open.
        let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
        var folderID = currentFolderID
        if chooseLocation && target == nil {
            guard let choice = await chooseImportLocation() else { return }
            do { folderID = try await folderForImport(choice) }
            catch { presentedError = .saveFailed(); return }
        }
        var firstImported: ItemID?
        var failures: [ImportError] = []
        var insertAfter = pageID
        for url in urls {
            do {
                if let target {
                    let added = try await env.importer.insertPages(from: .file(url), into: target, after: insertAfter)
                    insertAfter = added.last?.id ?? insertAfter
                } else {
                    do {
                        let item = try await env.importer.importItem(.file(url), folderID: folderID)
                        if firstImported == nil { firstImported = item.id }
                    } catch ImportError.unsupportedType {
                        // Word and Excel become pages where the system can lay
                        // them out; anything else is kept as the file it is
                        // rather than refused.
                        let item: PaperNestCore.LibraryItem
                        if let pages = await importOfficeDocument(url, folderID: folderID) {
                            item = pages
                        } else {
                            item = try await FileItemImporter(store: env.store).importFile(at: url, into: folderID)
                        }
                        if firstImported == nil { firstImported = item.id }
                    }
                }
            } catch ImportError.passwordRequired(let filename) {
                if let data = try? env.importer.loadData(.file(url)) {
                    let destination: Destination = target.map { .pages(into: $0, after: insertAfter) } ?? .newItem(folder: folderID, openAfterSaving: chooseLocation)
                    passwordQueue.append(PendingPassword(data: data, filename: filename, destination: destination))
                } else {
                    failures.append(.unreadable(filename: filename))
                }
            } catch let error as ImportError {
                failures.append(error)
            } catch {
                failures.append(.unreadable(filename: url.lastPathComponent))
            }
        }
        session.didChange()
        report(failures)
        if chooseLocation, let firstImported { await openImported(firstImported) }
    }

    /// Imports in-memory image data (paste, camera) as one new document.
    func importImages(_ images: [Data], name: String, openAfterSaving: Bool = false, chooseLocation: Bool = false) async {
        guard let env = environment, !images.isEmpty, !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        var folderID = currentFolderID
        if chooseLocation {
            guard let choice = await chooseImportLocation() else { return }
            do { folderID = try await folderForImport(choice) }
            catch { presentedError = .saveFailed(); return }
        }
        do {
            let imported = try await env.importer.importScan(images: images, name: name, folderID: folderID)
            if openAfterSaving || chooseLocation { open(imported.id) }
            session.didChange()
        } catch let error as ImportError {
            report([error])
        } catch {
            presentedError = .saveFailed()
        }
    }

    /// A scan that has just been saved and whose export screen is due.
    struct SavedScan: Identifiable, Equatable {
        let id: ItemID
        let name: String
    }

    /// Set once a scan is in the library. It presents the export screen for
    /// that scan; closing the screen clears it and returns to Home.
    var savedScan: SavedScan?

    /// Saves a scan as one new document and leaves it closed. A scan is paper
    /// someone wanted kept, so it does not open in the editor; its export
    /// screen opens instead. `savedScan` is set only after the store has the
    /// document, so Export never opens for a scan that is not saved.
    func importScan(_ images: [Data], name: String) async {
        guard let env = environment, !images.isEmpty, !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        guard let choice = await chooseImportLocation() else { return }
        let folderID: FolderID?
        do { folderID = try await folderForImport(choice) }
        catch { presentedError = .saveFailed(); return }
        do {
            let imported = try await env.importer.importScan(images: images, name: name, folderID: folderID)
            session.didChange()
            savedScan = SavedScan(id: imported.id, name: imported.name)
        } catch let error as ImportError {
            report([error])
        } catch {
            presentedError = .saveFailed()
        }
    }

    /// Photos picked from the system library, each becoming its own
    /// document — a photo of a receipt is a document, not a page of some
    /// other one. Failures are reported per photo and the rest still land.
    func importPhotos(_ photos: [(data: Data, name: String)], chooseLocation: Bool = false) async {
        guard let env = environment, !photos.isEmpty, !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        var folderID = currentFolderID
        if chooseLocation {
            guard let choice = await chooseImportLocation() else { return }
            do { folderID = try await folderForImport(choice) }
            catch { presentedError = .saveFailed(); return }
        }
        var firstImported: ItemID?
        var failures: [ImportError] = []
        for photo in photos {
            do {
                let item = try await env.importer.importItem(.data(photo.data, name: photo.name), folderID: folderID)
                if firstImported == nil { firstImported = item.id }
            } catch let error as ImportError {
                failures.append(error)
            } catch {
                failures.append(.unreadable(filename: photo.name))
            }
        }
        session.didChange()
        await reload()
        report(failures)
        if chooseLocation, let firstImported { await openImported(firstImported) }
    }

    func submitPassword(_ password: String, for pending: PendingPassword) async {
        guard let env = environment else { return }
        passwordQueue.removeAll { $0.id == pending.id }
        let source = DocumentImporter.Source.data(pending.data, name: pending.filename)
        do {
            switch pending.destination {
            case .newItem(let folder, let openAfterSaving):
                let item = try await env.importer.importItem(source, password: password, folderID: folder)
                if openAfterSaving { await openImported(item.id) }
            case .pages(let target, let after):
                try await env.importer.insertPages(from: source, password: password, into: target, after: after)
            case .prepared(let use):
                await use(try await env.importer.prepareInBackground(source, password: password))
            }
            session.didChange()
        } catch ImportError.incorrectPassword, ImportError.passwordRequired {
            var retry = pending
            retry.lastAttemptFailed = true
            passwordQueue.insert(retry, at: 0)
        } catch let error as ImportError {
            report([error])
        } catch {
            presentedError = .saveFailed()
        }
    }

    /// Validates and stores originals without creating pages, then hands
    /// them to `use` (rescan, replace). Password prompts and errors are
    /// handled like any other import.
    func prepareFile(_ url: URL, then use: @escaping @MainActor (DocumentImporter.Prepared) async -> Void) async {
        guard let env = environment else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            await use(try await env.importer.prepareInBackground(.file(url)))
        } catch ImportError.passwordRequired(let filename) {
            if let data = try? env.importer.loadData(.file(url)) {
                passwordQueue.append(PendingPassword(data: data, filename: filename, destination: .prepared(use)))
            } else {
                report([.unreadable(filename: filename)])
            }
        } catch let error as ImportError {
            report([error])
        } catch {
            presentedError = .saveFailed()
        }
    }

    /// Camera pages for an existing document (add or rescan).
    func prepareImages(_ images: [Data], name: String, then use: @escaping @MainActor (DocumentImporter.Prepared) async -> Void) async {
        guard let env = environment, !images.isEmpty else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            await use(try await env.importer.prepareAll(images.enumerated().map { .data($1, name: "\(name) \($0 + 1)") }))
        } catch let error as ImportError {
            report([error])
        } catch {
            presentedError = .saveFailed()
        }
    }

    func cancelPassword(_ pending: PendingPassword) {
        passwordQueue.removeAll { $0.id == pending.id }
    }

    /// The system file picker itself failed (not a cancel, which reports
    /// nothing): say so instead of silently doing nothing.
    func reportPickerFailure() {
        presentedError = PresentedError(title: L10n.genericErrorTitle, message: L10n.importUnreadable)
    }

    private func report(_ failures: [ImportError]) {
        guard !failures.isEmpty else { return }
        if failures.count == 1, let only = failures.first {
            presentedError = PresentedError(title: L10n.importErrorTitle(only.filename), message: only.localizedReason)
        } else {
            presentedError = PresentedError(
                title: L10n.importErrorsTitle,
                message: failures.map { L10n.importErrorLine($0.filename, $0.localizedReason) }.joined(separator: "\n")
            )
        }
    }

    private func sorted(_ summaries: [LibraryStore.ItemSummary]) -> [LibraryStore.ItemSummary] {
        guard scope != .recentlyDeleted else { return summaries }
        return switch sortOrder {
        case .dateModified: summaries   // the store's order
        case .dateAdded: summaries.sorted { $0.item.createdAt > $1.item.createdAt }
        case .name: summaries.sorted { $0.item.name.localizedStandardCompare($1.item.name) == .orderedAscending }
        }
    }

    /// The name of what the library shows.
    var scopeTitle: String {
        switch scope {
        case .all, .folder(nil): L10n.allDocuments
        case .favorites: L10n.favorites
        case .recentlyDeleted: L10n.recentlyDeleted
        case .folder(let id?): folders.first { $0.id == id }?.name ?? L10n.allDocuments
        }
    }

    /// Creates the notebook and its first A4 page together before publishing.
    func createNotebook(named name: String, template: PageTemplate) async throws -> ItemID {
        guard let env = environment else { throw CocoaError(.fileReadUnknown) }
        let item = try await SubscriptionStore.shared.withNotebookAllowance(in: env.store, additional: 1) {
            try await env.store.createItem(kind: .notebook, name: name,
            folderID: currentFolderID,
            pages: [.init(sourceSize: CGSize(width: 595.28, height: 841.89), content: .template(template))],
            assets: [])
        }
        session.didChange()
        await reload()
        return item.id
    }

    // MARK: - Folders

    /// New documents go into the folder being shown; from the iPhone home
    /// (no selection) they go to the library root.
    var currentFolderID: FolderID? {
        guard sidebarSelection != nil, case .folder(let id) = scope else { return nil }
        return id
    }

    /// Refreshes only what the sidebar shows.
    func reloadSidebar() async {
        guard let env = environment else { return }
        folders = (try? await env.store.folders()) ?? folders
        counts = (try? await env.store.scopeCounts()) ?? counts
        if let all = try? await env.store.items(in: .all) {
            dashboardItems = all.sorted { $0.item.modifiedAt > $1.item.modifiedAt }
            recentItems = Array(dashboardItems.prefix(10))
            var sizes: [ItemID: Int64] = [:]
            for summary in dashboardItems.prefix(Self.homeRecentLimit) {
                if let bytes = try? await env.store.originalByteCount(of: summary.id), bytes > 0 { sizes[summary.id] = bytes }
            }
            dashboardSizes = sizes
        }
    }

    /// Creates a folder and shows it.
    func createFolder(named name: String) async {
        guard let env = environment else { return }
        do {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let folder = try await env.store.createFolder(named: trimmed.isEmpty ? L10n.newFolder : trimmed)
            folders = try await env.store.folders()
            sidebarSelection = .folder(folder.id)
            session.didChange()
        } catch {
            presentedError = .saveFailed()
        }
    }

    func renameFolder(_ id: FolderID, to name: String) async {
        await mutate { try await $0.store.renameFolder(id, to: name) }
    }

    /// Deletes the folder only; what was in it moves up (see `LibraryStore.deleteFolder`).
    func deleteFolder(_ id: FolderID) async {
        if scope == .folder(id) { stopShowingFolder() }
        await mutate { try await $0.store.deleteFolder(id) }
    }

    /// Falls back to All Documents. On iPhone, when the sidebar is the
    /// screen showing (selection nil), this doesn't push the library.
    private func stopShowingFolder() {
        if sidebarSelection == nil {
            scope = .all
            path = []
        } else {
            sidebarSelection = .all
        }
    }

    func move(_ ids: [ItemID], to folderID: FolderID?) async {
        await mutate { try await $0.store.move(ids, to: folderID) }
    }

    // MARK: - Item actions

    func duplicate(_ ids: [ItemID]) async -> Bool {
        guard let env = environment else { return false }
        do {
            let selected = Set(ids)
            let additional = try await env.store.items(in: .all).filter { selected.contains($0.id) && $0.item.kind == .notebook }.count
            _ = try await SubscriptionStore.shared.withNotebookAllowance(in: env.store, additional: additional) {
                try await env.store.duplicateItems(Array(selected))
            }
            session.didChange()
            await reload()
            return true
        } catch let error as ProAccessError {
            proPaywall = error.feature
            return false
        } catch {
            presentedError = .saveFailed()
            return false
        }
    }

    /// One document per live page, named after the source. The source is kept.
    func split(_ summary: LibraryStore.ItemSummary) async -> Bool {
        guard SubscriptionStore.shared.allows(.pageTools) else {
            proPaywall = .pageTools
            return false
        }
        guard let env = environment else { return false }
        do {
            let name = summary.item.name
            _ = try await env.store.splitItem(summary.id) { page, _ in L10n.splitPageName(name, page) }
            session.didChange()
            await reload()
            return true
        } catch {
            presentedError = .saveFailed()
            return false
        }
    }

    /// Unpacks an archive file item into a folder of its own. The archive
    /// is untrusted: anything that escapes the destination, is a symbolic
    /// link, is encrypted or expands past the limits is refused outright,
    /// and nothing is added to the library in that case.
    func extractArchive(_ summary: LibraryStore.ItemSummary) async -> Bool {
        guard let env = environment, let payload = summary.file else { return false }
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestExtract-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        do {
            let data = try await env.store.assetData(payload.assetID).0
            let reader = try ZipReader(data: data)
            let files = try reader.extract(to: scratch)
            guard !files.isEmpty else { throw ZipReader.ArchiveError.notAnArchive }
            let folder = try await env.store.createFolder(named: summary.item.name)
            for url in files.sorted(by: { $0.path < $1.path }) {
                do {
                    _ = try await env.importer.importItem(.file(url), folderID: folder.id)
                } catch {
                    // Word and Excel become pages where they can; anything we
                    // cannot make pages from is still kept.
                    if await importOfficeDocument(url, folderID: folder.id) == nil {
                        _ = try? await FileItemImporter(store: env.store).importFile(at: url, into: folder.id)
                    }
                }
            }
            session.didChange()
            await reload()
            sidebarSelection = .folder(folder.id)
            return true
        } catch {
            presentedError = PresentedError(title: L10n.genericErrorTitle, message: L10n.extractArchiveFailed)
            return false
        }
    }

    func setColorLabel(_ color: ItemColor?, for ids: [ItemID]) async {
        await mutate { try await $0.store.setColorLabel(color, for: ids) }
    }

    func rename(_ id: ItemID, to name: String) async {
        await mutate { try await $0.store.rename(id, to: name) }
    }

    func setFavorite(_ id: ItemID, _ isFavorite: Bool) async {
        await mutate { try await $0.store.setFavorite(id, isFavorite) }
    }

    func moveToRecentlyDeleted(_ ids: [ItemID]) async {
        path.removeAll { ids.contains($0) }
        await mutate { try await $0.store.moveToRecentlyDeleted(ids) }
    }

    func recover(_ ids: [ItemID]) async {
        await mutate { try await $0.store.restore(ids) }
    }

    func deletePermanently(_ ids: [ItemID]) async {
        await mutate { try await $0.store.deletePermanently(ids) }
    }

    /// Runs a store change; the UI reflects it only after it has committed.
    private func mutate(_ change: (AppEnvironment) async throws -> some Any) async {
        guard let env = environment else { return }
        do {
            _ = try await change(env)
            session.didChange()
        } catch {
            presentedError = .saveFailed()
        }
    }
}

enum LibrarySort: String, CaseIterable {
    case dateModified, dateAdded, name
}

/// A presentation filter; never a second store or persisted collection.
enum LibraryContentKind: String {
    case all, notes, documents
    func includes(_ kind: ItemKind) -> Bool {
        switch self {
        case .all: true
        case .notes: kind == .notebook
        case .documents: kind != .notebook
        }
    }
}

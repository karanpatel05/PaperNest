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
    var searchText = ""
    private(set) var isImporting = false
    var presentedError: PresentedError?
    /// PDFs waiting for a password, shown one at a time.
    private(set) var passwordQueue: [PendingPassword] = []
    var isShowingFileImporter = false
    var isShowingScanner = false
    var isShowingSettings = false
    /// The newest documents, for the iPhone home's Recent row.
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
        case newItem(folder: FolderID?)
        case pages(into: ItemID, after: PageID?)
        /// Validated pages handed to an action, e.g. replacing a page.
        case prepared(@MainActor (DocumentImporter.Prepared) async -> Void)
    }

    /// `startsAtHome`: iPhone opens on the home (the sidebar column) rather
    /// than on All Documents.
    public init(session: LibrarySession, startsAtHome: Bool = false) {
        self.session = session
        if startsAtHome { sidebarSelection = nil }
    }

    /// Opens a document from anywhere: over the iPhone home when that is
    /// showing (no selection), otherwise over All Documents.
    func open(_ id: ItemID) {
        if sidebarSelection == nil {
            homeDocument = id
        } else {
            sidebarSelection = .all
            path = [id]
        }
    }

    /// A document pushed directly over the iPhone home (Recent row).
    /// Setting the split view's selection and the library's path together
    /// loses the path on iPhone, so the home pushes the document itself.
    var homeDocument: ItemID?

    var environment: AppEnvironment? { session.environment }

    // MARK: - Loading

    func reload() async {
        guard let env = environment else { return }
        do {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            var summaries = try await env.store.items(in: scope)
            if !query.isEmpty, scope != .recentlyDeleted {
                let matches = Set(try await env.store.search(query))
                summaries = summaries.filter { matches.contains($0.id) }
            }
            items = sorted(summaries)
            folders = try await env.store.folders()
            counts = try await env.store.scopeCounts()
            if case .folder(let id?) = scope, !folders.contains(where: { $0.id == id }) {
                stopShowingFolder()
            }
            hasLoaded = true
        } catch {
            presentedError = PresentedError(title: L10n.genericErrorTitle, message: L10n.libraryOpenFailed)
        }
    }

    // MARK: - Import

    /// Imports each file as its own document. Failures are collected and
    /// reported together; password-protected PDFs are queued for a prompt.
    func importFiles(_ urls: [URL], into target: ItemID? = nil, after pageID: PageID? = nil) async {
        guard let env = environment, !urls.isEmpty else { return }
        isImporting = true
        defer { isImporting = false }
        var failures: [ImportError] = []
        var insertAfter = pageID
        for url in urls {
            do {
                if let target {
                    let added = try await env.importer.insertPages(from: .file(url), into: target, after: insertAfter)
                    insertAfter = added.last?.id ?? insertAfter
                } else {
                    _ = try await env.importer.importItem(.file(url), folderID: currentFolderID)
                }
            } catch ImportError.passwordRequired(let filename) {
                if let data = try? env.importer.loadData(.file(url)) {
                    let destination: Destination = target.map { .pages(into: $0, after: insertAfter) } ?? .newItem(folder: currentFolderID)
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
    }

    /// Imports in-memory image data (paste, camera) as one new document.
    func importImages(_ images: [Data], name: String) async {
        guard let env = environment, !images.isEmpty else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            _ = try await env.importer.importScan(images: images, name: name, folderID: currentFolderID)
            session.didChange()
        } catch let error as ImportError {
            report([error])
        } catch {
            presentedError = .saveFailed()
        }
    }

    func submitPassword(_ password: String, for pending: PendingPassword) async {
        guard let env = environment else { return }
        passwordQueue.removeAll { $0.id == pending.id }
        let source = DocumentImporter.Source.data(pending.data, name: pending.filename)
        do {
            switch pending.destination {
            case .newItem(let folder):
                _ = try await env.importer.importItem(source, password: password, folderID: folder)
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
        if let all = try? await env.store.items(in: .all) { recentItems = Array(all.prefix(10)) }
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

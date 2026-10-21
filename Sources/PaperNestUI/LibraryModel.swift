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
    var scope: LibraryStore.Scope = .all
    var path: [ItemID] = []
    private(set) var items: [LibraryStore.ItemSummary] = []
    private(set) var hasLoaded = false
    var searchText = ""
    private(set) var isImporting = false
    var presentedError: PresentedError?
    /// PDFs waiting for a password, shown one at a time.
    private(set) var passwordQueue: [PendingPassword] = []
    var isShowingFileImporter = false

    struct PendingPassword: Identifiable {
        let id = UUID()
        let data: Data
        let filename: String
        /// Set after a wrong attempt so the prompt can say so.
        var lastAttemptFailed = false
        /// When non-nil, pages are added to this item instead of a new one.
        var targetItem: ItemID?
    }

    public init(session: LibrarySession) {
        self.session = session
    }

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
            items = summaries
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
                    _ = try await env.importer.importItem(.file(url))
                }
            } catch ImportError.passwordRequired(let filename) {
                if let data = try? env.importer.loadData(.file(url)) {
                    passwordQueue.append(PendingPassword(data: data, filename: filename, targetItem: target))
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
            _ = try await env.importer.importScan(images: images, name: name)
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
            if let target = pending.targetItem {
                try await env.importer.insertPages(from: source, password: password, into: target, after: nil)
            } else {
                _ = try await env.importer.importItem(source, password: password)
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

    func cancelPassword(_ pending: PendingPassword) {
        passwordQueue.removeAll { $0.id == pending.id }
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

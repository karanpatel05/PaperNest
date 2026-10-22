import Foundation
import Observation
import PaperNestCore
import PaperNestExport
import PaperNestImport
import PaperNestRender
import PaperNestStore

/// The services one library needs, created together.
public struct AppEnvironment: Sendable {
    public let store: LibraryStore
    public let importer: DocumentImporter
    public let renderer: PageRenderer
    public let exporter: Exporter

    public init(libraryURL: URL) throws {
        store = try LibraryStore(directory: libraryURL)
        importer = DocumentImporter(store: store)
        renderer = PageRenderer(store: store)
        exporter = Exporter(renderer: renderer)
    }

    /// `~/Library/Application Support/PaperNest/Library` (inside the app
    /// container when sandboxed). Debug builds accept
    /// `-PaperNestLibraryPath <dir>` so UI checks never touch real data.
    public static func defaultLibraryURL() throws -> URL {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "PaperNestLibraryPath"), !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        #endif
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return support.appendingPathComponent(Brand.storageDirectoryName, isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
    }
}

/// One per app process: opens the library once and tells every window when
/// the library changed so each can reload what it shows.
@MainActor @Observable
public final class LibrarySession {
    public enum State {
        case loading
        case ready(AppEnvironment)
        case failed(title: String, message: String)
    }

    public private(set) var state: State = .loading
    /// Incremented after every committed change.
    public private(set) var changeToken = 0
    let thumbnails = ThumbnailCache()
    private let libraryURL: URL?

    /// `libraryURL` overrides the default location (used by tests).
    public init(libraryURL: URL? = nil) {
        self.libraryURL = libraryURL
    }

    public var environment: AppEnvironment? {
        if case .ready(let env) = state { return env }
        return nil
    }

    public func bootstrap() async {
        guard case .loading = state else { return }
        do {
            let url = try libraryURL ?? AppEnvironment.defaultLibraryURL()
            let env = try await Task.detached(priority: .userInitiated) { () throws -> AppEnvironment in
                let env = try AppEnvironment(libraryURL: url)
                // Housekeeping after a previous run: pages deleted last
                // session (their undo is gone), expired Recently Deleted
                // items, then originals nothing references any more.
                try await env.store.purgeDeletedPages()
                try await env.store.purgeReplacedPageContent()
                try await env.store.purgeExpiredDeletions()
                try await env.store.sweepOrphanAssets()
                return env
            }.value
            state = .ready(env)
        } catch StoreError.newerSchema {
            state = .failed(title: L10n.libraryErrorTitle, message: L10n.libraryNewer)
        } catch {
            state = .failed(title: L10n.libraryErrorTitle, message: L10n.libraryOpenFailed)
        }
    }

    public func didChange() {
        changeToken &+= 1
    }
}

/// An error ready to show in an alert.
struct PresentedError: Identifiable {
    let id = UUID()
    var title: String
    var message: String

    static func saveFailed() -> PresentedError {
        PresentedError(title: L10n.genericErrorTitle, message: L10n.saveFailed)
    }
}

extension ImportError {
    var localizedReason: String {
        switch self {
        case .unsupportedType: L10n.importUnsupported
        case .unreadable: L10n.importUnreadable
        case .damaged: L10n.importDamaged
        case .empty: L10n.importEmpty
        case .passwordRequired, .incorrectPassword: L10n.importIncorrectPassword
        case .protectedPDFUnsupported: L10n.importProtectedUnsupported
        case .restrictedPDF: L10n.importRestricted
        case .tooLarge: L10n.importTooLarge
        }
    }
}

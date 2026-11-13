import Foundation
import PaperNestCore
import PaperNestStore

/// Whether iCloud can be used right now, and as whom.
public enum CloudAccountState: Sendable, Equatable {
    /// Signed in. `id` is CloudKit's opaque name for the account; it is
    /// compared, never shown.
    case available(id: String)
    case noAccount
    /// Parental controls or device management forbid iCloud here.
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine

    public var accountID: String? {
        if case .available(let id) = self { return id }
        return nil
    }
}

/// Why sync stopped making progress, in terms a person can act on.
public enum SyncFailure: Sendable, Equatable {
    case quotaExceeded
    /// PaperNest's data was deleted from iCloud, here or on another device.
    case cloudDataDeleted
    case other(String)
}

public enum SyncBackendEvent: Sendable {
    /// A fetch or send started or stopped.
    case activity(isTransferring: Bool)
    /// Changes from the server were written to the library.
    case applied(SyncApplyReport)
    /// The server answered a send; the pending count has moved.
    case sent
    /// A fetch ran to the end: what the server had is now here.
    case fetchCompleted
    case accountChanged
    case failure(SyncFailure)
    /// The cause of an earlier failure is gone (a send went through).
    case recovered
}

/// Moves original files to and from iCloud, one at a time, by their SHA-256.
public protocol BlobTransport: Sendable {
    func exists(_ sha256: String) async throws -> Bool
    func upload(_ sha256: String, from fileURL: URL, byteCount: Int64) async throws
    /// A temporary file holding the bytes, or nil if iCloud does not have
    /// them. The caller verifies the hash; this only fetches.
    func download(_ sha256: String) async throws -> URL?
    /// Deleting something already absent is success.
    func delete(_ sha256: String) async throws
}

public enum BlobTransportError: Error, Equatable, Sendable {
    case quotaExceeded
    /// Network, account or service trouble: stop this pass and try later.
    case unavailable
    case other(String)
}

/// One iCloud account's records and files, however they are reached. The
/// real one is CloudKit; tests use a pretend server, so everything above
/// this line — the controller, the status, account switching — and
/// everything below it in the store is exercised by the same code paths
/// either way.
public protocol SyncBackend: Sendable {
    var blobs: any BlobTransport { get }
    func accountState() async -> CloudAccountState
    /// Begins syncing and keeps going until `stop`. Remote changes are
    /// written to the store before the matching event is delivered.
    func start(events: @escaping @Sendable (SyncBackendEvent) async -> Void) async throws
    func stop() async
    /// New entries are in the outbox, or held-back records may now go.
    func localChangesQueued() async
    /// Send and fetch now, and return when both have finished.
    func syncNow() async throws
    /// Forget how far fetching had got and read everything again.
    func refetchEverything() async throws
    /// Removes PaperNest's records and files from iCloud. Local documents
    /// are untouched.
    func deleteAllCloudData() async throws
}

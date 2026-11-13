import CloudKit
import Foundation
import Network
import Observation
import PaperNestCore
import PaperNestStore

/// The one place the app asks about sync and tells it things.
///
/// Everything shown comes from real state: the pending count is the outbox's
/// row count, "up to date" needs a finished fetch and an empty outbox, and a
/// build with no iCloud container says so instead of showing a switch that
/// does nothing.
@MainActor @Observable
public final class CloudSyncController {
    public enum Availability: Sendable, Equatable {
        /// This build was made without an iCloud container.
        case notConfigured
        case checking
        case ready
        case noAccount
        case restricted
        case temporarilyUnavailable
        /// Sync was on for one iCloud account and the device is now signed in
        /// to another. Nothing moves until the person decides.
        case accountChanged
        case unknown
    }

    public private(set) var isEnabled = false
    public private(set) var availability: Availability = .checking
    public private(set) var snapshot = SyncSnapshot()
    public private(set) var counts = LibraryStore.SyncCounts()
    public private(set) var lastSynced: Date?
    public private(set) var failure: SyncFailure?
    public private(set) var conflicts: [SyncConflict] = []
    /// Documents with something that is only in iCloud.
    public private(set) var cloudOnlyItems: Set<ItemID> = []
    public private(set) var downloading: Set<ItemID> = []
    /// Another device runs a newer PaperNest and has sent something this
    /// version cannot read. It is kept aside, untouched.
    public private(set) var needsNewerApp = false
    public private(set) var downloadsOnDemand = false
    /// A switch is being thrown; the control that throws it waits.
    public private(set) var isChangingState = false

    /// Called after changes from another device were written, so open
    /// windows reload.
    public var onLibraryChanged: (@MainActor (SyncApplyReport) -> Void)?

    public var status: SyncStatus { .resolve(snapshot) }

    private let store: LibraryStore
    private let backend: (any SyncBackend)?
    private let blobSyncer: BlobSyncer?
    private var isRunning = false
    private var engineActive = false
    private var transferTask: Task<Void, Never>?
    private var transferWantsAnotherPass = false
    private var changeDebounce: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var accountObserver: (any NSObjectProtocol)?

    public init(store: LibraryStore, backend: (any SyncBackend)?, monitorsNetwork: Bool = true) {
        self.store = store
        self.backend = backend
        blobSyncer = backend.map { BlobSyncer(store: store, transport: $0.blobs) }
        if backend == nil { availability = .notConfigured }
        if monitorsNetwork, backend != nil {
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                let online = path.status == .satisfied
                Task { @MainActor in self?.setOnline(online) }
            }
            monitor.start(queue: DispatchQueue(label: "PaperNest.sync.reachability"))
            pathMonitor = monitor
        }
    }

    /// The real thing when this build has a container; otherwise a
    /// controller that truthfully reports sync as not set up.
    public static func forApp(store: LibraryStore) -> CloudSyncController {
        let backend = CloudSyncConfiguration.fromBundle().map { CloudKitSyncBackend(store: store, configuration: $0) }
        return CloudSyncController(store: store, backend: backend)
    }

    // MARK: - Lifecycle

    /// Reads the saved choice and, if sync is on and the account is the one
    /// it was on for, starts.
    public func start() async {
        isEnabled = (try? await store.syncIsEnabled()) ?? false
        downloadsOnDemand = (try? await store.syncMetaString(SyncMetaKey.downloadOnDemand)) == "1"
        if let text = try? await store.syncMetaString(SyncMetaKey.lastSynced), let seconds = Double(text) {
            lastSynced = Date(timeIntervalSinceReferenceDate: seconds)
        }
        snapshot.isEnabled = isEnabled
        await refresh()
        guard backend != nil else { return }
        if accountObserver == nil {
            accountObserver = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.evaluateAccount() }
            }
        }
        await evaluateAccount()
    }

    /// Checks who is signed in and starts or stops accordingly. Run at
    /// launch, when iCloud says the account changed, and when the app comes
    /// to the front.
    public func evaluateAccount() async {
        guard let backend else { return }
        let state = await backend.accountState()
        switch state {
        case .available(let id):
            let known = try? await store.syncMetaString(SyncMetaKey.account)
            if isEnabled, let known, known != id {
                // Never merged into a different account on its own.
                availability = .accountChanged
                await stopBackend()
            } else {
                availability = .ready
                if isEnabled {
                    if known == nil { try? await store.syncSetMetaString(SyncMetaKey.account, id) }
                    await startBackend()
                }
            }
        case .noAccount:
            availability = .noAccount
            await stopBackend()
        case .restricted:
            availability = .restricted
            await stopBackend()
        case .temporarilyUnavailable:
            availability = .temporarilyUnavailable
            await stopBackend()
        case .couldNotDetermine:
            availability = .unknown
            await stopBackend()
        }
        snapshot.accountAvailable = availability == .ready
    }

    /// Whether turning sync on now would attach this library to a different
    /// iCloud account from the one it last synced with. The screen asks
    /// before doing that.
    public func enablingWouldSwitchAccounts() async -> Bool {
        guard let backend, case .available(let id) = await backend.accountState(),
              let known = try? await store.syncMetaString(SyncMetaKey.account) else { return false }
        return known != id
    }

    public enum EnableError: Error, Equatable {
        case notConfigured
        case accountUnavailable
        case failed
    }

    /// Turns sync on or off **for this device**. Off stops syncing and
    /// nothing else: every document stays here, and everything in iCloud
    /// stays there.
    public func setEnabled(_ enabled: Bool) async throws {
        guard let backend else { throw EnableError.notConfigured }
        isChangingState = true
        defer { isChangingState = false }
        if !enabled {
            await stopBackend()
            try await store.syncSetEnabled(false)
            isEnabled = false
            snapshot.isEnabled = false
            await refresh()
            return
        }
        guard case .available(let id) = await backend.accountState() else {
            await evaluateAccount()
            throw EnableError.accountUnavailable
        }
        do {
            if let known = try await store.syncMetaString(SyncMetaKey.account), known != id {
                // What the previous account confirmed means nothing to this
                // one. The documents themselves are not touched.
                try await store.syncResetCloudKnowledge()
            }
            if try await store.syncMetaString(SyncMetaKey.recoveryCopy) == nil {
                let copy = try await store.syncWriteRecoveryCopy()
                try await store.syncSetMetaString(SyncMetaKey.recoveryCopy, copy.lastPathComponent)
            }
            try await store.syncSetMetaString(SyncMetaKey.account, id)
            try await store.syncSetEnabled(true)
        } catch {
            throw EnableError.failed
        }
        isEnabled = true
        snapshot.isEnabled = true
        failure = nil
        availability = .ready
        snapshot.accountAvailable = true
        await refresh()
        await startBackend()
    }

    /// The device is signed in to a different iCloud account than this
    /// library was syncing with.
    public enum AccountChoice: Sendable {
        /// Upload this library to the account now signed in.
        case syncWithCurrentAccount
        /// Keep everything on this device and stop syncing.
        case stopSyncing
    }

    public func resolveAccountChange(_ choice: AccountChoice) async throws {
        switch choice {
        case .stopSyncing:
            try await setEnabled(false)
            await evaluateAccount()
        case .syncWithCurrentAccount:
            // `setEnabled` sees the different account and starts afresh.
            try await setEnabled(true)
        }
    }

    private func startBackend() async {
        guard let backend, !isRunning else { return }
        isRunning = true
        snapshot.remoteChangesProcessed = false
        do {
            try await backend.start { [weak self] event in await self?.handle(event) }
            runTransfers()
        } catch {
            isRunning = false
            failure = .other("start")
            await refresh()
        }
    }

    private func stopBackend() async {
        guard let backend, isRunning else { return }
        isRunning = false
        transferTask?.cancel()
        await backend.stop()
        engineActive = false
        snapshot.isTransferring = false
    }

    // MARK: - Events

    private func handle(_ event: SyncBackendEvent) async {
        switch event {
        case .activity(let transferring):
            engineActive = transferring
            snapshot.isTransferring = engineActive || transferTask != nil
        case .applied(let report):
            await refresh()
            if report.changed > 0 { onLibraryChanged?(report) }
            runTransfers()
        case .sent:
            await refresh()
            await noteIfSettled()
        case .fetchCompleted:
            snapshot.remoteChangesProcessed = true
            await refresh()
            await noteIfSettled()
            runTransfers()
        case .accountChanged:
            await evaluateAccount()
        case .recovered:
            if failure != .cloudDataDeleted { failure = nil }
            await refresh()
        case .failure(.cloudDataDeleted):
            // Someone removed PaperNest's data from iCloud. That was a
            // decision about iCloud, not about this device: the library
            // stays, sync goes off, and turning it back on uploads again.
            await stopBackend()
            try? await store.syncSetEnabled(false)
            try? await store.syncResetCloudKnowledge()
            isEnabled = false
            snapshot.isEnabled = false
            failure = .cloudDataDeleted
            await refresh()
        case .failure(let other):
            failure = other
            await refresh()
        }
    }

    /// "Last synced" is only moved when it is true: the server's changes are
    /// in and nothing of ours is waiting.
    private func noteIfSettled() async {
        guard snapshot.remoteChangesProcessed, counts.pendingChanges == 0, counts.pendingUploads == 0 else { return }
        let now = Date()
        lastSynced = now
        try? await store.syncSetMetaString(SyncMetaKey.lastSynced, String(now.timeIntervalSinceReferenceDate))
    }

    func setOnline(_ online: Bool) {
        let wasOnline = snapshot.isOnline
        snapshot.isOnline = online
        if online, !wasOnline, isRunning {
            Task { await self.backend?.localChangesQueued() }
            runTransfers()
        }
    }

    // MARK: - What the app tells sync

    /// Something was saved. Coalesced, so a burst of strokes costs one look
    /// at the outbox after the pen lifts rather than one per stroke.
    public func localDidChange() {
        guard isEnabled else { return }
        changeDebounce?.cancel()
        changeDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, let self else { return }
            await self.refresh()
            guard self.isRunning else { return }
            await self.backend?.localChangesQueued()
            self.runTransfers()
        }
    }

    /// Sends and fetches now. Returns when both have finished or failed.
    public func syncNow() async {
        guard let backend else { return }
        await evaluateAccount()
        guard isRunning else { return }
        await runTransfersAndWait()
        do {
            try await backend.syncNow()
            // Whatever the fetch brought may need its originals, and merging
            // may have left something to send.
            await runTransfersAndWait()
            if (try? await store.syncCounts().pendingChanges) ?? 0 > 0 { try await backend.syncNow() }
        } catch {
            if snapshot.isOnline { failure = failure ?? .other("syncNow") }
        }
        await refresh()
        await noteIfSettled()
    }

    public func appBecameActive() async {
        guard backend != nil, isEnabled else { return }
        await evaluateAccount()
        guard isRunning else { return }
        try? await backend?.syncNow()
        await refresh()
    }

    // MARK: - Originals

    private func runTransfers() {
        guard isRunning, blobSyncer != nil else { return }
        guard transferTask == nil else {
            transferWantsAnotherPass = true
            return
        }
        snapshot.isTransferring = true
        transferTask = Task { [weak self] in
            await self?.transferPass()
            guard let self else { return }
            self.transferTask = nil
            self.snapshot.isTransferring = self.engineActive
            await self.refresh()
            await self.noteIfSettled()
            if self.transferWantsAnotherPass {
                self.transferWantsAnotherPass = false
                self.runTransfers()
            }
        }
    }

    private func runTransfersAndWait() async {
        runTransfers()
        // A pass that finds more to do starts another before it ends.
        while let task = transferTask { await task.value }
    }

    private func transferPass() async {
        guard let blobSyncer, let backend else { return }
        let uploaded = await blobSyncer.uploadPending()
        if uploaded.completed > 0 {
            // Records that were waiting for these files can go now.
            await backend.localChangesQueued()
        }
        if uploaded.stopped == .quotaExceeded { failure = .quotaExceeded }
        if !downloadsOnDemand, !Task.isCancelled {
            let downloaded = await blobSyncer.downloadMissing()
            if downloaded.completed > 0 { onLibraryChanged?(SyncApplyReport()) }
        }
        await blobSyncer.deleteExpired()
    }

    /// Fetches everything one document shows, for opening it or keeping it
    /// offline. Returns whether it is all here afterwards.
    @discardableResult
    public func download(_ item: ItemID) async -> Bool {
        guard let blobSyncer, isRunning else { return false }
        downloading.insert(item)
        let pass = await blobSyncer.downloadMissing(for: item)
        downloading.remove(item)
        await refresh()
        if pass.completed > 0 { onLibraryChanged?(SyncApplyReport()) }
        return (try? await store.syncIsAvailableOffline(item)) ?? false
    }

    /// Frees this device's copy of a document's originals that iCloud holds.
    /// The document stays in the library and downloads again when opened.
    public func removeDownloads(_ item: ItemID) async {
        guard let blobSyncer, isRunning else { return }
        let freed = await blobSyncer.removeDownloads(of: item)
        await refresh()
        if freed > 0 { onLibraryChanged?(SyncApplyReport()) }
    }

    public func setDownloadsOnDemand(_ onDemand: Bool) async {
        downloadsOnDemand = onDemand
        try? await store.syncSetMetaString(SyncMetaKey.downloadOnDemand, onDemand ? "1" : nil)
        if !onDemand { runTransfers() }
    }

    // MARK: - Conflicts and the far end

    public func resolveConflict(_ id: String, keepingCopy: Bool) async {
        try? await store.syncResolveConflict(id, keepingCopy: keepingCopy)
        await refresh()
        if !keepingCopy {
            onLibraryChanged?(SyncApplyReport())
            localDidChange()
        }
    }

    /// Deletes PaperNest's data from iCloud and turns sync off here. Every
    /// document on this device stays. Other devices keep theirs too, and
    /// stop syncing when they notice.
    public func deleteCloudData() async throws {
        guard let backend else { throw EnableError.notConfigured }
        isChangingState = true
        defer { isChangingState = false }
        await stopBackend()
        try await backend.deleteAllCloudData()
        try await store.syncSetEnabled(false)
        try await store.syncResetCloudKnowledge()
        isEnabled = false
        snapshot.isEnabled = false
        failure = nil
        await refresh()
    }

    // MARK: - Reading the store

    public func refresh() async {
        if let fresh = try? await store.syncCounts() { counts = fresh }
        conflicts = (try? await store.syncConflicts()) ?? []
        cloudOnlyItems = (try? await store.syncCloudOnlyItems()) ?? []
        needsNewerApp = (try? await store.syncHasRecordsFromNewerApp()) ?? false
        snapshot.pendingChanges = counts.pendingChanges
        snapshot.pendingUploads = counts.pendingUploads
        snapshot.unresolvedConflicts = counts.unresolvedConflicts
        snapshot.hasError = failure != nil || needsNewerApp || counts.failedChanges > 0
    }
}

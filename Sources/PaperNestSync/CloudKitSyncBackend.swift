import CloudKit
import Foundation
import os
import PaperNestCore
import PaperNestStore
#if os(macOS)
import Security
#endif

/// Which iCloud container this build syncs with, if any.
///
/// The identifier comes from the app's Info.plist (`PaperNestICloudContainer`,
/// filled from the `PAPERNEST_ICLOUD_CONTAINER` build setting). A build made
/// without it — the Command Line Tools dev app, a Simulator build with the
/// placeholder identity — has no container, and sync is reported as not set
/// up rather than attempted: creating a `CKContainer` the process is not
/// entitled to raises an exception.
public struct CloudSyncConfiguration: Sendable, Equatable {
    public static let infoPlistKey = "PaperNestICloudContainer"

    public let containerIdentifier: String

    public init(containerIdentifier: String) {
        self.containerIdentifier = containerIdentifier
    }

    public static func fromBundle(_ bundle: Bundle = .main) -> CloudSyncConfiguration? {
        guard let identifier = bundle.object(forInfoDictionaryKey: infoPlistKey) as? String,
              identifier.hasPrefix("iCloud."), !identifier.contains("$(") else { return nil }
        #if os(macOS)
        // The plist can say one thing and the signature another (an ad-hoc
        // signed dev build). Only the entitlement counts.
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil),
              let containers = value as? [String], containers.contains(identifier) else { return nil }
        #endif
        return CloudSyncConfiguration(containerIdentifier: identifier)
    }
}

/// iCloud through `CKSyncEngine`, on the private database.
///
/// The engine decides *when* to talk to the server — it listens for pushes,
/// watches the network, backs off when throttled and retries what is worth
/// retrying. This type decides *what* is said: it hands the engine batches
/// built from the library's outbox and gives everything the server sends to
/// the store, which owns every merge and conflict rule. No document content
/// is ever logged; only counts and error codes.
public actor CloudKitSyncBackend: SyncBackend, CKSyncEngineDelegate {
    private static let log = Logger(subsystem: "PaperNest", category: "sync")

    private let store: LibraryStore
    private let container: CKContainer
    private let database: CKDatabase
    public nonisolated let blobs: any BlobTransport

    private var engine: CKSyncEngine?
    private var events: (@Sendable (SyncBackendEvent) async -> Void)?
    private var batchLimit = 200
    private var activity = 0
    /// Set when something the server sent could not be stored, or a deletion
    /// was withdrawn: the fetch position can no longer be trusted and is
    /// thrown away instead of saved.
    private var mustRefetch = false
    private let scratch: URL

    public init(store: LibraryStore, configuration: CloudSyncConfiguration) {
        self.store = store
        container = CKContainer(identifier: configuration.containerIdentifier)
        database = container.privateCloudDatabase
        blobs = CloudKitBlobTransport(database: database)
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestSyncScratch", isDirectory: true)
    }

    // MARK: - SyncBackend

    public func accountState() async -> CloudAccountState {
        do {
            switch try await container.accountStatus() {
            case .available:
                return .available(id: try await container.userRecordID().recordName)
            case .noAccount: return .noAccount
            case .restricted: return .restricted
            case .temporarilyUnavailable: return .temporarilyUnavailable
            case .couldNotDetermine: return .couldNotDetermine
            @unknown default: return .couldNotDetermine
            }
        } catch {
            return .couldNotDetermine
        }
    }

    public func start(events: @escaping @Sendable (SyncBackendEvent) async -> Void) async throws {
        self.events = events
        guard engine == nil else { return }
        try? FileManager.default.removeItem(at: scratch)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        mustRefetch = false
        let saved = try await store.syncMeta(SyncMetaKey.engineState)
        let state = saved.flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
        let engine = CKSyncEngine(CKSyncEngine.Configuration(database: database, stateSerialization: state, delegate: self))
        self.engine = engine
        if state == nil {
            // Saving a zone that already exists is harmless.
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudSchema.libraryZone))])
        }
        await queuePending()
    }

    public func stop() async {
        let running = engine
        engine = nil
        await running?.cancelOperations()
        try? await store.syncAbandonBatch()
        activity = 0
    }

    public func localChangesQueued() async {
        await queuePending()
    }

    public func syncNow() async throws {
        guard let engine else { return }
        await queuePending()
        try await engine.sendChanges()
        try await engine.fetchChanges()
    }

    public func refetchEverything() async throws {
        guard let events else { return }
        await stop()
        try await store.syncSetMeta(SyncMetaKey.engineState, nil)
        try await start(events: events)
    }

    public func deleteAllCloudData() async throws {
        await stop()
        let zones = [CloudSchema.libraryZone, CloudSchema.originalsZone]
        let (_, deleted) = try await database.modifyRecordZones(saving: [], deleting: zones)
        for (_, result) in deleted {
            if case .failure(let error) = result, (error as? CKError)?.code != .zoneNotFound { throw error }
        }
        try await store.syncSetMeta(SyncMetaKey.engineState, nil)
    }

    // MARK: - Pending changes

    private func pendingChange(_ key: SyncRecordKey, isDelete: Bool) -> CKSyncEngine.PendingRecordZoneChange {
        isDelete ? .deleteRecord(CloudSchema.recordID(key)) : .saveRecord(CloudSchema.recordID(key))
    }

    /// Tells the engine about everything in the outbox. Adding a change it
    /// already holds does nothing, so this is safe to call after any edit.
    private func queuePending() async {
        guard let engine, let pending = try? await store.syncPendingKeys(), !pending.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: pending.map { pendingChange($0.key, isDelete: $0.isDelete) })
    }

    private func emit(_ event: SyncBackendEvent) async {
        await events?(event)
    }

    private func setActive(_ delta: Int) async {
        let wasActive = activity > 0
        activity = max(0, activity + delta)
        if wasActive != (activity > 0) { await emit(.activity(isTransferring: activity > 0)) }
    }

    // MARK: - CKSyncEngineDelegate

    public func nextFetchChangesOptions(_ context: CKSyncEngine.FetchChangesContext,
                                        syncEngine: CKSyncEngine) async -> CKSyncEngine.FetchChangesOptions {
        var options = context.options
        // Original files are fetched one at a time when wanted, never swept
        // up with the records.
        if case .all = options.scope { options.scope = .allExcluding([CloudSchema.originalsZone]) }
        return options
    }

    public func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                          syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        var keys = Set<SyncRecordKey>()
        for change in pending {
            switch change {
            case .saveRecord(let id), .deleteRecord(let id):
                if let key = CloudSchema.key(id) { keys.insert(key) }
            @unknown default:
                break
            }
        }
        guard !keys.isEmpty, let batch = try? await store.syncNextBatch(limit: batchLimit, only: keys) else { return nil }

        var saves: [CKRecord] = []
        var deletes: [CKRecord.ID] = []
        for change in batch.changes {
            switch change {
            case .save(let record, let systemFields):
                if let ck = try? CloudRecordMapper.cloudRecord(for: record, systemFields: systemFields, temporaryDirectory: scratch) {
                    saves.append(ck)
                }
            case .delete(let key):
                deletes.append(CloudSchema.recordID(key))
            }
        }
        if saves.isEmpty && deletes.isEmpty {
            // Nothing among these can go now: already what the server has,
            // or waiting for an original to finish uploading. The engine is
            // told so, or it would ask again at once; `queuePending` puts
            // back whatever is still in the outbox when that changes.
            syncEngine.state.remove(pendingRecordZoneChanges: pending)
            return nil
        }
        let stale = (batch.dropped + batch.blocked).flatMap { [pendingChange($0, isDelete: false), pendingChange($0, isDelete: true)] }
        if !stale.isEmpty { syncEngine.state.remove(pendingRecordZoneChanges: stale) }
        return CKSyncEngine.RecordZoneChangeBatch(recordsToSave: saves, recordIDsToDelete: deletes, atomicByZone: false)
    }

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            guard !mustRefetch, let data = try? JSONEncoder().encode(update.stateSerialization) else { return }
            try? await store.syncSetMeta(SyncMetaKey.engineState, data)

        case .accountChange:
            await emit(.accountChanged)

        case .fetchedDatabaseChanges(let changes):
            if changes.deletions.contains(where: { $0.zoneID == CloudSchema.libraryZone }) {
                Self.log.notice("library zone was deleted on the server")
                await emit(.failure(.cloudDataDeleted))
            }

        case .fetchedRecordZoneChanges(let changes):
            await apply(changes)

        case .sentDatabaseChanges(let sent):
            for failure in sent.failedZoneSaves {
                Self.log.error("zone save failed: \(failure.error.code.rawValue)")
                if failure.error.code == .quotaExceeded { await emit(.failure(.quotaExceeded)) }
            }

        case .sentRecordZoneChanges(let sent):
            await handle(sent, engine: syncEngine)

        case .willFetchChanges, .willSendChanges:
            await setActive(1)

        case .didSendChanges:
            await setActive(-1)
            // Files for oversized fields have been uploaded or abandoned.
            if let leftovers = try? FileManager.default.contentsOfDirectory(at: scratch, includingPropertiesForKeys: nil) {
                for file in leftovers { try? FileManager.default.removeItem(at: file) }
            }

        case .didFetchChanges:
            await setActive(-1)
            if mustRefetch {
                // Outside this callback: restarting cancels the engine, and
                // the engine is waiting for this to return.
                Task { try? await self.refetchEverything() }
            } else {
                await emit(.fetchCompleted)
            }

        case .didFetchRecordZoneChanges(let done):
            if let error = done.error, error.code == .userDeletedZone, done.zoneID == CloudSchema.libraryZone {
                await emit(.failure(.cloudDataDeleted))
            }

        case .willFetchRecordZoneChanges:
            break

        @unknown default:
            break
        }
    }

    private func apply(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) async {
        let modifications = changes.modifications.compactMap { CloudRecordMapper.incoming(from: $0.record) }
        let deletions = changes.deletions.compactMap { CloudSchema.key($0.recordID) }
        guard !modifications.isEmpty || !deletions.isEmpty else { return }
        do {
            let report = try await store.syncApply(modifications: modifications, deletions: deletions)
            if report.needsFullRefetch { mustRefetch = true }
            Self.log.info("applied \(modifications.count) changes, \(deletions.count) deletions, \(report.deferred) deferred")
            // Merging may have left this device with something to send back.
            await queuePending()
            await emit(.applied(report))
        } catch {
            // Not stored, so the engine must not be allowed to move past it.
            Self.log.error("could not store fetched changes")
            mustRefetch = true
            await emit(.failure(.other("apply")))
        }
    }

    private func handle(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, engine: CKSyncEngine) async {
        var result = LibraryStore.SyncSendResult()
        var retry: [SyncRecordKey] = []
        var zoneMissing = false, cloudDeleted = false, quota = false

        result.saved = sent.savedRecords.compactMap { CloudRecordMapper.incoming(from: $0) }
        result.deleted = sent.deletedRecordIDs.compactMap { CloudSchema.key($0) }

        func classify(_ key: SyncRecordKey, _ error: CKError, isDelete: Bool) {
            switch error.code {
            case .serverRecordChanged:
                if let server = error.serverRecord, let incoming = CloudRecordMapper.incoming(from: server) {
                    result.conflicts.append(incoming)
                    retry.append(key)
                } else {
                    result.failed.append((key, "conflict"))
                }
            case .unknownItem:
                // A delete of something already gone has succeeded. A save
                // of something the server no longer has is an edit against a
                // deletion, which the store settles.
                if isDelete { result.deleted.append(key) } else { result.missing.append(key); retry.append(key) }
            case .zoneNotFound:
                zoneMissing = true
                retry.append(key)
            case .userDeletedZone:
                cloudDeleted = true
            case .quotaExceeded:
                quota = true
                result.failed.append((key, "quota"))
            case .limitExceeded:
                batchLimit = max(20, batchLimit / 2)
                retry.append(key)
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated,
                 .operationCancelled, .requestRateLimited, .batchRequestFailed, .accountTemporarilyUnavailable:
                // The engine retries these itself, after waiting as long as
                // the server asked.
                break
            default:
                result.failed.append((key, "cloudkit-\(error.code.rawValue)"))
            }
        }
        for failure in sent.failedRecordSaves {
            guard let key = CloudSchema.key(failure.record.recordID) else { continue }
            classify(key, failure.error, isDelete: false)
        }
        for (id, error) in sent.failedRecordDeletes {
            guard let key = CloudSchema.key(id) else { continue }
            classify(key, error, isDelete: true)
        }

        var report = SyncApplyReport()
        do {
            report = try await store.syncHandleSendResult(result)
        } catch {
            Self.log.error("could not record the server's answer")
            await emit(.failure(.other("store")))
        }
        if report.needsFullRefetch { mustRefetch = true }

        if zoneMissing {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudSchema.libraryZone))])
        }
        // Saved, but edited again meanwhile; or refused and merged.
        let again = result.saved.map(\.record.key) + retry
        if let still = try? await store.syncStillPending(again), !still.isEmpty {
            engine.state.add(pendingRecordZoneChanges: still.map { pendingChange($0.key, isDelete: $0.isDelete) })
        }

        Self.log.info("sent: \(result.saved.count) saved, \(result.deleted.count) deleted, \(result.conflicts.count) merged, \(result.failed.count) failed")
        if cloudDeleted {
            await emit(.failure(.cloudDataDeleted))
        } else if quota {
            await emit(.failure(.quotaExceeded))
        } else if let first = result.failed.first {
            await emit(.failure(.other(first.message)))
        } else if !result.saved.isEmpty || !result.deleted.isEmpty {
            await emit(.recovered)
        }
        await emit(.sent)
        if report.changed > 0 { await emit(.applied(report)) }
    }
}

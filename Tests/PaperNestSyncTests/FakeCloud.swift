import CoreGraphics
import Foundation
import PaperNestCore
@testable import PaperNestStore
@testable import PaperNestSync

/// A pretend iCloud, in memory, that behaves the way CloudKit does where it
/// matters to correctness: a save carrying a stale change tag is refused and
/// answered with the server's copy, a save to a record that no longer exists
/// is refused as unknown, deletes are unconditional, and a fetch returns
/// everything that changed since a token — this device's own changes
/// included. Each account has its own data.
///
/// It is not CloudKit. Tests passing here show the library's sync logic
/// converges; they say nothing about entitlements, pushes, the schema in the
/// real container, or how CKSyncEngine schedules work.
final class FakeCloud: @unchecked Sendable {
    private struct Stored {
        var fields: SyncFields
        var tag: Int
    }

    private final class AccountData {
        var records: [SyncRecordKey: Stored] = [:]
        var lastChange: [SyncRecordKey: Int] = [:]
        var serial = 0
        var blobs: [String: Data] = [:]
        var wipes = 0
    }

    private let lock = NSLock()
    private var accounts: [String: AccountData] = ["account-A": AccountData()]
    private var signedIn: String? = "account-A"

    private var _isOnline = true
    private var _quotaExceeded = false
    private var _corruptDownloads = false
    private var _acceptLimit: Int?
    private var _saveCount = 0
    private var _blobUploads = 0

    var isOnline: Bool {
        get { lock.withLock { _isOnline } }
        set { lock.withLock { _isOnline = newValue } }
    }

    var quotaExceeded: Bool {
        get { lock.withLock { _quotaExceeded } }
        set { lock.withLock { _quotaExceeded = newValue } }
    }

    var corruptDownloads: Bool {
        get { lock.withLock { _corruptDownloads } }
        set { lock.withLock { _corruptDownloads = newValue } }
    }

    /// After this many more saved records the connection "drops".
    var acceptLimit: Int? {
        get { lock.withLock { _acceptLimit } }
        set { lock.withLock { _acceptLimit = newValue } }
    }

    var savedRecordCount: Int { lock.withLock { _saveCount } }
    var blobUploadCount: Int { lock.withLock { _blobUploads } }

    func signIn(_ account: String?) {
        lock.withLock {
            signedIn = account
            if let account, accounts[account] == nil { accounts[account] = AccountData() }
        }
    }

    var accountState: CloudAccountState {
        lock.withLock { signedIn.map { .available(id: $0) } ?? .noAccount }
    }

    private var current: AccountData? { signedIn.flatMap { accounts[$0] } }

    func recordCount(account: String) -> Int { lock.withLock { accounts[account]?.records.count ?? 0 } }
    func blobCount(account: String) -> Int { lock.withLock { accounts[account]?.blobs.count ?? 0 } }
    func record(_ key: SyncRecordKey, account: String = "account-A") -> SyncFields? {
        lock.withLock { accounts[account]?.records[key]?.fields }
    }

    var wipeCount: Int { lock.withLock { current?.wipes ?? 0 } }

    private static func tagData(_ tag: Int) -> Data { Data(String(tag).utf8) }
    private static func tag(_ data: Data?) -> Int? { data.flatMap { Int(String(decoding: $0, as: UTF8.self)) } }

    enum Failure: Error { case offline, connectionLost }

    func send(_ changes: [SyncOutgoing]) throws -> LibraryStore.SyncSendResult {
        try lock.withLock {
            guard _isOnline, let data = current else { throw Failure.offline }
            var result = LibraryStore.SyncSendResult()
            for change in changes {
                switch change {
                case .delete(let key):
                    if data.records.removeValue(forKey: key) != nil {
                        data.serial += 1
                        data.lastChange[key] = data.serial
                    }
                    result.deleted.append(key)
                case .save(let record, let systemFields):
                    if let limit = _acceptLimit {
                        guard limit > 0 else { throw Failure.connectionLost }
                        _acceptLimit = limit - 1
                    }
                    let key = record.key
                    let clientTag = Self.tag(systemFields)
                    if let existing = data.records[key] {
                        guard clientTag == existing.tag else {
                            result.conflicts.append(SyncIncoming(record: SyncRecord(key: key, fields: existing.fields),
                                                                 systemFields: Self.tagData(existing.tag)))
                            continue
                        }
                    } else if clientTag != nil {
                        result.missing.append(key)
                        continue
                    }
                    if _quotaExceeded {
                        result.failed.append((key, "quota"))
                        continue
                    }
                    data.serial += 1
                    data.records[key] = Stored(fields: record.fields, tag: data.serial)
                    data.lastChange[key] = data.serial
                    _saveCount += 1
                    result.saved.append(SyncIncoming(record: record, systemFields: Self.tagData(data.serial)))
                }
            }
            return result
        }
    }

    struct Fetched {
        var modifications: [SyncIncoming] = []
        var deletions: [SyncRecordKey] = []
        var token = 0
        var wipes = 0
    }

    /// Everything changed after `token`. `only` limits it to some record
    /// types, to deliver a document's pages ahead of the document.
    func changes(since token: Int, only types: Set<SyncRecordType>? = nil) throws -> Fetched {
        try lock.withLock {
            guard _isOnline, let data = current else { throw Failure.offline }
            var fetched = Fetched(token: data.serial, wipes: data.wipes)
            for (key, serial) in data.lastChange where serial > token {
                if let types, !types.contains(key.type) { continue }
                if let stored = data.records[key] {
                    fetched.modifications.append(SyncIncoming(record: SyncRecord(key: key, fields: stored.fields),
                                                              systemFields: Self.tagData(stored.tag)))
                } else {
                    fetched.deletions.append(key)
                }
            }
            return fetched
        }
    }

    /// Writes a record as some other, newer app would have.
    func plant(_ record: SyncRecord) {
        lock.withLock {
            guard let data = current else { return }
            data.serial += 1
            data.records[record.key] = Stored(fields: record.fields, tag: data.serial)
            data.lastChange[record.key] = data.serial
        }
    }

    func wipe() {
        lock.withLock {
            guard let data = current else { return }
            data.records.removeAll()
            data.lastChange.removeAll()
            data.blobs.removeAll()
            data.wipes += 1
        }
    }

    // MARK: Originals

    func blobExists(_ sha: String) throws -> Bool {
        try lock.withLock {
            guard _isOnline, let data = current else { throw BlobTransportError.unavailable }
            return data.blobs[sha] != nil
        }
    }

    func putBlob(_ sha: String, _ bytes: Data) throws {
        try lock.withLock {
            guard _isOnline, let data = current else { throw BlobTransportError.unavailable }
            guard !_quotaExceeded else { throw BlobTransportError.quotaExceeded }
            data.blobs[sha] = bytes
            _blobUploads += 1
        }
    }

    func blob(_ sha: String) throws -> Data? {
        try lock.withLock {
            guard _isOnline, let data = current else { throw BlobTransportError.unavailable }
            guard var bytes = data.blobs[sha] else { return nil }
            if _corruptDownloads { bytes.append(0x00) }
            return bytes
        }
    }

    func removeBlob(_ sha: String) throws {
        try lock.withLock {
            guard _isOnline, let data = current else { throw BlobTransportError.unavailable }
            data.blobs[sha] = nil
        }
    }
}

struct FakeBlobTransport: BlobTransport {
    let cloud: FakeCloud

    func exists(_ sha256: String) async throws -> Bool { try cloud.blobExists(sha256) }

    func upload(_ sha256: String, from fileURL: URL, byteCount: Int64) async throws {
        try cloud.putBlob(sha256, try Data(contentsOf: fileURL))
    }

    func download(_ sha256: String) async throws -> URL? {
        guard let bytes = try cloud.blob(sha256) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fake-download-\(UUID().uuidString)")
        try bytes.write(to: url)
        return url
    }

    func delete(_ sha256: String) async throws { try cloud.removeBlob(sha256) }
}

/// Stands where `CloudKitSyncBackend` stands, talking to `FakeCloud`. It
/// calls exactly the store methods the real backend calls, in the same
/// order: build a batch, hand the server's answer to
/// `syncHandleSendResult`, hand fetched changes to `syncApply`.
actor FakeBackend: SyncBackend {
    let cloud: FakeCloud
    let store: LibraryStore
    nonisolated let blobs: any BlobTransport

    private var events: (@Sendable (SyncBackendEvent) async -> Void)?
    private var token = 0
    private var seenWipes = 0
    private var isRunning = false
    /// The next answer from the server never arrives: the app was killed
    /// after the upload left and before the reply was recorded.
    var loseNextAnswer = false
    /// Fetch record types in separate batches, in this order.
    var fetchOrder: [Set<SyncRecordType>]?

    init(cloud: FakeCloud, store: LibraryStore) {
        self.cloud = cloud
        self.store = store
        blobs = FakeBlobTransport(cloud: cloud)
    }

    func setLoseNextAnswer(_ value: Bool) { loseNextAnswer = value }
    func setFetchOrder(_ order: [Set<SyncRecordType>]?) { fetchOrder = order }

    func accountState() async -> CloudAccountState { cloud.accountState }

    func start(events: @escaping @Sendable (SyncBackendEvent) async -> Void) async throws {
        self.events = events
        isRunning = true
        if let saved = try await store.syncMeta(SyncMetaKey.engineState),
           let parts = Optional(String(decoding: saved, as: UTF8.self).split(separator: ",")), parts.count == 2 {
            token = Int(parts[0]) ?? 0
            seenWipes = Int(parts[1]) ?? 0
        } else {
            token = 0
            seenWipes = cloud.wipeCount
        }
    }

    func stop() async {
        isRunning = false
        try? await store.syncAbandonBatch()
    }

    func localChangesQueued() async {}

    func syncNow() async throws {
        guard isRunning else { return }
        await events?(.activity(isTransferring: true))
        defer { Task { await events?(.activity(isTransferring: false)) } }
        try await push()
        try await pull()
        try await push()
    }

    func refetchEverything() async throws {
        token = 0
        try await pull()
    }

    func deleteAllCloudData() async throws {
        cloud.wipe()
        try await store.syncSetMeta(SyncMetaKey.engineState, nil)
    }

    private func saveToken() async throws {
        try await store.syncSetMeta(SyncMetaKey.engineState, Data("\(token),\(seenWipes)".utf8))
    }

    private func push() async throws {
        while true {
            let batch = try await store.syncNextBatch(limit: 50)
            guard !batch.changes.isEmpty else { return }
            let result = try cloud.send(batch.changes)
            if loseNextAnswer {
                loseNextAnswer = false
                throw FakeCloud.Failure.connectionLost
            }
            let report = try await store.syncHandleSendResult(result)
            if result.failed.contains(where: { $0.message == "quota" }) {
                await events?(.failure(.quotaExceeded))
            } else if !result.saved.isEmpty || !result.deleted.isEmpty {
                await events?(.recovered)
            }
            await events?(.sent)
            if report.changed > 0 { await events?(.applied(report)) }
            if report.needsFullRefetch { token = 0 }
            let progressed = !(result.saved.isEmpty && result.deleted.isEmpty && result.conflicts.isEmpty && result.missing.isEmpty)
            guard progressed else { return }
        }
    }

    private func pull() async throws {
        let passes: [Set<SyncRecordType>?] = fetchOrder.map { $0.map(Optional.some) } ?? [nil]
        var newToken = token
        for types in passes {
            let fetched = try cloud.changes(since: token, only: types)
            if fetched.wipes > seenWipes {
                seenWipes = fetched.wipes
                await events?(.failure(.cloudDataDeleted))
                return
            }
            newToken = fetched.token
            let report = try await store.syncApply(modifications: fetched.modifications, deletions: fetched.deletions)
            if report.needsFullRefetch {
                token = 0
                try await saveToken()
                fetchOrder = nil
                return try await pull()
            }
            await events?(.applied(report))
        }
        token = newToken
        try await saveToken()
        await events?(.fetchCompleted)
    }
}

/// One device: its own library on disk, its own controller, a shared cloud.
@MainActor
final class TestDevice {
    let name: String
    let directory: URL
    let cloud: FakeCloud
    private(set) var store: LibraryStore
    private(set) var backend: FakeBackend
    private(set) var sync: CloudSyncController
    private(set) var libraryChanges = 0

    init(_ name: String, cloud: FakeCloud) throws {
        self.name = name
        self.cloud = cloud
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestSyncTests-\(UUID().uuidString)", isDirectory: true)
        store = try LibraryStore(directory: directory)
        backend = FakeBackend(cloud: cloud, store: store)
        sync = CloudSyncController(store: store, backend: backend, monitorsNetwork: false)
        sync.onLibraryChanged = { [weak self] _ in self?.libraryChanges += 1 }
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    /// A device with sync already on.
    static func syncing(_ name: String, cloud: FakeCloud) async throws -> TestDevice {
        let device = try TestDevice(name, cloud: cloud)
        await device.sync.start()
        try await device.sync.setEnabled(true)
        return device
    }

    /// Quits and reopens the app: a new store over the same files, launch
    /// housekeeping, a new controller.
    func relaunch() async throws {
        store = try LibraryStore(directory: directory)
        try await store.purgeDeletedPages()
        try await store.purgeReplacedPageContent()
        try await store.purgeExpiredDeletions()
        try await store.sweepOrphanAssets(gracePeriod: 0)
        backend = FakeBackend(cloud: cloud, store: store)
        sync = CloudSyncController(store: store, backend: backend, monitorsNetwork: false)
        await sync.start()
    }

    func syncNow() async {
        await sync.syncNow()
    }

    // MARK: Making things

    static func pdfBytes(_ label: String, size: Int = 64) -> Data {
        Data("%PDF-synthetic \(label) ".utf8) + Data(repeating: 0x41, count: size)
    }

    @discardableResult
    func makeDocument(_ name: String, pages: Int = 2, folder: FolderID? = nil, bytes: Data? = nil) async throws -> LibraryItem {
        let asset = try store.assets.store(bytes ?? Self.pdfBytes(name), kind: .pdf, originalFilename: "\(name).pdf")
        let newPages = (0..<pages).map {
            LibraryStore.NewPage(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: $0))
        }
        return try await store.createItem(kind: .document, name: name, folderID: folder, pages: newPages, assets: [asset])
    }

    @discardableResult
    func makeNotebook(_ name: String, pages: Int = 1) async throws -> LibraryItem {
        let newPages = (0..<pages).map { _ in
            LibraryStore.NewPage(sourceSize: CGSize(width: 595, height: 842), content: .template(.lined))
        }
        return try await store.createItem(kind: .notebook, name: name, pages: newPages, assets: [])
    }

    @discardableResult
    func draw(on page: Page, x: Double = 10, color: RGBAColor = .black) async throws -> PageObject {
        let stroke = InkStroke(tool: .pen, color: color, width: 2,
                               points: [InkPoint(x: x, y: 10), InkPoint(x: x + 40, y: 60), InkPoint(x: x + 80, y: 20)])
        let last = try await store.objects(on: page.id).last?.zKey
        let object = PageObject(pageID: page.id, zKey: try SortKey.between(last, nil), payload: .ink(stroke), modifiedAt: Date())
        try await store.saveObject(object)
        return object
    }

    func pages(_ item: LibraryItem) async throws -> [Page] { try await store.pages(of: item.id) }

    /// The whole library as the records it would sync as, for comparing
    /// devices. Identical dumps mean identical documents, pages and marks.
    func dump() async throws -> [String] { try await store.testSyncDump() }
}

extension LibraryStore {
    func testSyncDump() throws -> [String] {
        var lines: [String] = []
        let tables: [(SyncRecordType, String)] = [(.folder, "folders"), (.item, "items"), (.page, "pages"),
                                                  (.object, "page_objects"), (.signature, "signatures")]
        for (type, table) in tables {
            for id in try db.query("SELECT id FROM \(table) ORDER BY id", map: { $0.text(0) }) {
                guard let record = try syncSnapshot(SyncRecordKey(type, id)) else { continue }
                let fields = Self.syncCore(record.fields).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
                lines.append("\(type.rawValue) \(id) " + fields.joined(separator: " "))
            }
        }
        return lines
    }

    func testOutboxCount() throws -> Int {
        try db.query("SELECT count(*) FROM sync_outbox") { $0.int(0) }.first ?? 0
    }

    func testTriggerNames() throws -> Set<String> {
        Set(try db.query("SELECT name FROM sqlite_master WHERE type = 'trigger'") { $0.text(0) })
    }

    func testAssetState(_ id: AssetID) throws -> String? {
        try db.query("SELECT state FROM sync_assets WHERE asset_id = ?", [.text(id.sha256)]) { $0.text(0) }.first
    }

    func testBackdateAssetTombstones(days: Double) throws {
        try db.run("UPDATE sync_assets SET changed_at = changed_at - ? WHERE state = 'pendingRemoteDelete'", [.double(days * 86_400)])
    }

    func testBackdateDeletedPages(days: Double) throws {
        // Time passing is not an edit: the triggers must not see it as one.
        try db.run("UPDATE sync_control SET applying_remote = 1")
        try db.run("UPDATE pages SET deleted_at = deleted_at - ? WHERE deleted_at IS NOT NULL", [.double(days * 86_400)])
        try db.run("UPDATE sync_control SET applying_remote = 0")
    }
}

import CloudKit
import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore
@testable import PaperNestSync

private final class TempLibrary {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestSyncUnit-\(UUID().uuidString)", isDirectory: true)
    deinit { try? FileManager.default.removeItem(at: url) }
}

private func makeDocument(_ store: LibraryStore, pages: Int = 2) async throws -> LibraryItem {
    let asset = try store.assets.store(Data("%PDF-unit-\(UUID().uuidString)".utf8), kind: .pdf, originalFilename: "unit.pdf")
    let newPages = (0..<pages).map { LibraryStore.NewPage(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: $0)) }
    return try await store.createItem(kind: .document, name: "Unit", pages: newPages, assets: [asset])
}

@Suite struct SyncSchemaTests {
    /// SQLite drops a table's triggers with the table. A later migration
    /// that rebuilds one of these tables and forgets to recreate them would
    /// stop that table syncing without a single test elsewhere noticing.
    @Test func everySyncTriggerExistsInTheLatestSchema() async throws {
        let library = TempLibrary()
        let store = try LibraryStore(directory: library.url)
        let names = try await store.testTriggerNames()
        var expected: Set<String> = [
            "sync_file_items_insert", "sync_file_items_update", "sync_pages_asset_insert", "sync_pages_asset_update",
            "sync_objects_asset_insert", "sync_assets_insert", "sync_assets_delete",
            "sync_pages_local_delete", "sync_pages_local_restore",
        ]
        for table in ["folders", "items", "pages", "page_objects", "signatures"] {
            for event in ["insert", "update", "delete"] { expected.insert("sync_\(table)_\(event)") }
        }
        #expect(names.isSuperset(of: expected), "missing: \(expected.subtracting(names).sorted())")
    }

    @Test func nothingIsQueuedWhileSyncIsOff() async throws {
        let library = TempLibrary()
        let store = try LibraryStore(directory: library.url)
        let item = try await makeDocument(store)
        try await store.rename(item.id, to: "Renamed")
        try await store.deletePages([try await store.pages(of: item.id)[0].id])
        #expect(try await store.testOutboxCount() == 0)
        #expect(try await store.syncCounts().pendingUploads == 0)
    }

    @Test func everyKindOfEditIsQueuedInTheTransactionThatMadeIt() async throws {
        let library = TempLibrary()
        let store = try LibraryStore(directory: library.url)
        try await store.syncSetEnabled(true)
        let item = try await makeDocument(store)
        let pages = try await store.pages(of: item.id)
        // One item, two pages, one original.
        let created = try await store.syncPendingKeys().map(\.key.type.rawValue).sorted()
        #expect(created == ["item", "page", "page"])
        #expect(try await store.syncCounts().pendingUploads == 1)

        // A stroke queues the stroke and the item (its modified date), not the page.
        try await store.syncConfirmSaved(try await store.syncNextBatchIgnoringUploads())
        #expect(try await store.testOutboxCount() == 0)
        let stroke = PageObject(pageID: pages[0].id, zKey: "V",
                                payload: .ink(InkStroke(tool: .pen, color: .black, width: 1, points: [InkPoint(x: 1, y: 1)])),
                                modifiedAt: Date())
        try await store.saveObject(stroke)
        let afterStroke = Set(try await store.syncPendingKeys().map(\.key))
        #expect(afterStroke == [SyncRecordKey(.object, stroke.id.rawValue), SyncRecordKey(.item, item.id.rawValue)])

        // Deleting a document for good queues deletions for all of it,
        // through the foreign-key cascade.
        try await store.syncConfirmSaved(try await store.syncNextBatchIgnoringUploads())
        try await store.moveToRecentlyDeleted([item.id])
        try await store.deletePermanently([item.id])
        let pending = try await store.syncPendingKeys()
        let allDeletions = pending.allSatisfy { $0.isDelete }
        let deletedKeys = Set(pending.map { $0.key })
        #expect(allDeletions)
        #expect(deletedKeys == Set([SyncRecordKey(.item, item.id.rawValue), SyncRecordKey(.object, stroke.id.rawValue)]
            + pages.map { SyncRecordKey(.page, $0.id.rawValue) }))
    }

    @Test func somethingMadeAndErasedBeforeItEverSyncedLeavesNoTrace() async throws {
        let library = TempLibrary()
        let store = try LibraryStore(directory: library.url)
        try await store.syncSetEnabled(true)
        let item = try await makeDocument(store)
        let page = try await store.pages(of: item.id)[0]
        let before = try await store.testOutboxCount()
        let stroke = PageObject(pageID: page.id, zKey: "V",
                                payload: .ink(InkStroke(tool: .pen, color: .black, width: 1, points: [InkPoint(x: 1, y: 1)])),
                                modifiedAt: Date())
        try await store.saveObject(stroke)
        try await store.deleteObject(stroke.id)
        #expect(try await store.testOutboxCount() == before)
    }

    @Test func aFailedEditQueuesNothing() async throws {
        let library = TempLibrary()
        let store = try LibraryStore(directory: library.url)
        try await store.syncSetEnabled(true)
        let before = try await store.testOutboxCount()
        await #expect(throws: StoreError.itemNotFound) {
            try await store.setColorLabel(.red, for: [ItemID(rawValue: "no-such-item")])
        }
        #expect(try await store.testOutboxCount() == before)
    }

    @Test func aLibraryFromBeforeSyncMigratesAndKeepsWorking() async throws {
        let library = TempLibrary()
        do {
            let store = try LibraryStore(directory: library.url)
            _ = try await makeDocument(store)
        }
        let reopened = try LibraryStore(directory: library.url)
        #expect(try await reopened.schemaVersion() == 10)
        #expect(try await reopened.syncIsEnabled() == false)
        #expect(try await reopened.items(in: .all).count == 1)
    }
}

extension LibraryStore {
    /// Pretends every queued save was accepted, without any originals
    /// having to be uploaded first.
    func syncNextBatchIgnoringUploads() throws -> [SyncIncoming] {
        try db.run("UPDATE sync_assets SET state = 'uploaded'")
        return try syncNextBatch(limit: 10_000).changes.compactMap { change in
            if case .save(let record, _) = change { return SyncIncoming(record: record, systemFields: Data("1".utf8)) }
            return nil
        }
    }
}

@Suite struct SyncMergeTests {
    private func transform(_ t: PageTransform) -> SyncValue {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return .string(String(decoding: try! encoder.encode(t), as: UTF8.self))
    }

    @Test func aChangeOnlyOneSideMadeIsKept() {
        let base: SyncFields = ["name": .string("A"), "isFavorite": .int(0), "modifiedAt": .double(1)]
        var local = base, remote = base
        local["name"] = .string("Local name")
        local["modifiedAt"] = .double(5)
        remote["isFavorite"] = .int(1)
        remote["modifiedAt"] = .double(9)
        let merged = SyncMerge.resolve(.item, base: base, local: local, incoming: remote).merged
        #expect(merged == ["name": .string("Local name"), "isFavorite": .int(1), "modifiedAt": .double(9)])
    }

    @Test func beingAliveBeatsBeingDeleted() {
        let base: SyncFields = ["name": .string("A"), "deletedAt": .double(10), "modifiedAt": .double(1)]
        var restored = base, redeleted = base
        restored["deletedAt"] = nil
        redeleted["deletedAt"] = .double(20)
        #expect(SyncMerge.resolve(.item, base: base, local: restored, incoming: redeleted).merged["deletedAt"] == nil)
        #expect(SyncMerge.resolve(.item, base: base, local: redeleted, incoming: restored).merged["deletedAt"] == nil)
    }

    @Test func withNoCommonAncestorIdenticalRecordsAreNotAConflict() {
        let same: SyncFields = ["pageID": .string("p"), "kind": .string("ink"), "payload": .string("{}"), "zKey": .string("V"),
                                "modifiedAt": .double(3)]
        let resolution = SyncMerge.resolve(.object, base: nil, local: same, incoming: same)
        #expect(resolution.merged == same && !resolution.keepLocalCopy)
    }

    @Test func newPaperOnOneSideAndACropOnTheOtherKeepsBothAsPages() {
        let base: SyncFields = ["contentKind": .string("image"), "assetID": .string("aaa"), "width": .double(100),
                                "height": .double(100), "transform": transform(.identity), "sortKey": .string("V")]
        var rescanned = base, cropped = base
        rescanned["assetID"] = .string("bbb")
        cropped["transform"] = transform(PageTransform(crop: NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)))
        let resolution = SyncMerge.resolve(.page, base: base, local: cropped, incoming: rescanned)
        #expect(resolution.keepLocalCopy)
        #expect(resolution.merged["assetID"] == .string("bbb") && resolution.merged["transform"] == transform(.identity))
    }

    @Test func aReorderDoesNotDisturbAnEdit() {
        let base: SyncFields = ["contentKind": .string("template"), "template": .string("lined"), "width": .double(100),
                                "height": .double(100), "transform": transform(.identity), "sortKey": .string("V")]
        var moved = base, turned = base
        moved["sortKey"] = .string("k")
        turned["transform"] = transform(PageTransform(rotation: .half))
        let resolution = SyncMerge.resolve(.page, base: base, local: turned, incoming: moved)
        #expect(!resolution.keepLocalCopy)
        #expect(resolution.merged["sortKey"] == .string("k") && resolution.merged["transform"] == turned["transform"])
    }
}

@Suite struct SyncStatusTests {
    @Test func upToDateIsOnlyClaimedWhenItIsTrue() {
        var s = SyncSnapshot()
        #expect(SyncStatus.resolve(s) == .savedLocally)
        s.isEnabled = true
        // On, but nothing has been heard from the server yet.
        #expect(SyncStatus.resolve(s) == .waiting)
        s.remoteChangesProcessed = true
        #expect(SyncStatus.resolve(s) == .upToDate)
        s.pendingChanges = 1
        #expect(SyncStatus.resolve(s) == .waiting)
        s.pendingChanges = 0
        s.pendingUploads = 1
        #expect(SyncStatus.resolve(s) == .waiting)
        s.isTransferring = true
        #expect(SyncStatus.resolve(s) == .syncing)
        s.isTransferring = false
        s.pendingUploads = 0
        s.unresolvedConflicts = 1
        #expect(SyncStatus.resolve(s) == .conflict)
        s.hasError = true
        #expect(SyncStatus.resolve(s) == .needsAttention)
        s.isOnline = false
        #expect(SyncStatus.resolve(s) == .offline)
        s.accountAvailable = false
        #expect(SyncStatus.resolve(s) == .cloudUnavailable)
    }

    @MainActor @Test func aBuildWithoutAContainerSaysSoAndDoesNothing() async throws {
        let library = TempLibrary()
        let store = try LibraryStore(directory: library.url)
        let controller = CloudSyncController(store: store, backend: nil)
        await controller.start()
        #expect(controller.availability == .notConfigured && controller.status == .savedLocally)
        await #expect(throws: CloudSyncController.EnableError.notConfigured) { try await controller.setEnabled(true) }
        #expect(try await store.syncIsEnabled() == false)
    }

    @Test func aBundleWithoutTheKeyHasNoConfiguration() {
        #expect(CloudSyncConfiguration.fromBundle(Bundle(for: TempLibrary.self)) == nil)
    }
}

@Suite struct CloudRecordMapperTests {
    private let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestMapper-\(UUID().uuidString)", isDirectory: true)

    private func roundTrip(_ record: SyncRecord) throws -> SyncRecord? {
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let ck = try CloudRecordMapper.cloudRecord(for: record, systemFields: nil, temporaryDirectory: scratch)
        return CloudRecordMapper.incoming(from: ck)?.record
    }

    @Test func everyFieldSurvivesTheTripThroughACKRecord() throws {
        let page = SyncRecord(key: SyncRecordKey(.page, "11111111-2222-3333-4444-555555555555"), fields: [
            "itemID": .string("item"), "sortKey": .string("V"), "width": .double(612), "height": .double(792.25),
            "contentKind": .string("pdfPage"), "assetID": .string(String(repeating: "a", count: 64)), "pdfIndex": .int(71),
            "transform": .string("{}"), "createdAt": .double(816273913.736387), "deletedAt": .double(0.1 + 0.2),
            "assetKind": .string("pdf"), "assetBytes": .int(5_000_000_000), "assetName": .string("Bail 2026 — été.pdf"),
            SyncRecord.layoutVersionField: .int(1),
        ])
        #expect(try roundTrip(page) == page)

        let item = SyncRecord(key: SyncRecordKey(.item, "i"), fields: [
            "kind": .string("notebook"), "name": .string("Notes"), "isFavorite": .int(1), "createdAt": .double(1),
            "modifiedAt": .double(2), "schemaVersion": .int(1), SyncRecord.layoutVersionField: .int(1),
        ])
        #expect(try roundTrip(item) == item)
    }

    @Test func recordNamesCarryTheirTypeAndZone() {
        let key = SyncRecordKey(.object, "ABC.DEF")
        let id = CloudSchema.recordID(key)
        #expect(id.zoneID == CloudSchema.libraryZone && id.recordName == "object.ABC.DEF")
        #expect(CloudSchema.key(id) == key)
        #expect(CloudSchema.key(CloudSchema.originalID("abc")) == nil)
        #expect(CloudSchema.key(CKRecord.ID(recordName: "nonsense", zoneID: CloudSchema.libraryZone)) == nil)
    }

    @Test func whatAPersonWroteIsEncryptedAndIdentifiersAreNot() throws {
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let record = SyncRecord(key: SyncRecordKey(.object, "o"), fields: [
            "pageID": .string("p"), "zKey": .string("V"), "kind": .string("text"), "payload": .string("{\"secret\":1}"),
            "modifiedAt": .double(1),
        ])
        let ck = try CloudRecordMapper.cloudRecord(for: record, systemFields: nil, temporaryDirectory: scratch)
        #expect(ck["payload"] == nil)
        #expect(ck.encryptedValues["payload"] as String? == "{\"secret\":1}")
        #expect(ck["pageID"] as? String == "p")
        #expect(ck.recordType == "PageObject")
    }

    @Test func textTooLargeForARecordTravelsAsAFile() throws {
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let long = String(repeating: "stroke ", count: 60_000)
        let record = SyncRecord(key: SyncRecordKey(.object, "o"), fields: [
            "pageID": .string("p"), "zKey": .string("V"), "kind": .string("ink"), "payload": .string(long), "modifiedAt": .double(1),
            SyncRecord.layoutVersionField: .int(1),
        ])
        let ck = try CloudRecordMapper.cloudRecord(for: record, systemFields: nil, temporaryDirectory: scratch)
        #expect(ck["payloadFile"] is CKAsset)
        #expect(ck.encryptedValues["payload"] as String? == nil)
        #expect(CloudRecordMapper.incoming(from: ck)?.record == record)
    }

    @Test func aRecordSentAgainKeepsTheServersChangeTag() throws {
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let record = SyncRecord(key: SyncRecordKey(.folder, "f"), fields: ["name": .string("A"), "createdAt": .double(1), "modifiedAt": .double(1)])
        let first = try CloudRecordMapper.cloudRecord(for: record, systemFields: nil, temporaryDirectory: scratch)
        let system = CloudRecordMapper.systemFields(of: first)
        let second = try CloudRecordMapper.cloudRecord(for: record, systemFields: system, temporaryDirectory: scratch)
        #expect(second.recordID == first.recordID && second.recordType == "Folder")
        // System fields from some other record are not trusted.
        let other = try CloudRecordMapper.cloudRecord(for: SyncRecord(key: SyncRecordKey(.folder, "g"), fields: record.fields),
                                                      systemFields: system, temporaryDirectory: scratch)
        #expect(other.recordID.recordName == "folder.g")
    }
}

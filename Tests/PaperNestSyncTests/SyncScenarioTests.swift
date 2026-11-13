import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore
@testable import PaperNestSync

/// Several devices, one pretend iCloud. Each test ends by comparing the
/// devices' whole libraries, record for record: converging is the claim.
///
/// These run the real store, the real outbox, the real merge and conflict
/// rules, the real controller and the real asset mover. What they do not run
/// is CloudKit; see `FakeCloud`.
@MainActor
@Suite struct SyncScenarioTests {
    private func sync(_ devices: TestDevice..., rounds: Int = 3) async {
        for _ in 0..<rounds {
            for device in devices { await device.syncNow() }
        }
    }

    private func expectSame(_ devices: TestDevice..., sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let first = try await devices[0].dump()
        #expect(!first.isEmpty, sourceLocation: sourceLocation)
        for device in devices.dropFirst() {
            let other = try await device.dump()
            #expect(other == first, "\(device.name) differs from \(devices[0].name)", sourceLocation: sourceLocation)
        }
    }

    // MARK: - Basic synchronization

    @Test func notebookTravelsFromPadToPhoneToMacAndStaysEditable() async throws {
        let cloud = FakeCloud()
        let pad = try await TestDevice.syncing("iPad", cloud: cloud)
        let phone = try await TestDevice.syncing("iPhone", cloud: cloud)
        let mac = try await TestDevice.syncing("Mac", cloud: cloud)

        let notebook = try await pad.makeNotebook("Lecture notes", pages: 2)
        let padPages = try await pad.pages(notebook)
        try await pad.draw(on: padPages[0])
        await sync(pad, phone)

        // On the phone it is a notebook with one real stroke, not a picture.
        let onPhone = try #require(try await phone.store.item(notebook.id))
        #expect(onPhone.kind == .notebook && onPhone.name == "Lecture notes")
        let phonePages = try await phone.pages(onPhone)
        #expect(phonePages.map(\.id) == padPages.map(\.id))
        let strokes = try await phone.store.objects(on: phonePages[0].id)
        #expect(strokes.count == 1)
        guard case .ink(let ink) = strokes[0].payload else { Issue.record("not ink"); return }
        #expect(ink.points.count == 3)

        // The phone adds handwriting; the Mac sees both strokes.
        try await phone.draw(on: phonePages[0], x: 200, color: RGBAColor(red: 1, green: 0, blue: 0))
        await sync(phone, mac, pad)
        #expect(try await mac.store.objects(on: padPages[0].id).count == 2)
        try await expectSame(pad, phone, mac)
        #expect(pad.sync.status == .upToDate && phone.sync.status == .upToDate && mac.sync.status == .upToDate)
    }

    @Test func foldersRenamesMovesFavoritesAndLabelsReachEveryDevice() async throws {
        let cloud = FakeCloud()
        let mac = try await TestDevice.syncing("Mac", cloud: cloud)
        let pad = try await TestDevice.syncing("iPad", cloud: cloud)

        let folder = try await mac.store.createFolder(named: "Taxes")
        let sub = try await mac.store.createFolder(named: "2026", parentID: folder.id)
        let pdf = try await mac.makeDocument("Receipt")
        await sync(mac, pad)
        #expect(try await pad.store.folders().map(\.name).sorted() == ["2026", "Taxes"])

        // Changes made on the iPad to a document the Mac created.
        try await pad.store.rename(pdf.id, to: "Receipt March")
        try await pad.store.setFavorite(pdf.id, true)
        try await pad.store.move([pdf.id], to: sub.id)
        try await pad.store.setColorLabel(.purple, for: [pdf.id])
        try await pad.store.renameFolder(folder.id, to: "Tax returns")
        await sync(pad, mac)

        let onMac = try #require(try await mac.store.item(pdf.id))
        #expect(onMac.name == "Receipt March" && onMac.isFavorite && onMac.folderID == sub.id && onMac.colorLabel == .purple)
        #expect(try await mac.store.folders().first { $0.id == folder.id }?.name == "Tax returns")
        // Renaming and moving kept its identity: still one document.
        #expect(try await mac.store.items(in: .all).count == 1)
        try await expectSame(mac, pad)
    }

    // MARK: - Offline

    @Test func workDoneOfflineIsKeptAndSentWhenTheNetworkReturns() async throws {
        let cloud = FakeCloud()
        let pad = try await TestDevice.syncing("iPad", cloud: cloud)
        let mac = try await TestDevice.syncing("Mac", cloud: cloud)
        var notes: [LibraryItem] = []
        for name in ["One", "Two", "Three"] { notes.append(try await pad.makeNotebook(name)) }
        await sync(pad, mac)

        cloud.isOnline = false
        pad.sync.setOnline(false)
        for note in notes { try await pad.draw(on: try await pad.pages(note)[0]) }
        let folder = try await pad.store.createFolder(named: "Offline folder")
        let scan = try await pad.makeDocument("Scan", pages: 3, folder: folder.id)
        await pad.syncNow()
        #expect(pad.sync.status == .offline)
        #expect(pad.sync.counts.pendingChanges > 0)
        // Nothing reached the Mac, and nothing on the iPad was lost.
        #expect(try await pad.store.items(in: .all).count == 4)

        // Meanwhile the Mac changes something else.
        try await mac.store.rename(notes[0].id, to: "One (renamed on Mac)")

        cloud.isOnline = true
        pad.sync.setOnline(true)
        await sync(pad, mac)
        #expect(try await mac.store.items(in: .all).count == 4)
        #expect(try await mac.pages(scan).count == 3)
        #expect(try await mac.store.objects(on: try await mac.pages(notes[2])[0].id).count == 1)
        // The Mac's rename and the iPad's stroke on the same notebook both stand.
        #expect(try await pad.store.item(notes[0].id)?.name == "One (renamed on Mac)")
        #expect(try await mac.store.objects(on: try await mac.pages(notes[0])[0].id).count == 1)
        #expect(pad.sync.counts.pendingChanges == 0 && pad.sync.status == .upToDate)
        try await expectSame(pad, mac)
    }

    // MARK: - Conflicts

    @Test func independentStrokesOnTheSamePageBothSurvive() async throws {
        let cloud = FakeCloud()
        let pad = try await TestDevice.syncing("iPad", cloud: cloud)
        let mac = try await TestDevice.syncing("Mac", cloud: cloud)
        let notebook = try await pad.makeNotebook("Shared")
        await sync(pad, mac)
        let page = try await pad.pages(notebook)[0]

        try await pad.draw(on: page, x: 10)
        try await mac.draw(on: page, x: 300)
        await sync(pad, mac)
        #expect(try await pad.store.objects(on: page.id).count == 2)
        #expect(pad.sync.conflicts.isEmpty && mac.sync.conflicts.isEmpty)
        try await expectSame(pad, mac)
    }

    @Test func aRotationHereAndACropThereAreMergedWithoutAConflict() async throws {
        let cloud = FakeCloud()
        let pad = try await TestDevice.syncing("iPad", cloud: cloud)
        let mac = try await TestDevice.syncing("Mac", cloud: cloud)
        let pdf = try await pad.makeDocument("Lease")
        await sync(pad, mac)
        let page = try await pad.pages(pdf)[0]

        try await pad.store.updateTransform(page.id, to: PageTransform(rotation: .clockwise90))
        try await mac.store.updateTransform(page.id, to: PageTransform(crop: NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)))
        await sync(pad, mac)

        let merged = try #require(try await mac.store.page(page.id)).transform
        #expect(merged.rotation == .clockwise90)
        #expect(merged.crop.isApproximately(NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)))
        #expect(try await mac.pages(pdf).count == 2)
        #expect(pad.sync.conflicts.isEmpty && mac.sync.conflicts.isEmpty)
        try await expectSame(pad, mac)
    }

    @Test func theSamePageTurnedTwoWaysKeepsBothVersionsAndSaysSo() async throws {
        let cloud = FakeCloud()
        let pad = try await TestDevice.syncing("iPad", cloud: cloud)
        let mac = try await TestDevice.syncing("Mac", cloud: cloud)
        let pdf = try await pad.makeDocument("Contract", pages: 2)
        await sync(pad, mac)
        let page = try await pad.pages(pdf)[0]
        try await pad.draw(on: page)
        await sync(pad, mac)

        // Both offline, both at the same revision, both turn page 1.
        try await pad.store.updateTransform(page.id, to: PageTransform(rotation: .clockwise90))
        try await mac.store.updateTransform(page.id, to: PageTransform(rotation: .half))
        await pad.syncNow()
        await mac.syncNow()

        // The Mac was second: the iPad's version holds the page, the Mac's
        // is the page right after it, with the ink it had.
        #expect(mac.sync.conflicts.count == 1)
        #expect(mac.sync.status == .conflict)
        let conflict = try #require(mac.sync.conflicts.first)
        #expect(conflict.kind == .pageVersion && conflict.itemID == pdf.id && conflict.itemName == "Contract")
        let macPages = try await mac.pages(pdf)
        #expect(macPages.count == 3)
        #expect(macPages[0].id == page.id && macPages[0].transform.rotation == .clockwise90)
        #expect(macPages[1].id.rawValue == conflict.copyID && macPages[1].transform.rotation == .half)
        #expect(try await mac.store.objects(on: macPages[1].id).count == 1)

        // Deterministic: the iPad ends with exactly the same three pages.
        await sync(pad, mac)
        try await expectSame(pad, mac)
        #expect(try await pad.pages(pdf).map(\.transform.rotation) == [.clockwise90, .half, .none])

        // Reviewing it clears the status; choosing to drop the copy removes it everywhere.
        await mac.sync.resolveConflict(conflict.id, keepingCopy: false)
        #expect(mac.sync.conflicts.isEmpty)
        await sync(mac, pad)
        #expect(try await pad.pages(pdf).count == 2)
        try await expectSame(pad, mac)
    }

    @Test func theSameTextBoxEditedTwiceKeepsBothTexts() async throws {
        let cloud = FakeCloud()
        let pad = try await TestDevice.syncing("iPad", cloud: cloud)
        let mac = try await TestDevice.syncing("Mac", cloud: cloud)
        let notebook = try await pad.makeNotebook("Minutes")
        let page = try await pad.pages(notebook)[0]
        let box = PageObject(pageID: page.id, zKey: "V",
                             payload: .text(TextBox(frame: CGRect(x: 10, y: 10, width: 200, height: 40), text: "Draft")),
                             modifiedAt: Date())
        try await pad.store.saveObject(box)
        await sync(pad, mac)

        var padEdit = box, macEdit = box
        padEdit.payload = .text(TextBox(frame: CGRect(x: 10, y: 10, width: 200, height: 40), text: "Agreed on Tuesday"))
        macEdit.payload = .text(TextBox(frame: CGRect(x: 10, y: 10, width: 200, height: 40), text: "Agreed on Friday"))
        try await pad.store.saveObject(padEdit)
        try await mac.store.saveObject(macEdit)
        await sync(pad, mac)

        let texts = try await pad.store.objects(on: page.id).compactMap { object -> String? in
            if case .text(let t) = object.payload { return t.text }
            return nil
        }
        #expect(texts.sorted() == ["Agreed on Friday", "Agreed on Tuesday"])
        #expect(mac.sync.conflicts.first?.kind == .objectVersion)
        try await expectSame(pad, mac)
    }

    @Test func twoRenamesSettleOnTheLaterOneEverywhere() async throws {
        let cloud = FakeCloud()
        let pad = try await TestDevice.syncing("iPad", cloud: cloud)
        let mac = try await TestDevice.syncing("Mac", cloud: cloud)
        let pdf = try await pad.makeDocument("Untitled scan")
        await sync(pad, mac)

        try await pad.store.rename(pdf.id, to: "Invoice")
        try await Task.sleep(for: .milliseconds(20))
        try await mac.store.rename(pdf.id, to: "Invoice 0042")
        await sync(pad, mac)
        #expect(try await pad.store.item(pdf.id)?.name == "Invoice 0042")
        #expect(try await mac.store.item(pdf.id)?.name == "Invoice 0042")
        try await expectSame(pad, mac)
    }

    // MARK: - Deleting

    @Test func recentlyDeletedAndRestoreCrossDevices() async throws {
        let cloud = FakeCloud()
        let pad = try await TestDevice.syncing("iPad", cloud: cloud)
        let mac = try await TestDevice.syncing("Mac", cloud: cloud)
        let pdf = try await pad.makeDocument("Old lease")
        await sync(pad, mac)

        try await pad.store.moveToRecentlyDeleted([pdf.id])
        await sync(pad, mac)
        #expect(try await mac.store.items(in: .all).isEmpty)
        #expect(try await mac.store.items(in: .recentlyDeleted).map(\.id) == [pdf.id])

        try await mac.store.restore([pdf.id])
        await sync(mac, pad)
        #expect(try await pad.store.items(in: .all).map(\.id) == [pdf.id])
        #expect(try await pad.pages(pdf).count == 2)
        try await expectSame(pad, mac)

        // Deleted for good on one device once both have it in the bin.
        try await pad.store.moveToRecentlyDeleted([pdf.id])
        await sync(pad, mac)
        try await pad.store.deletePermanently([pdf.id])
        await sync(pad, mac)
        #expect(try await mac.store.item(pdf.id) == nil)
        #expect(cloud.recordCount(account: "account-A") == 0)
    }

    @Test func aDocumentDeletedForGoodElsewhereGoesToTheBinHereAndCanBeRestored() async throws {
        let cloud = FakeCloud()
        let pad = try await TestDevice.syncing("iPad", cloud: cloud)
        let mac = try await TestDevice.syncing("Mac", cloud: cloud)
        let pdf = try await pad.makeDocument("Passport scan", pages: 3)
        try await pad.draw(on: try await pad.pages(pdf)[0])
        await sync(pad, mac)

        // The Mac is away while the iPad bins it and empties the bin.
        try await pad.store.moveToRecentlyDeleted([pdf.id])
        try await pad.store.deletePermanently([pdf.id])
        await pad.syncNow()
        #expect(cloud.recordCount(account: "account-A") == 0)

        // The Mac never saw it enter the bin, so it is not erased there.
        await mac.syncNow()
        #expect(try await mac.store.items(in: .recentlyDeleted).map(\.id) == [pdf.id])
        #expect(try await mac.store.items(in: .all).isEmpty)

        // Restoring it sends the whole document back.
        try await mac.store.restore([pdf.id])
        await sync(mac, pad)
        #expect(try await pad.pages(pdf).count == 3)
        #expect(try await pad.store.objects(on: try await pad.pages(pdf)[0].id).count == 1)
        try await expectSame(pad, mac)
    }

    @Test func anEditMadeOfflineBeatsADeletionMadeElsewhere() async throws {
        let cloud = FakeCloud()
        let pad = try await TestDevice.syncing("iPad", cloud: cloud)
        let mac = try await TestDevice.syncing("Mac", cloud: cloud)
        let notebook = try await pad.makeNotebook("Journal", pages: 2)
        await sync(pad, mac)
        let pages = try await pad.pages(notebook)

        // A page: the iPad deletes it, the Mac (not knowing) writes on it.
        try await pad.store.deletePages([pages[1].id])
        try await mac.draw(on: pages[1])
        await sync(pad, mac)
        #expect(try await pad.pages(notebook).count == 2)
        #expect(try await pad.store.objects(on: pages[1].id).count == 1)
        try await expectSame(pad, mac)

        // A whole document: the iPad deletes it for good, the Mac writes in it.
        try await pad.store.moveToRecentlyDeleted([notebook.id])
        try await pad.store.deletePermanently([notebook.id])
        try await mac.draw(on: pages[0])
        await sync(pad, mac)
        #expect(try await pad.store.item(notebook.id)?.isDeleted == false)
        #expect(try await pad.store.objects(on: pages[0].id).count == 1)
        try await expectSame(pad, mac)
    }

    @Test func aStrokeErasedHereAndRecoloredThereIsKept() async throws {
        let cloud = FakeCloud()
        let pad = try await TestDevice.syncing("iPad", cloud: cloud)
        let mac = try await TestDevice.syncing("Mac", cloud: cloud)
        let notebook = try await pad.makeNotebook("Sketch")
        let page = try await pad.pages(notebook)[0]
        let stroke = try await pad.draw(on: page)
        await sync(pad, mac)

        try await pad.store.deleteObject(stroke.id)
        var recolored = stroke
        if case .ink(var ink) = stroke.payload {
            ink.color = RGBAColor(red: 0, green: 0, blue: 1)
            recolored.payload = .ink(ink)
        }
        try await mac.store.saveObject(recolored)
        await sync(pad, mac)
        #expect(try await pad.store.objects(on: page.id).map(\.payload) == [recolored.payload])
        try await expectSame(pad, mac)
    }

    @Test func aDeletedPageIsKeptAsATombstoneWhileSyncIsOn() async throws {
        let cloud = FakeCloud()
        let pad = try await TestDevice.syncing("iPad", cloud: cloud)
        let pdf = try await pad.makeDocument("Report", pages: 3)
        let pages = try await pad.pages(pdf)
        try await pad.store.deletePages([pages[2].id])

        // Not yet sent: a relaunch must not turn it into a hard delete.
        try await pad.relaunch()
        #expect(try await pad.store.syncSnapshot(SyncRecordKey(.page, pages[2].id.rawValue)) != nil)
        await pad.syncNow()
        // Sent, but still inside the tombstone period.
        try await pad.relaunch()
        #expect(try await pad.store.syncSnapshot(SyncRecordKey(.page, pages[2].id.rawValue)) != nil)
        // After it, the page goes for good and the server is told.
        try await pad.store.testBackdateDeletedPages(days: 31)
        try await pad.relaunch()
        #expect(try await pad.store.syncSnapshot(SyncRecordKey(.page, pages[2].id.rawValue)) == nil)
        await pad.syncNow()
        #expect(cloud.record(SyncRecordKey(.page, pages[2].id.rawValue)) == nil)
        #expect(cloud.record(SyncRecordKey(.page, pages[1].id.rawValue)) != nil)
    }

    @Test func aFolderDeletedElsewhereDoesNotSwallowADocumentPutInItOffline() async throws {
        let cloud = FakeCloud()
        let pad = try await TestDevice.syncing("iPad", cloud: cloud)
        let mac = try await TestDevice.syncing("Mac", cloud: cloud)
        let folder = try await pad.store.createFolder(named: "Inbox")
        await sync(pad, mac)

        try await pad.store.deleteFolder(folder.id)
        let late = try await mac.makeDocument("Filed late", folder: folder.id)
        await sync(pad, mac)
        #expect(try await mac.store.item(late.id)?.folderID == nil)
        #expect(try await pad.store.items(in: .folder(nil)).map(\.id) == [late.id])
        try await expectSame(pad, mac)
    }

    // MARK: - Originals

    @Test func aHundredPagePDFArrivesWholeAndVerified() async throws {
        let cloud = FakeCloud()
        let mac = try await TestDevice.syncing("Mac", cloud: cloud)
        let pad = try await TestDevice.syncing("iPad", cloud: cloud)
        let bytes = TestDevice.pdfBytes("big", size: 2_000_000)
        let pdf = try await mac.makeDocument("Manual", pages: 100, bytes: bytes)
        try await mac.draw(on: try await mac.pages(pdf)[71])
        await sync(mac, pad)

        let padPages = try await pad.pages(pdf)
        #expect(padPages.count == 100)
        #expect(padPages.map(\.sortKey) == (try await mac.pages(pdf)).map(\.sortKey))
        let assetID = try #require(padPages[0].content.assetID)
        #expect(assetID == AssetFileStore.assetID(for: bytes))
        let (downloaded, kind) = try await pad.store.assetData(assetID)
        #expect(downloaded == bytes && kind == .pdf)
        try pad.store.assets.verify(assetID, kind: .pdf)
        #expect(try await pad.store.integrityCheck().isEmpty)
        // One hundred pages, one upload of the file.
        #expect(cloud.blobCount(account: "account-A") == 1 && cloud.blobUploadCount == 1)

        // An edit to page 72 sends that stroke, not the document again.
        let before = cloud.savedRecordCount
        try await pad.draw(on: padPages[71], x: 250)
        await sync(pad, mac)
        #expect(cloud.savedRecordCount - before <= 2)
        #expect(cloud.blobUploadCount == 1)
        try await expectSame(mac, pad)
    }

    @Test func picturesFileItemsAndSignaturesSync() async throws {
        let cloud = FakeCloud()
        let mac = try await TestDevice.syncing("Mac", cloud: cloud)
        let pad = try await TestDevice.syncing("iPad", cloud: cloud)

        // A scan: image pages.
        let scanBytes = Data("JPEG-synthetic-scan".utf8)
        let scan = try mac.store.assets.store(scanBytes, kind: .jpeg, originalFilename: "scan.jpg")
        let scanned = try await mac.store.createItem(kind: .document, name: "Scanned receipt", pages: [
            LibraryStore.NewPage(sourceSize: CGSize(width: 600, height: 800), content: .image(scan.id),
                                 transform: PageTransform(crop: NormalizedRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9),
                                                          rotation: .clockwise90, filter: .blackAndWhite)),
        ], assets: [scan])
        // A picture placed on a notebook page.
        let notebook = try await mac.makeNotebook("Trip")
        let page = try await mac.pages(notebook)[0]
        let picture = try mac.store.assets.store(Data("PNG-synthetic-photo".utf8), kind: .png, originalFilename: "photo.png")
        try await mac.store.placeImage(picture, on: page.id, frame: CGRect(x: 20, y: 20, width: 100, height: 80))
        // A file kept as it is.
        let audio = try mac.store.assets.store(Data("RIFF-synthetic-audio".utf8), kind: .file, originalFilename: "memo.wav")
        let file = try await mac.store.createFileItem(named: "Voice memo", asset: audio, uti: "com.microsoft.waveform-audio",
                                                      originalFilename: "memo.wav")
        try await mac.store.saveSignature(SavedSignature(id: UUID().uuidString, name: "Mine", strokes: [
            InkStroke(tool: .pen, color: .black, width: 2, points: [InkPoint(x: 0, y: 0), InkPoint(x: 10, y: 10)]),
        ], createdAt: Date()))
        await sync(mac, pad)

        let scannedPage = try #require(try await pad.pages(scanned).first)
        #expect(scannedPage.transform.rotation == .clockwise90 && scannedPage.transform.filter == .blackAndWhite)
        #expect(try await pad.store.assetData(scan.id).0 == scanBytes)
        let placed = try await pad.store.objects(on: page.id)
        #expect(placed.count == 1)
        #expect(try await pad.store.assetData(picture.id).1 == .png)
        let payload = try #require(try await pad.store.filePayload(file.id))
        #expect(payload.originalFilename == "memo.wav" && payload.uti == "com.microsoft.waveform-audio")
        #expect(try await pad.store.assetData(audio.id).0 == Data("RIFF-synthetic-audio".utf8))
        #expect(try await pad.store.signatures().map(\.name) == ["Mine"])
        #expect(pad.sync.cloudOnlyItems.isEmpty)
        try await expectSame(mac, pad)
    }

    @Test func documentsCanStayInICloudUntilWanted() async throws {
        let cloud = FakeCloud()
        let mac = try await TestDevice.syncing("Mac", cloud: cloud)
        let phone = try await TestDevice.syncing("iPhone", cloud: cloud)
        await phone.sync.setDownloadsOnDemand(true)
        let bytes = TestDevice.pdfBytes("atlas", size: 50_000)
        let pdf = try await mac.makeDocument("Atlas", pages: 5, bytes: bytes)
        await sync(mac, phone)

        // Known, listed, not downloaded — and it says so.
        let assetID = try #require(try await phone.pages(pdf).first?.content.assetID)
        #expect(try await phone.pages(pdf).count == 5)
        #expect(try await phone.store.assetRecord(assetID)?.availability == .remoteOnly)
        #expect(phone.sync.cloudOnlyItems == [pdf.id])
        await #expect(throws: StoreError.assetMissing(assetID.sha256)) { _ = try await phone.store.assetData(assetID) }

        // A damaged download is refused and nothing is marked as present.
        cloud.corruptDownloads = true
        #expect(await phone.sync.download(pdf.id) == false)
        #expect(try await phone.store.assetRecord(assetID)?.availability == .remoteOnly)
        cloud.corruptDownloads = false

        #expect(await phone.sync.download(pdf.id))
        #expect(try await phone.store.assetData(assetID).0 == bytes)
        #expect(phone.sync.cloudOnlyItems.isEmpty)

        // Freed again; iCloud still has it, and it comes back.
        await phone.sync.removeDownloads(pdf.id)
        #expect(try await phone.store.assetRecord(assetID)?.availability == .remoteOnly)
        #expect(!FileManager.default.fileExists(atPath: phone.store.assets.url(for: assetID, kind: .pdf).path))
        #expect(await phone.sync.download(pdf.id))
    }

    @Test func aLocalCopyIsNeverFreedUnlessICloudReallyHasIt() async throws {
        let cloud = FakeCloud()
        let mac = try await TestDevice.syncing("Mac", cloud: cloud)
        await mac.syncNow()
        cloud.isOnline = false
        let pdf = try await mac.makeDocument("Only copy")
        let assetID = try #require(try await mac.pages(pdf).first?.content.assetID)

        // Not uploaded yet.
        await mac.sync.removeDownloads(pdf.id)
        #expect(try await mac.store.assetRecord(assetID)?.availability == .local)
        #expect(try await mac.store.testAssetState(assetID) == "pendingUpload")

        // Uploaded, then lost from iCloud behind our back.
        cloud.isOnline = true
        await mac.syncNow()
        #expect(try await mac.store.testAssetState(assetID) == "uploaded")
        try cloud.removeBlob(assetID.sha256)
        await mac.sync.removeDownloads(pdf.id)
        #expect(try await mac.store.assetRecord(assetID)?.availability == .local)
        #expect(try await mac.store.assetData(assetID).0 == TestDevice.pdfBytes("Only copy"))
    }

    @Test func originalsLeaveICloudOnlyAfterTheTombstonePeriod() async throws {
        let cloud = FakeCloud()
        let mac = try await TestDevice.syncing("Mac", cloud: cloud)
        let pdf = try await mac.makeDocument("Temporary")
        let assetID = try #require(try await mac.pages(pdf).first?.content.assetID)
        await mac.syncNow()
        #expect(cloud.blobCount(account: "account-A") == 1)

        try await mac.store.moveToRecentlyDeleted([pdf.id])
        try await mac.store.deletePermanently([pdf.id])
        await mac.syncNow()
        #expect(try await mac.store.testAssetState(assetID) == "pendingRemoteDelete")
        #expect(cloud.blobCount(account: "account-A") == 1)

        try await mac.store.testBackdateAssetTombstones(days: 31)
        await mac.syncNow()
        #expect(cloud.blobCount(account: "account-A") == 0)
        #expect(try await mac.store.testAssetState(assetID) == nil)
    }

    // MARK: - First-time migration

    @Test func anExistingLibraryIsUploadedOnceHoweverOftenSyncIsTurnedOn() async throws {
        let cloud = FakeCloud()
        let pad = try TestDevice("iPad", cloud: cloud)
        await pad.sync.start()
        // A library that existed long before sync.
        let folder = try await pad.store.createFolder(named: "School")
        for index in 0..<4 { try await pad.makeNotebook("Notebook \(index)", pages: 2) }
        for index in 0..<6 { try await pad.makeDocument("PDF \(index)", pages: 3, folder: folder.id) }
        #expect(try await pad.store.testOutboxCount() == 0)
        #expect(pad.sync.status == .savedLocally)
        let before = try await pad.dump()

        try await pad.sync.setEnabled(true)
        // Folder 1 + items 10 + pages 8 + 18.
        #expect(pad.sync.counts.pendingChanges == 37)
        #expect(pad.sync.counts.pendingUploads == 6)
        // The library as it was, kept beside it.
        let backups = try FileManager.default.contentsOfDirectory(atPath: pad.directory.appendingPathComponent("Backups").path)
        #expect(backups.count == 1 && backups[0].hasPrefix("before-icloud-sync-"))
        await pad.syncNow()
        #expect(pad.sync.counts.pendingChanges == 0 && pad.sync.status == .upToDate)
        #expect(cloud.recordCount(account: "account-A") == 37 && cloud.blobCount(account: "account-A") == 6)
        #expect(try await pad.dump() == before)

        // Off and on again, twice: nothing is queued, nothing is sent.
        let sent = cloud.savedRecordCount
        for _ in 0..<2 {
            try await pad.sync.setEnabled(false)
            try await pad.sync.setEnabled(true)
            #expect(pad.sync.counts.pendingChanges == 0)
            await pad.syncNow()
        }
        #expect(cloud.savedRecordCount == sent && cloud.recordCount(account: "account-A") == 37)
        #expect(try FileManager.default.contentsOfDirectory(atPath: pad.directory.appendingPathComponent("Backups").path).count == 1)

        // Changes made while it was off are found when it comes back on.
        try await pad.sync.setEnabled(false)
        let extra = try await pad.makeNotebook("Written while off")
        let doomed = try #require(try await pad.store.items(in: .all).first { $0.item.name == "PDF 0" })
        try await pad.store.moveToRecentlyDeleted([doomed.id])
        try await pad.store.deletePermanently([doomed.id])
        try await pad.sync.setEnabled(true)
        await pad.syncNow()
        #expect(cloud.record(SyncRecordKey(.item, extra.id.rawValue)) != nil)
        #expect(cloud.record(SyncRecordKey(.item, doomed.id.rawValue)) == nil)
        #expect(cloud.recordCount(account: "account-A") == 37 + 2 - 4)
    }

    @Test func aMigrationCutShortResumesWithoutDuplicates() async throws {
        let cloud = FakeCloud()
        let pad = try TestDevice("iPad", cloud: cloud)
        await pad.sync.start()
        for index in 0..<8 { try await pad.makeDocument("PDF \(index)", pages: 4) }
        try await pad.sync.setEnabled(true)

        // The connection drops partway through, then the app is killed.
        cloud.acceptLimit = 13
        await pad.syncNow()
        #expect(pad.sync.counts.pendingChanges > 0)
        cloud.acceptLimit = nil
        try await pad.relaunch()
        #expect(pad.sync.isEnabled && pad.sync.counts.pendingChanges > 0)
        await pad.syncNow()
        #expect(pad.sync.counts.pendingChanges == 0)
        #expect(cloud.recordCount(account: "account-A") == 8 + 32)

        // A second device ends up with exactly the same library.
        let mac = try await TestDevice.syncing("Mac", cloud: cloud)
        await sync(mac, pad)
        #expect(try await mac.store.items(in: .all).count == 8)
        try await expectSame(pad, mac)
    }

    @Test func anUploadWhoseAnswerNeverArrivedIsNotSentAsADuplicate() async throws {
        let cloud = FakeCloud()
        let pad = try await TestDevice.syncing("iPad", cloud: cloud)
        let notebook = try await pad.makeNotebook("Killed mid-upload", pages: 3)
        try await pad.draw(on: try await pad.pages(notebook)[0])

        // The server stored it; the app died before hearing so.
        await pad.backend.setLoseNextAnswer(true)
        await pad.syncNow()
        #expect(cloud.recordCount(account: "account-A") == 5)
        #expect(pad.sync.counts.pendingChanges == 5)

        try await pad.relaunch()
        await pad.syncNow()
        #expect(pad.sync.counts.pendingChanges == 0)
        #expect(cloud.recordCount(account: "account-A") == 5)
        #expect(pad.sync.conflicts.isEmpty)
        #expect(try await pad.store.items(in: .all).count == 1)
        #expect(try await pad.pages(notebook).count == 3)
    }

    @Test func twoDevicesHoldingTheSameLibraryDoNotDoubleIt() async throws {
        // A library restored from the same backup onto two devices, then
        // sync turned on for both.
        let cloud = FakeCloud()
        let pad = try await TestDevice.syncing("iPad", cloud: cloud)
        for index in 0..<3 { try await pad.makeDocument("Doc \(index)") }
        await pad.syncNow()
        let mac = try await TestDevice.syncing("Mac", cloud: cloud)
        await mac.syncNow()
        // Forget everything the cloud confirmed, as a fresh install would.
        try await mac.store.syncSetEnabled(false)
        try await mac.store.syncResetCloudKnowledge()
        try await mac.sync.setEnabled(true)
        #expect(mac.sync.counts.pendingChanges == 9)
        await sync(mac, pad)
        #expect(mac.sync.conflicts.isEmpty)
        #expect(cloud.recordCount(account: "account-A") == 9)
        #expect(try await mac.store.items(in: .all).count == 3)
        try await expectSame(pad, mac)
    }

    // MARK: - Trouble

    @Test func aFullICloudKeepsEverythingQueuedAndSaysSo() async throws {
        let cloud = FakeCloud()
        let pad = try await TestDevice.syncing("iPad", cloud: cloud)
        await pad.syncNow()
        cloud.quotaExceeded = true
        let pdf = try await pad.makeDocument("Too big for iCloud")
        try await pad.makeNotebook("Small note")
        await pad.syncNow()
        #expect(pad.sync.failure == .quotaExceeded)
        #expect(pad.sync.status == .needsAttention)
        #expect(pad.sync.counts.pendingChanges == 5 && pad.sync.counts.pendingUploads == 1)
        #expect(try await pad.pages(pdf).count == 2)

        cloud.quotaExceeded = false
        await pad.syncNow()
        #expect(pad.sync.failure == nil && pad.sync.status == .upToDate)
        #expect(cloud.recordCount(account: "account-A") == 5)
    }

    @Test func aDifferentICloudAccountGetsNothingUntilThePersonDecides() async throws {
        let cloud = FakeCloud()
        let pad = try await TestDevice.syncing("iPad", cloud: cloud)
        try await pad.makeDocument("Private to account A")
        await pad.syncNow()
        let onA = cloud.recordCount(account: "account-A")
        #expect(onA == 3)

        // Signed out: nothing is deleted, edits keep being recorded.
        cloud.signIn(nil)
        await pad.sync.evaluateAccount()
        #expect(pad.sync.availability == .noAccount && pad.sync.status == .cloudUnavailable)
        try await pad.makeNotebook("Written while signed out")
        #expect(try await pad.store.items(in: .all).count == 2)

        // Someone else signs in. Sync does not start on its own.
        cloud.signIn("account-B")
        await pad.sync.evaluateAccount()
        #expect(pad.sync.availability == .accountChanged)
        await pad.syncNow()
        #expect(cloud.recordCount(account: "account-B") == 0 && cloud.blobCount(account: "account-B") == 0)
        #expect(await pad.sync.enablingWouldSwitchAccounts())

        // Choosing to stop keeps everything local and sends nothing.
        try await pad.sync.resolveAccountChange(.stopSyncing)
        #expect(!pad.sync.isEnabled && pad.sync.status == .savedLocally)
        #expect(try await pad.store.items(in: .all).count == 2)
        #expect(cloud.recordCount(account: "account-B") == 0)

        // Choosing to sync with the new account uploads the library there,
        // as new, and leaves the first account's data exactly as it was.
        try await pad.sync.resolveAccountChange(.syncWithCurrentAccount)
        await pad.syncNow()
        #expect(cloud.recordCount(account: "account-B") == 5)
        #expect(cloud.recordCount(account: "account-A") == onA)
        #expect(pad.sync.status == .upToDate)

        // Back on the first account: again nothing moves by itself.
        cloud.signIn("account-A")
        await pad.sync.evaluateAccount()
        #expect(pad.sync.availability == .accountChanged)
    }

    @Test func deletingICloudDataLeavesEveryDeviceItsDocuments() async throws {
        let cloud = FakeCloud()
        let pad = try await TestDevice.syncing("iPad", cloud: cloud)
        let mac = try await TestDevice.syncing("Mac", cloud: cloud)
        try await pad.makeDocument("Keep me")
        await sync(pad, mac)

        try await pad.sync.deleteCloudData()
        #expect(cloud.recordCount(account: "account-A") == 0 && cloud.blobCount(account: "account-A") == 0)
        #expect(!pad.sync.isEnabled)
        #expect(try await pad.store.items(in: .all).count == 1)

        // The Mac notices, stops, and keeps its copy rather than re-uploading
        // what someone just chose to remove.
        await mac.syncNow()
        #expect(!mac.sync.isEnabled && mac.sync.failure == .cloudDataDeleted)
        #expect(try await mac.store.items(in: .all).count == 1)
        #expect(try await mac.store.integrityCheck().isEmpty)
        await mac.syncNow()
        #expect(cloud.recordCount(account: "account-A") == 0)
    }

    @Test func turningSyncOffDeletesNothingAnywhere() async throws {
        let cloud = FakeCloud()
        let pad = try await TestDevice.syncing("iPad", cloud: cloud)
        try await pad.makeDocument("Stays put")
        await pad.syncNow()
        let before = try await pad.dump()
        try await pad.sync.setEnabled(false)
        #expect(try await pad.dump() == before)
        #expect(cloud.recordCount(account: "account-A") == 3 && cloud.blobCount(account: "account-A") == 1)
        #expect(pad.sync.status == .savedLocally)
    }

    @Test func recordsThatArriveBeforeTheirDocumentWaitForIt() async throws {
        let cloud = FakeCloud()
        let pad = try await TestDevice.syncing("iPad", cloud: cloud)
        let mac = try await TestDevice.syncing("Mac", cloud: cloud)
        let folder = try await pad.store.createFolder(named: "Later")
        let notebook = try await pad.makeNotebook("Out of order", pages: 2)
        try await pad.store.move([notebook.id], to: folder.id)
        try await pad.draw(on: try await pad.pages(notebook)[0])
        await pad.syncNow()

        // Marks first, then pages, then the document, then its folder.
        await mac.backend.setFetchOrder([[.object], [.page], [.item], [.folder, .signature]])
        await mac.syncNow()
        await mac.syncNow()
        #expect(mac.sync.counts.deferred == 0)
        #expect(try await mac.store.item(notebook.id)?.folderID == folder.id)
        try await expectSame(pad, mac)
    }

    @Test func somethingFromANewerAppIsSetAsideNotMangled() async throws {
        let cloud = FakeCloud()
        let pad = try await TestDevice.syncing("iPad", cloud: cloud)
        let notebook = try await pad.makeNotebook("Mixed versions")
        let page = try await pad.pages(notebook)[0]
        await pad.syncNow()

        let fromTheFuture = SyncRecordKey(.object, UUID().uuidString)
        cloud.plant(SyncRecord(key: fromTheFuture, fields: [
            "pageID": .string(page.id.rawValue), "zKey": .string("V"), "kind": .string("hologram"),
            "payload": .string("{\"hologram\":{}}"), "modifiedAt": .double(1), SyncRecord.layoutVersionField: .int(2),
        ]))
        await pad.syncNow()
        #expect(pad.sync.needsNewerApp && pad.sync.status == .needsAttention)
        #expect(try await pad.store.objects(on: page.id).isEmpty)
        // It is still exactly as the newer app wrote it.
        #expect(cloud.record(fromTheFuture)?["kind"] == .string("hologram"))
        // And everything else keeps syncing.
        try await pad.draw(on: page)
        await pad.syncNow()
        #expect(pad.sync.counts.pendingChanges == 0)
    }

    @Test func aRelaunchPicksUpWhereSyncLeftOff() async throws {
        let cloud = FakeCloud()
        let pad = try await TestDevice.syncing("iPad", cloud: cloud)
        let mac = try await TestDevice.syncing("Mac", cloud: cloud)
        let notebook = try await pad.makeNotebook("Persistent")
        await sync(pad, mac)

        cloud.isOnline = false
        try await pad.draw(on: try await pad.pages(notebook)[0])
        try await pad.relaunch()
        #expect(pad.sync.isEnabled && pad.sync.counts.pendingChanges > 0)
        cloud.isOnline = true
        let fetchedBefore = try await mac.dump()
        await sync(pad, mac)
        #expect(try await mac.dump() != fetchedBefore)
        try await expectSame(pad, mac)
    }
}

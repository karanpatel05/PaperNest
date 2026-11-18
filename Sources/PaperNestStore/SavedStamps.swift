import Foundation
import PaperNestCore

/// Stamps someone made and kept to place again (schema v14, `saved_stamps`).
///
/// Words, style and colour only — no pictures — so a saved stamp keeps no
/// original alive and none of the asset checks need to know about it. Kept
/// on this device and not synced, like saved templates. A stamp already
/// placed is an ordinary text box on its page: deleting the saved stamp
/// leaves it there.
extension LibraryStore {
    /// Keeps `design` to place again, newest first. The same words, style,
    /// colour and date setting kept twice is one saved stamp, brought to the
    /// front. Words that tidy to nothing are refused.
    @discardableResult
    public func saveStamp(_ design: StampDesign) throws -> SavedStamp {
        guard !design.isEmpty else { throw StoreError.invalidPlacement }
        return try db.transaction {
            let timestamp = now()
            if var existing = try savedStamps().first(where: { $0.design == design }) {
                try db.run("UPDATE saved_stamps SET created_at = ? WHERE id = ?",
                           [.date(timestamp), .text(existing.id.rawValue)])
                existing.createdAt = timestamp
                return existing
            }
            let stamp = SavedStamp(design: design, createdAt: timestamp)
            try db.run("INSERT INTO saved_stamps (id, design_json, created_at) VALUES (?, ?, ?)",
                       [.text(stamp.id.rawValue), .text(try json(design)), .date(timestamp)])
            return stamp
        }
    }

    /// Every saved stamp, the most recently kept first.
    public func savedStamps() throws -> [SavedStamp] {
        try db.query("SELECT id, design_json, created_at FROM saved_stamps ORDER BY created_at DESC, id") { s in
            SavedStamp(id: SavedStampID(rawValue: s.text(0)),
                       design: try decoder.decode(StampDesign.self, from: Data(s.text(1).utf8)),
                       createdAt: s.date(2))
        }
    }

    /// Deletes a saved stamp. Stamps already placed from it stay on their pages.
    public func deleteSavedStamp(_ id: SavedStampID) throws {
        _ = try db.transaction { try db.run("DELETE FROM saved_stamps WHERE id = ?", [.text(id.rawValue)]) }
    }
}

/// Images kept to place again as stamps (schema v15, `saved_picture_stamps`).
///
/// **A picture stamp keeps its original alive**, exactly as a saved template
/// does: every check of whether an asset is still used asks
/// `isAssetKeptAside`, which covers both. Kept on this device, not synced and
/// not in the library backup. Placing one writes an ordinary placed image, so
/// a page using it keeps the original too, and deleting the saved stamp
/// leaves placed copies where they are.
extension LibraryStore {
    /// Keeps a staged image to place again: its row and the stamp's in one
    /// write, so the launch sweep can never find the file unclaimed in
    /// between. The same image kept twice — content addressing makes it the
    /// same asset — is one saved stamp, brought to the front.
    @discardableResult
    public func savePictureStamp(_ staged: AssetFileStore.StagedAsset, pixelSize: CGSize) throws -> SavedPictureStamp {
        guard staged.kind.isDrawableImage, pixelSize.width > 0, pixelSize.height > 0,
              pixelSize.width.isFinite, pixelSize.height.isFinite else { throw StoreError.invalidPlacement }
        return try db.transaction {
            let timestamp = now()
            try insertAssetRows([staged], at: timestamp)
            if var existing = try savedPictureStamps().first(where: { $0.assetID == staged.id }) {
                try db.run("UPDATE saved_picture_stamps SET created_at = ? WHERE id = ?",
                           [.date(timestamp), .text(existing.id.rawValue)])
                existing.createdAt = timestamp
                return existing
            }
            let stamp = SavedPictureStamp(assetID: staged.id, kind: staged.kind, pixelSize: pixelSize, createdAt: timestamp)
            try db.run("""
                INSERT INTO saved_picture_stamps (id, asset_id, pixel_width, pixel_height, created_at) VALUES (?, ?, ?, ?, ?)
                """, [.text(stamp.id.rawValue), .text(staged.id.sha256), .double(Double(pixelSize.width)),
                      .double(Double(pixelSize.height)), .date(timestamp)])
            return stamp
        }
    }

    /// Every saved picture stamp, the most recently kept first.
    public func savedPictureStamps() throws -> [SavedPictureStamp] {
        try db.query("""
            SELECT s.id, s.asset_id, a.kind, s.pixel_width, s.pixel_height, s.created_at
            FROM saved_picture_stamps s JOIN assets a ON a.id = s.asset_id
            ORDER BY s.created_at DESC, s.id
            """) { s in
            SavedPictureStamp(id: SavedPictureStampID(rawValue: s.text(0)), assetID: AssetID(sha256: s.text(1)),
                              kind: AssetKind(rawValue: s.text(2)) ?? .png,
                              pixelSize: CGSize(width: s.double(3), height: s.double(4)), createdAt: s.date(5))
        }
    }

    /// Deletes a saved picture stamp. Copies placed on pages stay; its
    /// original goes at the next sweep if nothing else uses it.
    public func deleteSavedPictureStamp(_ id: SavedPictureStampID) throws {
        _ = try db.transaction { try db.run("DELETE FROM saved_picture_stamps WHERE id = ?", [.text(id.rawValue)]) }
    }

    /// Places a saved picture stamp on a page as an ordinary placed image,
    /// on top of what the page holds, in one write — refused if the stamp or
    /// its original is gone. `frame` is in upright source points, as for
    /// `placeImage`, and the image is stretched to it.
    @discardableResult
    public func placePictureStamp(_ id: SavedPictureStampID, on pageID: PageID,
                                  frame: CGRect) throws -> (page: Page, object: PageObject) {
        guard frame.width > 0, frame.height > 0, frame.minX.isFinite, frame.minY.isFinite,
              frame.width.isFinite, frame.height.isFinite else { throw StoreError.invalidPlacement }
        let timestamp = Date()
        return try db.transaction {
            guard let stamp = try savedPictureStamps().first(where: { $0.id == id }) else { throw StoreError.itemNotFound }
            guard let record = try assetRecord(stamp.assetID), record.availability == .local,
                  FileManager.default.fileExists(atPath: assets.url(for: stamp.assetID, kind: record.kind).path) else {
                throw StoreError.assetMissing(stamp.assetID.sha256)
            }
            guard let page = try page(pageID), let parent = try item(page.itemID), !parent.isDeleted else {
                throw StoreError.pageNotFound
            }
            let key = try SortKey.between(try objects(on: pageID).last?.zKey, nil)
            let object = PageObject(pageID: pageID, zKey: key,
                                    payload: .image(PlacedImage(assetID: stamp.assetID, frame: frame)),
                                    modifiedAt: timestamp)
            return (try applyObjectChanges(on: pageID, saving: [object], deleting: []), object)
        }
    }

    /// Whether something saved to use again — a template or a picture stamp —
    /// keeps `asset`. Every check of whether an asset is still used asks this.
    func isAssetKeptAside(_ asset: AssetID) throws -> Bool {
        if try isAssetKeptBySavedTemplate(asset) { return true }
        return try !db.query("SELECT 1 FROM saved_picture_stamps WHERE asset_id = ? LIMIT 1",
                             [.text(asset.sha256)]) { $0.int(0) }.isEmpty
    }

    /// Every original kept by something saved to use again.
    func assetsKeptAside() throws -> Set<AssetID> {
        try assetsKeptBySavedTemplates()
            .union(db.query("SELECT asset_id FROM saved_picture_stamps") { AssetID(sha256: $0.text(0)) })
    }
}

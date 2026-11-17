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

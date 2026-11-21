import Foundation
import PaperNestCore

/// Making a page's handwriting findable.
///
/// What is read off the ink is kept in `handwriting_recognition`, stamped with
/// the page's ink count (`page_ink_generation`, moved by triggers on every
/// write to an ink row; see schema v17). It answers a search only while the
/// two match, and it is in `search_index` only then: the triggers take it out
/// the moment the ink changes, and `saveHandwriting` puts it back only for
/// the ink as it now is. So ink is never called searchable on the strength of
/// a reading of different ink.
extension LibraryStore {
    /// The `search_index` field handwriting uses.
    public static let handwritingField = "ink"

    /// How many times the page's ink has changed. Zero for ink from before
    /// the count existed, or a page with none.
    public func inkGeneration(of pageID: PageID) throws -> Int {
        try db.query("SELECT generation FROM page_ink_generation WHERE page_id = ?", [.text(pageID.rawValue)]) {
            $0.int(0)
        }.first ?? 0
    }

    /// Live pages carrying ink with no reading of the ink as it is now: none
    /// yet, a stale one, or one from an older engine. Each comes with the ink
    /// count to record against. Most recently changed documents first.
    public func pagesNeedingHandwriting(engineVersion: String, limit: Int = 20) throws -> [(page: Page, inkGeneration: Int)] {
        let rows = try db.query("""
            SELECT p.id, COALESCE(g.generation, 0) FROM pages p
            JOIN items i ON i.id = p.item_id
            LEFT JOIN page_ink_generation g ON g.page_id = p.id
            LEFT JOIN handwriting_recognition h ON h.page_id = p.id
            WHERE p.deleted_at IS NULL AND i.deleted_at IS NULL
              AND EXISTS (SELECT 1 FROM page_objects o WHERE o.page_id = p.id AND o.kind = 'ink')
              AND (h.page_id IS NULL OR h.ink_generation != COALESCE(g.generation, 0) OR h.engine_version != ?)
            ORDER BY i.modified_at DESC, p.sort_key, p.id
            LIMIT ?
            """, [.text(engineVersion), .int(Int64(limit))]) { (PageID(rawValue: $0.text(0)), $0.int(1)) }
        return try rows.compactMap { id, generation in try page(id).map { ($0, generation) } }
    }

    /// Keeps a reading and, when it is of the ink as it is now, makes its
    /// confident lines findable, in one transaction.
    ///
    /// Returns false, keeping nothing, when the ink changed after it was
    /// read: the reading would describe ink that is no longer there, and the
    /// page is read again on the next pass.
    @discardableResult
    public func saveHandwriting(_ result: HandwritingRecognitionResult) throws -> Bool {
        let json = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        return try db.transaction {
            guard let page = try page(result.pageID) else { throw StoreError.pageNotFound }
            guard try inkGeneration(of: page.id) == result.inkGeneration else { return false }
            try db.run("""
                INSERT INTO handwriting_recognition (page_id, ink_generation, engine_version, result_json, recognized_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(page_id) DO UPDATE SET ink_generation = excluded.ink_generation,
                    engine_version = excluded.engine_version, result_json = excluded.result_json,
                    recognized_at = excluded.recognized_at
                """, [.text(page.id.rawValue), .int(Int64(result.inkGeneration)), .text(result.engineVersion),
                      .text(json), .date(now())])
            try db.run("DELETE FROM search_index WHERE page_id = ? AND field = ?",
                       [.text(page.id.rawValue), .text(Self.handwritingField)])
            let words = result.searchableText
            if !words.isEmpty {
                try db.run("INSERT INTO search_index (item_id, page_id, field, content) VALUES (?, ?, ?, ?)",
                           [.text(page.itemID.rawValue), .text(page.id.rawValue), .text(Self.handwritingField),
                            .text(words)])
            }
            return true
        }
    }

    /// The page's reading, current or not. Nil when it was never read.
    public func handwriting(on pageID: PageID) throws -> HandwritingRecognitionResult? {
        try db.query("SELECT result_json FROM handwriting_recognition WHERE page_id = ?", [.text(pageID.rawValue)]) {
            try JSONDecoder().decode(HandwritingRecognitionResult.self, from: Data($0.text(0).utf8))
        }.first
    }

    /// The reading, only while it describes the page's ink as it is now.
    public func currentHandwriting(on pageID: PageID) throws -> HandwritingRecognitionResult? {
        guard let result = try handwriting(on: pageID), result.inkGeneration == (try inkGeneration(of: pageID))
        else { return nil }
        return result
    }
}

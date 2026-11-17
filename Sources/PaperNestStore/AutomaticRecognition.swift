import Foundation
import PaperNestCore

/// Which pages still need their text read, so recognition can happen without
/// the user asking for it page by page.
extension LibraryStore {
    /// Live pages whose text has not been read for the paper they show now,
    /// newest document first.
    ///
    /// The work is decided from what is already stored rather than from a
    /// queue, so a pass can be interrupted at any point and the next one picks
    /// up exactly what is left. A page qualifies when it has no result, when
    /// its result was read from an older revision (a rescan), when a request
    /// never finished, or when a different engine produced it.
    ///
    /// A **failed** result for this same paper and engine is left alone:
    /// reading it again would fail again, so a rescan or a new engine version
    /// is what earns another attempt. `engineVersion` is passed in because the
    /// store knows nothing about Vision.
    ///
    /// A **corrected** result is left alone when only the engine changed: its
    /// lines are what a person typed, and reading the page again would throw
    /// them away for something no better. New paper (a stale revision) still
    /// earns a reading, since the corrections describe paper that is gone.
    ///
    /// Pages that already carry their own text are skipped. A digital PDF's
    /// words beat recognizing a raster of those same words, and an empty
    /// `pdfText` marker — a scan with no text layer — is precisely the case
    /// that does need reading.
    ///
    /// Template pages have nothing on them, and a page whose original is not
    /// on this device would fail every pass, so neither is offered.
    public func pagesNeedingRecognition(engineVersion: String, limit: Int = 50) throws -> [Page] {
        let ids = try db.query("""
            SELECT p.id FROM pages p
            JOIN items i ON i.id = p.item_id
            JOIN assets a ON a.id = p.asset_id AND a.availability = 'local'
            LEFT JOIN page_recognition r ON r.page_id = p.id
            WHERE p.deleted_at IS NULL AND i.deleted_at IS NULL
              AND p.content_kind != 'template'
              AND p.id NOT IN (
                  SELECT page_id FROM search_index
                  WHERE field = ? AND page_id IS NOT NULL AND content <> ''
              )
              AND (
                  r.page_id IS NULL
                  OR r.source_revision != p.revision
                  OR r.status = 'pending'
                  OR (r.engine_version != ?
                      AND json_extract(r.result_json, '$.correctedAt') IS NULL)
              )
            ORDER BY i.modified_at DESC, p.sort_key
            LIMIT ?
            """, [.text(Self.embeddedTextField), .text(engineVersion), .int(Int64(limit))]) {
            PageID(rawValue: $0.text(0))
        }
        return try ids.compactMap { try page($0) }
    }
}

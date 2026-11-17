import CoreGraphics
import Foundation
import PaperNestCore

/// Pages saved to start other pages from (schema v12, `saved_templates`).
///
/// Kept on this device and not synced, like bookmarks: syncing them needs a
/// record type of their own and their originals uploaded first.
///
/// **A template keeps its originals alive.** Its background (`asset_id`) and
/// the pictures placed on it (inside `objects_json`) count as uses in every
/// check of whether an asset is still needed: `isAssetReferenced`, the launch
/// sweep, the redaction check and sync's eviction. Without that, the sweep's
/// delete would also trip the foreign key and fail partway.
extension LibraryStore {
    /// Saves `pageID` as a template: its size, content, crop and rotation,
    /// and its ink, text boxes and placed pictures. Private comments and
    /// recognized text are left behind. Nothing it holds is indexed, so a
    /// template's words are not found until a page is made from it.
    public func saveTemplate(from pageID: PageID, named name: String) throws -> SavedPageTemplate {
        try db.transaction {
            guard let page = try page(pageID), try item(page.itemID).map({ !$0.isDeleted }) == true else {
                throw StoreError.pageNotFound
            }
            let objects = try objects(on: pageID).compactMap { object -> PageObject.Payload? in
                if case .comment = object.payload { return nil }
                return object.payload
            }
            let timestamp = now()
            let template = SavedPageTemplate(
                name: NameDeduplicator.uniqueName(name, existing: try savedTemplates().map(\.name)),
                sourceSize: page.sourceSize, content: page.content, transform: page.transform,
                objects: objects, createdAt: timestamp, modifiedAt: timestamp)
            let (kind, asset, index, paper) = Self.templateContentColumns(template.content)
            try db.run("""
                INSERT INTO saved_templates (id, name, source_width, source_height, content_kind, asset_id,
                                             pdf_page_index, template, transform_json, objects_json, created_at, modified_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [.text(template.id.rawValue), .text(template.name),
                      .double(Double(template.sourceSize.width)), .double(Double(template.sourceSize.height)),
                      .text(kind), .optionalText(asset), index, .optionalText(paper),
                      .text(try json(template.transform)), .text(try json(template.objects)),
                      .date(timestamp), .date(timestamp)])
            return template
        }
    }

    /// Every saved template, by name.
    public func savedTemplates() throws -> [SavedPageTemplate] {
        try db.query("""
            SELECT id, name, source_width, source_height, content_kind, asset_id, pdf_page_index, template,
                   transform_json, objects_json, created_at, modified_at
            FROM saved_templates ORDER BY name COLLATE NOCASE, id
            """) { s in
            let content: PageContent
            switch s.text(4) {
            case "image": content = .image(AssetID(sha256: s.text(5)))
            case "pdfPage": content = .pdfPage(AssetID(sha256: s.text(5)), index: s.int(6))
            default: content = .template(PageTemplate(rawValue: s.optionalText(7) ?? "") ?? .blank)
            }
            return SavedPageTemplate(
                id: SavedTemplateID(rawValue: s.text(0)), name: s.text(1),
                sourceSize: CGSize(width: s.double(2), height: s.double(3)), content: content,
                transform: try decoder.decode(PageTransform.self, from: Data(s.text(8).utf8)),
                objects: try decoder.decode([PageObject.Payload].self, from: Data(s.text(9).utf8)),
                createdAt: s.date(10), modifiedAt: s.date(11))
        }
    }

    public func savedTemplate(_ id: SavedTemplateID) throws -> SavedPageTemplate? {
        try savedTemplates().first { $0.id == id }
    }

    /// Renames a template; the name is tidied and kept apart from the others'.
    public func renameSavedTemplate(_ id: SavedTemplateID, to name: String) throws {
        try db.transaction {
            let others = try savedTemplates().filter { $0.id != id }.map(\.name)
            let changed = try db.run("UPDATE saved_templates SET name = ?, modified_at = ? WHERE id = ?",
                                     [.text(NameDeduplicator.uniqueName(name, existing: others)), .date(now()),
                                      .text(id.rawValue)])
            guard changed == 1 else { throw StoreError.itemNotFound }
        }
    }

    /// Deletes a template. Pages made from it are untouched; its originals are
    /// left for the launch sweep if nothing else uses them.
    public func deleteSavedTemplate(_ id: SavedTemplateID) throws {
        _ = try db.transaction { try db.run("DELETE FROM saved_templates WHERE id = ?", [.text(id.rawValue)]) }
    }

    /// Whether a saved template keeps `asset`: as its background or as a
    /// picture placed on it.
    func isAssetKeptBySavedTemplate(_ asset: AssetID) throws -> Bool {
        try !db.query("""
            SELECT 1 FROM saved_templates WHERE asset_id = ?1
            UNION ALL SELECT 1 FROM saved_templates t, json_each(t.objects_json) j
                WHERE json_extract(j.value, '$.image._0.assetID') = ?1
            LIMIT 1
            """, [.text(asset.sha256)]) { $0.int(0) }.isEmpty
    }

    /// Every original a saved template keeps.
    func assetsKeptBySavedTemplates() throws -> Set<AssetID> {
        Set(try savedTemplates().flatMap(\.assetIDs))
    }

    static func templateContentColumns(_ content: PageContent) -> (kind: String, assetID: String?, pdfIndex: SQLValue, template: String?) {
        switch content {
        case .image(let id): ("image", id.sha256, .null, nil)
        case .pdfPage(let id, let index): ("pdfPage", id.sha256, .int(Int64(index)), nil)
        case .template(let paper): ("template", nil, .null, paper.rawValue)
        }
    }
}

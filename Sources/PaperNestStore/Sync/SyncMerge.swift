import Foundation
import PaperNestCore

/// Merging what this device changed with what another device changed, given
/// the last version both agreed on.
///
/// The rule throughout: a change only one side made is kept; a change both
/// sides made the same way is kept once; a change both sides made
/// differently is never settled by throwing one away without a trace. For
/// small facts about a document (its name, its folder) the later edit wins,
/// which is what anyone renaming a file on two devices expects. For what a
/// page shows and for the marks on it, the other device's version stays where
/// it is and this device's version is kept beside it as a copy.
///
/// Pure functions over plain fields, so every rule here is tested without a
/// database or a network.
enum SyncMerge {
    struct Resolution: Equatable {
        /// The fields the row should now hold.
        var merged: SyncFields
        /// This device's version lost its place and must be kept as a copy.
        var keepLocalCopy = false
    }

    private struct Sides {
        var base: SyncFields?
        var local: SyncFields
        var incoming: SyncFields

        func localChanged(_ k: String) -> Bool { base == nil || local[k] != base?[k] }
        func remoteChanged(_ k: String) -> Bool { base == nil || incoming[k] != base?[k] }
        func localChanged(_ keys: [String]) -> Bool { keys.contains(where: localChanged) }
        func remoteChanged(_ keys: [String]) -> Bool { keys.contains(where: remoteChanged) }
        func differ(_ keys: [String]) -> Bool { keys.contains { local[$0] != incoming[$0] } }
    }

    private static func double(_ v: SyncValue?) -> Double? {
        if case .double(let d)? = v { return d }
        return nil
    }

    /// Field-by-field: `pick` is asked only about fields both sides changed
    /// to different values.
    private static func mergeFields(_ s: Sides, skipping: Set<String> = [],
                                    pick: (String, SyncValue?, SyncValue?) -> SyncValue?) -> SyncFields {
        var merged: SyncFields = [:]
        for k in Set(s.local.keys).union(s.incoming.keys).union(s.base?.keys.map { $0 } ?? []) where !skipping.contains(k) {
            let l = s.local[k], r = s.incoming[k]
            let value: SyncValue?
            if l == r { value = l }
            else if !s.remoteChanged(k) { value = l }
            else if !s.localChanged(k) { value = r }
            else { value = pick(k, l, r) }
            merged[k] = value
        }
        return merged
    }

    /// Being alive beats being deleted; of two deletions the earlier stands.
    private static func mergeDeletedAt(_ l: SyncValue?, _ r: SyncValue?) -> SyncValue? {
        guard let a = double(l), let b = double(r) else { return nil }
        return .double(min(a, b))
    }

    private static func earliest(_ l: SyncValue?, _ r: SyncValue?) -> SyncValue? {
        guard let a = double(l), let b = double(r) else { return l ?? r }
        return .double(min(a, b))
    }

    private static func latest(_ l: SyncValue?, _ r: SyncValue?) -> SyncValue? {
        guard let a = double(l), let b = double(r) else { return l ?? r }
        return .double(max(a, b))
    }

    static func resolve(_ type: SyncRecordType, base: SyncFields?, local: SyncFields, incoming: SyncFields) -> Resolution {
        let s = Sides(base: base, local: local, incoming: incoming)
        switch type {
        case .folder, .item:
            let localIsNewer = (double(local["modifiedAt"]) ?? 0) > (double(incoming["modifiedAt"]) ?? 0)
            return Resolution(merged: mergeFields(s) { k, l, r in
                switch k {
                case "modifiedAt": latest(l, r)
                case "createdAt": earliest(l, r)
                case "deletedAt": mergeDeletedAt(l, r)
                default: localIsNewer ? l : r
                }
            })

        case .page:
            return resolvePage(s)

        case .object:
            // What the mark is and where it lives move together.
            let body = ["pageID", "kind", "payload", "assetID"]
            var merged = mergeFields(s, skipping: Set(body)) { k, l, r in
                k == "modifiedAt" ? latest(l, r) : r
            }
            let clash = s.localChanged(body) && s.remoteChanged(body) && s.differ(body)
            let source = (s.remoteChanged(body) || !s.localChanged(body)) ? incoming : local
            for k in body { merged[k] = source[k] }
            return Resolution(merged: merged, keepLocalCopy: clash)

        case .signature:
            return Resolution(merged: mergeFields(s) { _, _, r in r })
        }
    }

    private static let pageContent = ["width", "height", "contentKind", "assetID", "pdfIndex", "template"]

    private static func resolvePage(_ s: Sides) -> Resolution {
        var merged = mergeFields(s, skipping: Set(pageContent + ["transform"])) { k, l, r in
            switch k {
            case "deletedAt": mergeDeletedAt(l, r)
            case "createdAt": earliest(l, r)
            default: r
            }
        }
        var clash = false
        let localContent = s.localChanged(pageContent), remoteContent = s.remoteChanged(pageContent)
        let localLook = s.localChanged("transform"), remoteLook = s.remoteChanged("transform")

        if localContent || remoteContent {
            // New paper resets how the page is cropped and turned, so the
            // paper and its look travel as one. If only one side touched
            // either, that side's pair stands.
            let group = pageContent + ["transform"]
            let localTouched = localContent || localLook, remoteTouched = remoteContent || remoteLook
            if localTouched && remoteTouched && s.differ(group) { clash = true }
            let source = remoteTouched ? s.incoming : s.local
            for k in group { merged[k] = source[k] }
        } else if localLook && remoteLook && s.local["transform"] != s.incoming["transform"] {
            // Same paper, both adjusted. A rotation here and a crop there are
            // both kept; only the same setting changed two ways is a clash.
            let (value, clashed) = mergeTransform(base: s.base?["transform"], local: s.local["transform"], incoming: s.incoming["transform"])
            merged["transform"] = value
            clash = clashed
            for k in pageContent { merged[k] = s.incoming[k] }
        } else {
            merged["transform"] = localLook ? s.local["transform"] : s.incoming["transform"]
            for k in pageContent { merged[k] = s.incoming[k] }
        }
        return Resolution(merged: merged, keepLocalCopy: clash)
    }

    private static func transform(_ v: SyncValue?) -> PageTransform? {
        guard case .string(let text)? = v else { return nil }
        return try? JSONDecoder().decode(PageTransform.self, from: Data(text.utf8))
    }

    private static func mergeTransform(base: SyncValue?, local: SyncValue?, incoming: SyncValue?) -> (SyncValue?, Bool) {
        guard let l = transform(local), let r = transform(incoming), let b = transform(base) else {
            return (incoming, true)
        }
        var clash = false
        func pick<T: Equatable>(_ path: KeyPath<PageTransform, T>) -> T {
            let lv = l[keyPath: path], rv = r[keyPath: path], bv = b[keyPath: path]
            if lv == rv || rv == bv { return lv }
            if lv != bv { clash = true }
            return rv
        }
        let merged = PageTransform(crop: pick(\.crop), rotation: pick(\.rotation), filter: pick(\.filter),
                                   brightness: pick(\.brightness), contrast: pick(\.contrast))
        // Reuse the text either side already holds when the result is theirs,
        // so "equal to what the server has" stays a byte comparison.
        if merged == r { return (incoming, clash) }
        if merged == l { return (local, clash) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(merged) else { return (incoming, true) }
        return (.string(String(decoding: data, as: UTF8.self)), clash)
    }
}

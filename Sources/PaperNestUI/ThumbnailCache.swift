import CoreGraphics
import Foundation
import PaperNestCore
import PaperNestRender

/// Rendered page images keyed by page revision, so an edit naturally
/// produces a new entry. Memory is bounded (LRU) and rendering is limited to
/// a few pages at a time so scrolling a 100-page document stays responsive.
@MainActor
final class ThumbnailCache {
    /// The transform is part of the key, not just the revision: the crop
    /// editor renders an uncropped copy of a page with the same revision.
    struct Key: Hashable {
        let page: PageID
        let revision: Int
        let transform: PageTransform
        let pixelSize: Int
        /// The ink editor shows the page without its ink.
        let includesInk: Bool
        let excludedIDs: Set<PageObjectID>

        init(_ page: Page, pixelSize: CGFloat, includesInk: Bool = true, excludingObjectIDs: Set<PageObjectID> = []) {
            self.page = page.id
            revision = page.revision
            transform = page.transform
            self.pixelSize = ThumbnailCache.bucket(pixelSize)
            self.includesInk = includesInk
            excludedIDs = excludingObjectIDs
        }
    }

    private var images: [Key: CGImage] = [:]
    private var order: [Key] = []
    private let limit = 240
    private let gate = AsyncGate(limit: 4)

    /// Rounds requested sizes up so small layout changes reuse renders.
    nonisolated static func bucket(_ pixels: CGFloat) -> Int {
        let steps = [96, 160, 256, 384, 512, 768, 1024, 1536, 2048, 3072, 4096]
        return steps.first { CGFloat($0) >= pixels } ?? 4096
    }

    func cached(_ page: Page, pixelSize: CGFloat, includesInk: Bool = true, excludingObjectIDs: Set<PageObjectID> = []) -> CGImage? {
        let key = Key(page, pixelSize: pixelSize, includesInk: includesInk, excludingObjectIDs: excludingObjectIDs)
        guard let image = images[key] else { return nil }
        touch(key)
        return image
    }

    func image(for page: Page, pixelSize: CGFloat, includesInk: Bool = true, excludingObjectIDs: Set<PageObjectID> = [], renderer: PageRenderer) async throws -> CGImage {
        let key = Key(page, pixelSize: pixelSize, includesInk: includesInk, excludingObjectIDs: excludingObjectIDs)
        if let hit = images[key] {
            touch(key)
            return hit
        }
        await gate.enter()
        let image: CGImage
        do {
            try Task.checkCancellation()
            image = try await renderer.renderThumbnail(page, maxPixelSize: CGFloat(key.pixelSize), includingInk: includesInk, excludingObjectIDs: excludingObjectIDs)
            await gate.leave()
        } catch {
            await gate.leave()
            throw error
        }
        images[key] = image
        touch(key)
        return image
    }

    private func touch(_ key: Key) {
        if let index = order.firstIndex(of: key) { order.remove(at: index) }
        order.append(key)
        while order.count > limit {
            images[order.removeFirst()] = nil
        }
    }
}

/// A counting semaphore for async work.
actor AsyncGate {
    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func enter() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func leave() {
        if waiters.isEmpty {
            running -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

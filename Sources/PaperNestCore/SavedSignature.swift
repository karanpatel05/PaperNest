import CoreGraphics
import Foundation

/// Ink a person drew once, kept, and placeable again on any page.
///
/// **This is a picture of a handwritten signature, not a cryptographic one.**
/// It proves nothing about who placed it, carries no certificate, timestamp or
/// tamper-evidence, and anyone holding the file can copy the image out and put
/// it on another. Nothing built on this may say "signed", "verified",
/// "authenticated" or "secure". The honest verb is **placed**.
///
/// The strokes are kept in the signature's **own unit box** rather than in the
/// coordinates of the page it was drawn on, so placing it later is a pure
/// scale and translate onto any page of any size, with no memory of where it
/// came from.
public struct SavedSignature: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Strokes in unit space: coordinates and widths divided by the **same** number, the
    /// longer side of the ink's own bounds. So the longer side runs 0...1 and
    /// the shorter runs 0...less, which is what keeps the signature's shape.
    /// Scaling each axis to 0...1 separately would square up a wide signature
    /// before it was ever placed. For a lone dot, its diameter supplies that divisor.
    public var strokes: [InkStroke]
    public var createdAt: Date

    public init(id: String = UUID().uuidString, name: String,
                strokes: [InkStroke], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.strokes = strokes
        self.createdAt = createdAt
    }

    /// Captures ink drawn on a page, normalised by **its own bounding box** so
    /// the blank paper around it does not become part of the signature.
    ///
    /// Returns nil for ink with nothing in it: saving an empty signature would
    /// offer the user something that places nothing. Degenerate ink — a single
    /// point, or a perfectly straight horizontal line — is kept, with the
    /// flat axis collapsed to 0 rather than divided by zero.
    public init?(id: String = UUID().uuidString, name: String,
                 capturing drawn: [InkStroke], createdAt: Date = Date()) {
        let points = drawn.flatMap(\.points)
        guard !points.isEmpty,
              let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
        else { return nil }
        let width = maxX - minX, height = maxY - minY
        // One divisor for both axes: the signature's shape is part of the
        // signature. Normalising each axis separately would turn a wide
        // signature into a square one here, before placement ever saw it.
        let longest = max(width, height)
        // Width lives in the same units as the captured points. A lone dot
        // has no point extent, so its widest stroke supplies its diameter.
        let widestStroke = drawn.map(\.width).max() ?? 1
        let divisor = longest > 0 ? longest : (widestStroke > 0 && widestStroke.isFinite ? widestStroke : 1)
        self.init(
            id: id, name: name,
            strokes: drawn.map { stroke in
                var normalized = stroke
                normalized.width = stroke.width / divisor
                normalized.points = stroke.points.map { point in
                    var moved = point
                    moved.x = (point.x - minX) / divisor
                    moved.y = (point.y - minY) / divisor
                    return moved
                }
                return normalized
            },
            createdAt: createdAt)
    }

    /// The signature as ink on a page, fitted inside `target` and centred.
    ///
    /// **Aspect ratio is preserved**, so a wide signature in a square target is
    /// letterboxed rather than stretched: a stretched signature is a different
    /// shape from the one the person drew, which looks wrong on a document and
    /// misrepresents their hand.
    ///
    /// The stored signature is untouched, so one signature can be placed any
    /// number of times.
    public func placed(in target: NormalizedRect, on pageSize: CGSize) -> [InkStroke] {
        let box = CGRect(x: target.x * pageSize.width, y: target.y * pageSize.height,
                         width: target.width * pageSize.width, height: target.height * pageSize.height)
        let extent = self.extent
        // Fit inside, keeping shape. A flat signature uses the one axis it has.
        let scaleX = extent.width > 0 ? box.width / extent.width : .infinity
        let scaleY = extent.height > 0 ? box.height / extent.height : .infinity
        let scale = extent.width > 0 || extent.height > 0
            ? min(scaleX, scaleY) : min(box.width, box.height)
        let drawnWidth = extent.width * scale, drawnHeight = extent.height * scale
        let originX = box.minX + (box.width - drawnWidth) / 2
        let originY = box.minY + (box.height - drawnHeight) / 2

        return strokes.map { stroke in
            var placed = stroke
            placed.width = stroke.width * scale
            placed.points = stroke.points.map { point in
                var moved = point
                moved.x = originX + (point.x - extent.minX) * scale
                moved.y = originY + (point.y - extent.minY) * scale
                return moved
            }
            return placed
        }
    }

    /// The bounds the strokes actually occupy in unit space. Normally
    /// (0, 0, 1, 1), but a signature decoded from elsewhere need not be.
    private var extent: CGRect {
        let points = strokes.flatMap(\.points)
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
        else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

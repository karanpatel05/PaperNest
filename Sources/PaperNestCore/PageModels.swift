import CoreGraphics
import Foundation

/// One page of a document or notebook.
///
/// Coordinate convention (see docs/ARCHITECTURE.md, "Page coordinates"):
/// `sourceSize` is the upright, uncropped content in points (1/72 in) with a
/// top-left origin. Ink, text and OCR boxes are stored in that *content
/// space*, so `transform` (crop, then rotation) moves them with the page.
public struct Page: Identifiable, Hashable, Codable, Sendable {
    public var id: PageID
    public var itemID: ItemID
    /// Fractional-index key; pages sort by `(sortKey, id)`. See `SortKey`.
    public var sortKey: String
    public var sourceSize: CGSize
    public var content: PageContent
    public var transform: PageTransform
    /// Incremented on every committed change to this page. Derived caches
    /// (thumbnails, OCR) record the revision they were built from.
    public var revision: Int
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: PageID = .make(),
        itemID: ItemID,
        sortKey: String,
        sourceSize: CGSize,
        content: PageContent,
        transform: PageTransform = .identity,
        revision: Int = 1,
        createdAt: Date,
        modifiedAt: Date
    ) {
        self.id = id
        self.itemID = itemID
        self.sortKey = sortKey
        self.sourceSize = sourceSize
        self.content = content
        self.transform = transform
        self.revision = revision
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    public var geometry: PageGeometry {
        PageGeometry(sourceSize: sourceSize, crop: transform.crop, rotation: transform.rotation)
    }
}

public enum PageContent: Hashable, Codable, Sendable {
    /// A raster scan or photo stored as an immutable asset.
    case image(AssetID)
    /// One page of an imported PDF, kept as vector content.
    case pdfPage(AssetID, index: Int)
    /// A notebook page drawn from a template.
    case template(PageTemplate)

    public var assetID: AssetID? {
        switch self {
        case .image(let id), .pdfPage(let id, _): id
        case .template: nil
        }
    }
}

public enum PageTemplate: String, Codable, Sendable, CaseIterable {
    case blank, lined, grid
}

/// Non-destructive edits applied over the original. The original asset is
/// never rewritten; "revert" means restoring `.identity`.
public struct PageTransform: Hashable, Codable, Sendable {
    public var crop: NormalizedRect
    public var rotation: QuarterTurns
    public var filter: PageFilter
    /// -1...1, 0 = unchanged.
    public var brightness: Double
    /// 0.25...4, 1 = unchanged.
    public var contrast: Double

    public init(
        crop: NormalizedRect = .full,
        rotation: QuarterTurns = .none,
        filter: PageFilter = .original,
        brightness: Double = 0,
        contrast: Double = 1
    ) {
        self.crop = crop
        self.rotation = rotation
        self.filter = filter
        self.brightness = min(max(brightness, -1), 1)
        self.contrast = min(max(contrast, 0.25), 4)
    }

    public static let identity = PageTransform()

    /// True when pixels must be processed (not just positioned) to render.
    public var needsPixelProcessing: Bool {
        filter != .original || brightness != 0 || contrast != 1
    }
}

public enum PageFilter: String, Codable, Sendable, CaseIterable {
    case original
    case grayscale
    case blackAndWhite
}

/// Clockwise quarter turns.
public enum QuarterTurns: Int, Codable, Sendable, CaseIterable {
    case none = 0, clockwise90 = 1, half = 2, clockwise270 = 3

    public var degrees: Int { rawValue * 90 }
    public var swapsAxes: Bool { rawValue % 2 == 1 }

    public func rotatedClockwise() -> QuarterTurns { QuarterTurns(rawValue: (rawValue + 1) % 4)! }
    public func rotatedCounterclockwise() -> QuarterTurns { QuarterTurns(rawValue: (rawValue + 3) % 4)! }

    /// Maps a clockwise angle in degrees (as found in PDF `/Rotate`) to quarter turns.
    public init(normalizingDegrees degrees: Int) {
        let d = ((degrees % 360) + 360) % 360
        self = QuarterTurns(rawValue: (d + 45) / 90 % 4)!
    }
}

/// A rectangle in unit coordinates (0...1) with a top-left origin.
public struct NormalizedRect: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    /// Smallest crop accepted, as a fraction of the source side, so a crop
    /// can never produce a zero-size page.
    public static let minimumSide = 0.02

    public init(x: Double, y: Double, width: Double, height: Double) {
        let minSide = Self.minimumSide
        let cx = min(max(x, 0), 1 - minSide)
        let cy = min(max(y, 0), 1 - minSide)
        self.x = cx
        self.y = cy
        self.width = min(max(width, minSide), 1 - cx)
        self.height = min(max(height, minSide), 1 - cy)
    }

    public static let full = NormalizedRect(x: 0, y: 0, width: 1, height: 1)

    public func denormalized(in size: CGSize) -> CGRect {
        CGRect(x: x * size.width, y: y * size.height, width: width * size.width, height: height * size.height)
    }
}

public enum AssetKind: String, Codable, Sendable {
    case pdf, jpeg, png

    public var fileExtension: String {
        switch self {
        case .pdf: "pdf"
        case .jpeg: "jpg"
        case .png: "png"
        }
    }
}

public enum AssetAvailability: String, Codable, Sendable {
    /// Bytes are on this device.
    case local
    /// Metadata is known (e.g. from sync) but bytes are not downloaded yet.
    /// Such pages must never be presented as available offline.
    case remoteOnly
}

/// Metadata for an immutable original stored in the asset store.
public struct AssetRecord: Hashable, Codable, Sendable {
    public var id: AssetID
    public var kind: AssetKind
    public var byteCount: Int64
    public var originalFilename: String?
    public var availability: AssetAvailability
    public var createdAt: Date

    public init(
        id: AssetID,
        kind: AssetKind,
        byteCount: Int64,
        originalFilename: String?,
        availability: AssetAvailability = .local,
        createdAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.byteCount = byteCount
        self.originalFilename = originalFilename
        self.availability = availability
        self.createdAt = createdAt
    }
}

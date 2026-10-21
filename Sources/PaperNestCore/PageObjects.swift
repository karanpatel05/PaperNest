import CoreGraphics
import Foundation

/// Editable content placed on a page: ink, typed text or an inserted image.
/// Positions are in the page's content space (see `Page`), so they follow the
/// page through crop and rotation.
///
/// The editor UI for these arrives in milestone M3; the model and persistence
/// exist now so the schema is settled before many screens depend on it.
public struct PageObject: Identifiable, Hashable, Codable, Sendable {
    public var id: PageObjectID
    public var pageID: PageID
    /// Paint order; higher draws later. Fractional-index key like page order.
    public var zKey: String
    public var payload: Payload
    public var modifiedAt: Date

    public init(id: PageObjectID = .make(), pageID: PageID, zKey: String, payload: Payload, modifiedAt: Date) {
        self.id = id
        self.pageID = pageID
        self.zKey = zKey
        self.payload = payload
        self.modifiedAt = modifiedAt
    }

    public enum Payload: Hashable, Codable, Sendable {
        case ink(InkStroke)
        case text(TextBox)
        case image(PlacedImage)

        public var kind: String {
            switch self {
            case .ink: "ink"
            case .text: "text"
            case .image: "image"
            }
        }
    }
}

/// An sRGB color with alpha, all components 0...1.
public struct RGBAColor: Hashable, Codable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let black = RGBAColor(red: 0, green: 0, blue: 0)
}

/// Editable vector ink. This app-owned format (rather than a PencilKit
/// `PKDrawing` blob) renders identically on Mac, merges per stroke during
/// sync, and converts to/from PencilKit on iPad.
public struct InkStroke: Hashable, Codable, Sendable {
    public enum Tool: String, Codable, Sendable {
        case pen, highlighter
    }

    public var tool: Tool
    public var color: RGBAColor
    /// Nominal width in points at pressure 1.
    public var width: Double
    public var points: [InkPoint]

    public init(tool: Tool, color: RGBAColor, width: Double, points: [InkPoint]) {
        self.tool = tool
        self.color = color
        self.width = width
        self.points = points
    }
}

public struct InkPoint: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    /// 0...1; 1 when the input device reports no pressure.
    public var pressure: Double
    /// Seconds since the first point of the stroke.
    public var time: Double

    public init(x: Double, y: Double, pressure: Double = 1, time: Double = 0) {
        self.x = x
        self.y = y
        self.pressure = pressure
        self.time = time
    }
}

public struct TextBox: Hashable, Codable, Sendable {
    public enum Alignment: String, Codable, Sendable {
        case leading, center, trailing
    }

    public var frame: CGRect
    public var text: String
    public var fontSize: Double
    public var color: RGBAColor
    public var alignment: Alignment

    public init(frame: CGRect, text: String, fontSize: Double = 14, color: RGBAColor = .black, alignment: Alignment = .leading) {
        self.frame = frame
        self.text = text
        self.fontSize = fontSize
        self.color = color
        self.alignment = alignment
    }
}

public struct PlacedImage: Hashable, Codable, Sendable {
    public var assetID: AssetID
    public var frame: CGRect

    public init(assetID: AssetID, frame: CGRect) {
        self.assetID = assetID
        self.frame = frame
    }
}

/// Text recognized on one page. Boxes are normalized to the upright,
/// uncropped source (top-left origin), the same space as page objects, so
/// they stay aligned after crop/rotation and in exported searchable PDFs.
///
/// The OCR engine arrives in milestone M4.
public struct PageRecognition: Hashable, Codable, Sendable {
    public enum Status: String, Codable, Sendable {
        case pending, completed, failed
    }

    public var pageID: PageID
    /// The page revision the text was recognized from; a newer page
    /// revision makes this result stale.
    public var sourceRevision: Int
    public var engineVersion: String
    public var status: Status
    public var languages: [String]
    public var lines: [RecognizedLine]

    public init(pageID: PageID, sourceRevision: Int, engineVersion: String, status: Status, languages: [String], lines: [RecognizedLine]) {
        self.pageID = pageID
        self.sourceRevision = sourceRevision
        self.engineVersion = engineVersion
        self.status = status
        self.languages = languages
        self.lines = lines
    }

    public var text: String { lines.map(\.text).joined(separator: "\n") }
}

public struct RecognizedLine: Hashable, Codable, Sendable {
    public var text: String
    public var box: NormalizedRect
    public var confidence: Double

    public init(text: String, box: NormalizedRect, confidence: Double) {
        self.text = text
        self.box = box
        self.confidence = confidence
    }
}

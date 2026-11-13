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
        /// Page-level private comment; not painted or included in image/PDF exports.
        case comment(String)

        public var kind: String {
            switch self {
            case .ink: "ink"
            case .text: "text"
            case .image: "image"
            case .comment: "comment"
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

    /// How a stroke's ends are finished.
    public enum Cap: String, Codable, Sendable {
        case round, flat
    }

    public var tool: Tool
    /// The color the user picked, at full strength. The highlighter's
    /// translucency is added when drawing (`highlighterOpacity`), never
    /// stored, so it can't be applied twice.
    public var color: RGBAColor
    /// Nominal width in source points; each point scales it.
    public var width: Double
    public var points: [InkPoint]
    /// Nil means round, which is every stroke saved before this existed and
    /// every pen stroke since. Only a flat-edged highlighter sets it, so the
    /// stored form of all other ink is byte-for-byte what it always was.
    public var cap: Cap?

    /// How opaque highlighter ink is drawn over the page.
    public static let highlighterOpacity = 0.35

    /// Drawn width at a point, in source points. The renderer and the
    /// PencilKit conversion both use this, so exports match the editor.
    public func width(at point: InkPoint) -> Double {
        width * min(max(point.widthScale, 0.05), 4)
    }

    public init(tool: Tool, color: RGBAColor, width: Double, points: [InkPoint], cap: Cap? = nil) {
        self.tool = tool
        self.color = color
        self.width = width
        self.points = points
        self.cap = cap
    }
}

public struct InkPoint: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    /// Width here relative to the stroke's `width` (1 = nominal). From
    /// PencilKit this is the point's size, which already reflects pressure
    /// and tilt; input without pressure uses 1.
    public var widthScale: Double
    /// Seconds since the first point of the stroke.
    public var time: Double

    public init(x: Double, y: Double, widthScale: Double = 1, time: Double = 0) {
        self.x = x
        self.y = y
        self.widthScale = widthScale
        self.time = time
    }
}

public struct TextBox: Hashable, Codable, Sendable {
    public enum Alignment: String, Codable, Sendable {
        case leading, center, trailing
    }

    public enum FontFamily: String, Codable, CaseIterable, Sendable {
        case sans, serif, monospaced
    }

    public var frame: CGRect
    public var text: String
    public var fontSize: Double
    public var color: RGBAColor
    public var alignment: Alignment
    public var fontFamily: FontFamily
    public var isBold: Bool
    public var isItalic: Bool

    public init(frame: CGRect, text: String, fontSize: Double = 14, color: RGBAColor = .black,
                alignment: Alignment = .leading, fontFamily: FontFamily = .sans,
                isBold: Bool = false, isItalic: Bool = false) {
        self.frame = frame
        self.text = text
        self.fontSize = fontSize
        self.color = color
        self.alignment = alignment
        self.fontFamily = fontFamily
        self.isBold = isBold
        self.isItalic = isItalic
    }

    /// Shared by the native editor and CoreText rendering/export.
    public var postScriptFontName: String {
        switch (fontFamily, isBold, isItalic) {
        case (.sans, false, false): "Helvetica"
        case (.sans, true, false): "Helvetica-Bold"
        case (.sans, false, true): "Helvetica-Oblique"
        case (.sans, true, true): "Helvetica-BoldOblique"
        case (.serif, false, false): "TimesNewRomanPSMT"
        case (.serif, true, false): "TimesNewRomanPS-BoldMT"
        case (.serif, false, true): "TimesNewRomanPS-ItalicMT"
        case (.serif, true, true): "TimesNewRomanPS-BoldItalicMT"
        case (.monospaced, false, false): "Courier"
        case (.monospaced, true, false): "Courier-Bold"
        case (.monospaced, false, true): "Courier-Oblique"
        case (.monospaced, true, true): "Courier-BoldOblique"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case frame, text, fontSize, color, alignment, fontFamily, isBold, isItalic
    }

    /// Old libraries have no font keys; their Helvetica appearance is retained.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        frame = try values.decode(CGRect.self, forKey: .frame)
        text = try values.decode(String.self, forKey: .text)
        fontSize = try values.decode(Double.self, forKey: .fontSize)
        color = try values.decode(RGBAColor.self, forKey: .color)
        alignment = try values.decode(Alignment.self, forKey: .alignment)
        fontFamily = try values.decodeIfPresent(FontFamily.self, forKey: .fontFamily) ?? .sans
        isBold = try values.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
        isItalic = try values.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false
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

/// One word of a recognised line, with its own place on the page.
///
/// Boxes come from Vision rather than from dividing the line's box by
/// character count: a proportional font makes that drift, and a highlight
/// that drifts lands on the wrong ink.
public struct RecognizedWord: Hashable, Codable, Sendable {
    public var text: String
    public var box: NormalizedRect

    public init(text: String, box: NormalizedRect) {
        self.text = text
        self.box = box
    }
}

public struct RecognizedLine: Hashable, Codable, Sendable {
    public var text: String
    public var box: NormalizedRect
    public var confidence: Double
    /// The line's words, where Vision could place them.
    ///
    /// Empty for every result recognised before this existed — those are still
    /// stored, and a reader treats empty as "fall back to the whole line"
    /// rather than as a failure. Nothing is recomputed behind the user's back.
    ///
    /// It can also hold fewer entries than the line has words: Vision does not
    /// always return a box for a range, and a word without one is dropped
    /// rather than given an invented box.
    public var words: [RecognizedWord]

    public init(text: String, box: NormalizedRect, confidence: Double,
                words: [RecognizedWord] = []) {
        self.text = text
        self.box = box
        self.confidence = confidence
        self.words = words
    }

    // Written by hand so a result stored before `words` existed still decodes.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        box = try container.decode(NormalizedRect.self, forKey: .box)
        confidence = try container.decode(Double.self, forKey: .confidence)
        words = try container.decodeIfPresent([RecognizedWord].self, forKey: .words) ?? []
    }
}

extension PageObject {
    public var commentText: String? {
        if case .comment(let text) = payload { return text }
        return nil
    }
}

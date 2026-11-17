import CoreGraphics
import Foundation

public typealias SavedStampID = Identifier<SavedStamp>

/// How a stamp looks around its words.
public enum StampStyle: String, Codable, CaseIterable, Sendable {
    /// Inside an outlined rounded rectangle, like a rubber stamp.
    case outlined
    /// On a tinted, fully rounded background, like a label.
    case filled
}

/// A stamp's measurements, all following its type size, so a stamp drawn
/// larger is the same stamp. Drawing, selection and the size a stamp is
/// placed at all read these, so they cannot disagree about where its words
/// sit.
extension TextBox {
    /// The smaller lines under the first, as a share of the type size.
    public static let stampDetailScale = 0.55

    /// An outlined stamp's border, in source points.
    public var stampLineWidth: Double { max(1, fontSize * 0.09) }

    /// Room between the border and the words, on each side; more at the
    /// ends of a filled stamp, whose ends are round.
    public var stampPadding: CGSize {
        CGSize(width: fontSize * (stamp == .filled ? 0.8 : 0.55), height: fontSize * 0.3)
    }

    /// An outlined stamp has softened corners; a filled one is fully rounded.
    public var stampCornerRadius: Double {
        switch stamp {
        case .filled: min(frame.width, frame.height) / 2
        case .outlined, nil: fontSize * 0.3
        }
    }

    /// Where a stamp's words are laid out: its frame less the border and the
    /// padding, in the box's own coordinates (origin at the frame's corner).
    public var stampContentRect: CGRect {
        let inset = stampPadding
        let line = stamp == .outlined ? stampLineWidth : 0
        return CGRect(origin: .zero, size: frame.size)
            .insetBy(dx: inset.width + line, dy: inset.height + line)
    }
}

/// The stamps that come with PaperNest. Their words are the reader's,
/// written in when a stamp is placed; this type knows nothing of language.
public enum StampPreset: String, CaseIterable, Sendable {
    case approved, paid, received, reviewed, rejected, draft, confidential

    /// Draft is a light working label; every other preset is a rubber stamp.
    public var style: StampStyle { self == .draft ? .filled : .outlined }

    /// The export watermarks' semantic colours (`WatermarkPreset.color`), so
    /// an Approved stamp and an Approved watermark are the same green: the
    /// mockup's green for done, a blue for noted, a red that is not pure
    /// saturated red for stop, and the app's accent for a draft.
    public var color: RGBAColor {
        switch self {
        case .approved, .paid: RGBAColor(red: 0.176, green: 0.541, blue: 0.404)
        case .received, .reviewed: RGBAColor(red: 0.141, green: 0.365, blue: 0.722)
        case .rejected, .confidential: RGBAColor(red: 0.78, green: 0.16, blue: 0.18)
        case .draft: RGBAColor(red: 0.459, green: 0.271, blue: 0.973)
        }
    }
}

/// What a stamp says and how it looks, before it is placed.
public struct StampDesign: Hashable, Codable, Sendable {
    /// Longest wording kept, in characters, as for a watermark: a pasted
    /// paragraph is not a stamp.
    public static let maxTextLength = 40

    /// One line, tidied (`tidy`).
    public private(set) var text: String
    public var style: StampStyle
    public var color: RGBAColor
    /// Today's date under the words, written in when it is placed.
    public var includesDate: Bool

    public init(text: String, style: StampStyle, color: RGBAColor, includesDate: Bool = false) {
        self.text = Self.tidy(text)
        self.style = style
        self.color = color
        self.includesDate = includesDate
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(text: try values.decode(String.self, forKey: .text),
                  style: try values.decode(StampStyle.self, forKey: .style),
                  color: try values.decode(RGBAColor.self, forKey: .color),
                  includesDate: try values.decodeIfPresent(Bool.self, forKey: .includesDate) ?? false)
    }

    private enum CodingKeys: String, CodingKey { case text, style, color, includesDate }

    public var isEmpty: Bool { text.isEmpty }

    /// Line breaks become spaces, runs of space one, the ends trimmed and
    /// the length limited: the date is the only second line a stamp has.
    public static func tidy(_ text: String) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        return String(words.joined(separator: " ").prefix(maxTextLength))
    }

    /// The text box this stamp is: its words, then the date line, bold,
    /// centred, in its colour. `frame` comes from measuring it.
    public func textBox(dateLine: String?, fontSize: Double, frame: CGRect = .zero) -> TextBox {
        let date = dateLine.map(Self.tidy).flatMap { $0.isEmpty ? nil : $0 }
        return TextBox(frame: frame, text: date.map { "\(text)\n\($0)" } ?? text, fontSize: fontSize,
                       color: color, alignment: .center, fontFamily: .sans, isBold: true, stamp: style)
    }
}

/// How large a stamp is placed.
public enum StampSize: String, CaseIterable, Sendable {
    case small, medium, large

    /// Its type size, as a share of the shorter side of the page as shown:
    /// about 13, 20 and 28 points on a US Letter page.
    public func fontSize(on pageSize: CGSize) -> Double {
        let side = Double(min(pageSize.width, pageSize.height))
        return switch self {
        case .small: side * 0.022
        case .medium: side * 0.032
        case .large: side * 0.046
        }
    }
}

/// Where on the page a stamp is placed: where a stamp usually goes on paper.
public enum StampPlacement: String, CaseIterable, Sendable {
    case topRight, bottomRight, center

    /// A stamp `size` points large (laid out upright in source space, as
    /// every text box is) placed on the page **as it is shown** — cropped and
    /// turned — and mapped back through `PageGeometry`. A margin of 5% of
    /// the shorter side keeps it off the edge; a stamp wider than the room
    /// starts at the edge rather than off the page.
    public func frame(size: CGSize, on geometry: PageGeometry) -> CGRect {
        let page = geometry.pageSize
        let shown = geometry.rotation.swapsAxes ? CGSize(width: size.height, height: size.width) : size
        let margin = min(page.width, page.height) * 0.05
        let origin: CGPoint = switch self {
        case .topRight: CGPoint(x: page.width - margin - shown.width, y: margin)
        case .bottomRight: CGPoint(x: page.width - margin - shown.width, y: page.height - margin - shown.height)
        case .center: CGPoint(x: (page.width - shown.width) / 2, y: (page.height - shown.height) / 2)
        }
        let onPage = CGRect(origin: CGPoint(x: max(0, origin.x), y: max(0, origin.y)), size: shown)
        let source = onPage.applying(geometry.pageToSource)
        // The mapped rectangle's own origin with the exact size: a quarter
        // turn there and back can leave a rounding error in the size.
        return CGRect(origin: source.origin, size: size)
    }
}

/// A stamp someone made and kept to use again (schema v14, `saved_stamps`).
public struct SavedStamp: Hashable, Sendable, Identifiable {
    public var id: SavedStampID
    public var design: StampDesign
    public var createdAt: Date

    public init(id: SavedStampID = .make(), design: StampDesign, createdAt: Date) {
        self.id = id
        self.design = design
        self.createdAt = createdAt
    }
}

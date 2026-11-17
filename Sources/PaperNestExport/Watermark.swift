import CoreGraphics
import Foundation
import PaperNestCore

/// The look a watermark starts from. Each preset fixes the mark's shape and
/// colour; text, placement, opacity, rotation and the date line are the
/// person's, starting from the preset's defaults.
public enum WatermarkPreset: String, CaseIterable, Codable, Sendable {
    /// Large diagonal word across the page, in a muted red.
    case confidential
    /// Small tinted capsule in the top-right corner, in PaperNest's accent.
    case draft
    /// Outlined status stamp in the bottom-right corner, in green.
    case approved
    /// The person's own words, large and diagonal by default, in navy.
    case custom

    public var shape: WatermarkShape {
        switch self {
        case .confidential, .custom: .text
        case .draft: .capsule
        case .approved: .stamp
        }
    }

    /// Semantic colours: a red that is not pure saturated red, the app's
    /// accent (`Theme.accent`, #7545F8), the approved green of the owner's
    /// mockup (#2D8A67, `docs/design/mockups/watermark-samples.svg`) and a
    /// navy, each readable on white paper and on a dense scan at the preset's
    /// opacity.
    public var color: RGBAColor {
        switch self {
        case .confidential: RGBAColor(red: 0.78, green: 0.16, blue: 0.18)
        case .draft: RGBAColor(red: 0.459, green: 0.271, blue: 0.973)
        case .approved: RGBAColor(red: 0.176, green: 0.541, blue: 0.404)
        case .custom: RGBAColor(red: 0.20, green: 0.25, blue: 0.40)
        }
    }

    public var defaultPlacement: WatermarkPlacement {
        switch self {
        case .confidential, .custom: .center
        case .draft: .topRight
        case .approved: .bottomRight
        }
    }

    public var defaultOpacity: Double {
        switch self {
        case .confidential: 0.18
        case .custom: 0.16
        case .draft: 0.9
        case .approved: 0.85
        }
    }

    /// Degrees, turning clockwise as seen on the page: −32 rises to the right.
    public var defaultRotation: Double {
        switch self {
        case .confidential, .custom: -32
        case .draft, .approved: 0
        }
    }
}

/// How a mark is drawn. Fixed by the preset.
public enum WatermarkShape: Sendable {
    /// Letters alone.
    case text
    /// Letters on a tinted, fully rounded background.
    case capsule
    /// Letters inside an outlined rounded rectangle, like a rubber stamp.
    case stamp
}

public enum WatermarkPlacement: String, CaseIterable, Codable, Sendable {
    case center, topRight, bottomRight
    /// The mark repeated across the whole page.
    case tiled
}

/// A watermark drawn onto exported pages.
///
/// It exists only in an export request (`ExportOptions.watermark`): nothing
/// about it is stored in the library, and the page it is drawn over is never
/// changed. The words are already in the person's language and the date line
/// is already formatted — this type draws strings and knows nothing of
/// localization, so an export is the same bytes on every device.
public struct Watermark: Hashable, Sendable {
    /// Longest text drawn, in characters. Longer text is cut, so a pasted
    /// paragraph cannot shrink to an unreadable sliver.
    public static let maxTextLength = 40
    public static let opacityRange: ClosedRange<Double> = 0.05...1
    public static let rotationRange: ClosedRange<Double> = -90...90

    public var preset: WatermarkPreset
    public var text: String { didSet { text = Self.limited(text) } }
    public var placement: WatermarkPlacement
    public var opacity: Double { didSet { opacity = Self.clamp(opacity, to: Self.opacityRange) } }
    public var rotation: Double { didSet { rotation = Self.clamp(rotation, to: Self.rotationRange) } }
    /// A second, smaller line under the text, such as a date. Nil for none.
    public var dateLine: String?

    public init(preset: WatermarkPreset, text: String, placement: WatermarkPlacement? = nil,
                opacity: Double? = nil, rotation: Double? = nil, dateLine: String? = nil) {
        self.preset = preset
        self.text = Self.limited(text)
        self.placement = placement ?? preset.defaultPlacement
        self.opacity = Self.clamp(opacity ?? preset.defaultOpacity, to: Self.opacityRange)
        self.rotation = Self.clamp(rotation ?? preset.defaultRotation, to: Self.rotationRange)
        self.dateLine = dateLine
    }

    public var shape: WatermarkShape { preset.shape }
    public var color: RGBAColor { preset.color }

    /// The text as drawn: surrounding spaces and line breaks removed.
    public var drawnText: String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    var drawnDateLine: String? {
        guard let line = dateLine?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else { return nil }
        return line
    }

    /// False when there is nothing to draw. Export then writes exactly what it
    /// writes with no watermark, so an empty Custom text is not a mark of
    /// zero size that still makes every page be redrawn.
    ///
    /// Judged from the letters' outlines, not from the text: a colour emoji
    /// has no outline and draws nothing, and "🔒" alone must not count as a
    /// watermark that stops a form being handed back as it came and then
    /// leaves no mark on it.
    public var isVisible: Bool { !drawnText.isEmpty && WatermarkDrawing.hasInk(drawnText) }

    private static func limited(_ text: String) -> String { String(text.prefix(maxTextLength)) }
    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : range.lowerBound
    }
}

extension ExportFormat {
    /// Whether a watermark can be drawn into this format: every format that
    /// carries a picture of the page. A text file has nowhere to put one, and
    /// export refuses rather than silently leaving it out.
    public var canCarryWatermark: Bool { !keepsOnlyWords }
}

extension ExportOptions {
    /// Whether this export can carry a watermark: PDF, JPEG, PNG and HEIC.
    /// Word is left out in both layouts for now — editable text has no
    /// page to draw on, and drawing on Word's page pictures is not built.
    public var canCarryWatermark: Bool { format.canCarryWatermark }
}

import CoreGraphics

public enum TextMarkupError: Error, Equatable, Sendable {
    case invalidBounds
    case invalidColor
}

/// Full-line marks represented by ordinary editable ink. Geometry is always
/// upright source space; PageGeometry applies crop/rotation when rendering.
public enum TextMarkupStyle: String, CaseIterable, Sendable {
    case highlight, underline, strikethrough

    public var defaultColor: RGBAColor {
        self == .highlight ? RGBAColor(red: 1, green: 0.82, blue: 0)
            : RGBAColor(red: 0.1, green: 0.35, blue: 0.8)
    }

    public func stroke(for line: RecognizedLine, in size: CGSize, color: RGBAColor? = nil) throws -> InkStroke {
        let color = color ?? defaultColor
        guard color.isVisibleInkColor else { throw TextMarkupError.invalidColor }
        let box = line.box
        guard [box.x, box.y, box.width, box.height, Double(size.width), Double(size.height)].allSatisfy(\.isFinite),
              size.width > 0, size.height > 0, box.x >= 0, box.y >= 0, box.width > 0, box.height > 0,
              box.x + box.width <= 1, box.y + box.height <= 1 else { throw TextMarkupError.invalidBounds }
        let rect = box.denormalized(in: size)
        let width = self == .highlight ? min(rect.height, rect.width)
            : min(rect.width, rect.height, max(0.5, min(2, rect.height * 0.1)))
        let y = self == .underline ? rect.maxY - width / 2 : rect.midY
        return InkStroke(tool: self == .highlight ? .highlighter : .pen,
                         color: color,
                         width: width, points: [
                            InkPoint(x: rect.minX + width / 2, y: y),
                            InkPoint(x: rect.maxX - width / 2, y: y, time: 0.1)
                         ])
    }
}

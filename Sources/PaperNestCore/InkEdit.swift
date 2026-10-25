/// An explicit edit of existing saved strokes; their IDs and source geometry
/// are unchanged by recoloring. Removal remains reversible through undo.
public enum InkEdit: Sendable {
    case recolor(RGBAColor)
    case remove
}

extension RGBAColor {
    /// Reject nonfinite/out-of-gamut components and completely invisible ink.
    public var isVisibleInkColor: Bool {
        [red, green, blue, alpha].allSatisfy { $0.isFinite && (0...1).contains($0) } && alpha > 0
    }
}

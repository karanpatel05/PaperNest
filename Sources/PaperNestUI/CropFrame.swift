import CoreGraphics

/// What a drag in the crop editor grabs.
enum CropHandle: CaseIterable {
    case topLeading, top, topTrailing, leading, trailing, bottomLeading, bottom, bottomTrailing
    /// Dragging inside the crop moves it without resizing.
    case move

    var movesLeadingEdge: Bool { [.topLeading, .leading, .bottomLeading].contains(self) }
    var movesTrailingEdge: Bool { [.topTrailing, .trailing, .bottomTrailing].contains(self) }
    var movesTopEdge: Bool { [.topLeading, .top, .topTrailing].contains(self) }
    var movesBottomEdge: Bool { [.bottomLeading, .bottom, .bottomTrailing].contains(self) }
}

/// Pure drag math for the crop editor. Everything is in points on the
/// uncropped, rotated page (see `PageGeometry.cropRectInUncroppedPage`), so
/// it is independent of the editor's on-screen scale.
enum CropFrame {
    /// The handle a touch at `point` grabs: corners beat edges, edges beat
    /// the interior; nil when the touch misses the crop.
    static func handle(at point: CGPoint, in rect: CGRect, tolerance: CGFloat) -> CropHandle? {
        let expanded = rect.insetBy(dx: -tolerance, dy: -tolerance)
        guard expanded.contains(point) else { return nil }
        let nearLeading = abs(point.x - rect.minX) <= tolerance
        let nearTrailing = abs(point.x - rect.maxX) <= tolerance
        let nearTop = abs(point.y - rect.minY) <= tolerance
        let nearBottom = abs(point.y - rect.maxY) <= tolerance
        switch (nearLeading, nearTrailing, nearTop, nearBottom) {
        case (true, _, true, _): return .topLeading
        case (_, true, true, _): return .topTrailing
        case (true, _, _, true): return .bottomLeading
        case (_, true, _, true): return .bottomTrailing
        case (true, _, _, _): return .leading
        case (_, true, _, _): return .trailing
        case (_, _, true, _): return .top
        case (_, _, _, true): return .bottom
        default: return rect.contains(point) ? .move : nil
        }
    }

    /// `rect` after dragging `handle` by `delta`, kept inside `bounds` and no
    /// smaller than `minSize`. Edges never cross each other.
    static func adjust(_ rect: CGRect, with handle: CropHandle, by delta: CGSize, within bounds: CGRect, minSize: CGSize) -> CGRect {
        if handle == .move {
            let dx = clamp(delta.width, bounds.minX - rect.minX, bounds.maxX - rect.maxX)
            let dy = clamp(delta.height, bounds.minY - rect.minY, bounds.maxY - rect.maxY)
            return rect.offsetBy(dx: dx, dy: dy)
        }
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        if handle.movesLeadingEdge { minX = clamp(rect.minX + delta.width, bounds.minX, maxX - minSize.width) }
        if handle.movesTrailingEdge { maxX = clamp(rect.maxX + delta.width, minX + minSize.width, bounds.maxX) }
        if handle.movesTopEdge { minY = clamp(rect.minY + delta.height, bounds.minY, maxY - minSize.height) }
        if handle.movesBottomEdge { maxY = clamp(rect.maxY + delta.height, minY + minSize.height, bounds.maxY) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// 5% of each side: comfortably above `NormalizedRect.minimumSide` (2%)
    /// so a crop drawn here is always stored as drawn.
    static func minimumSize(for pageSize: CGSize) -> CGSize {
        CGSize(width: pageSize.width * 0.05, height: pageSize.height * 0.05)
    }

    private static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}

import CoreGraphics
import Foundation

/// Selecting a page's text: which fragment a point means, what a word and a
/// line are, and what a selection says and covers.
///
/// A selection is a closed range of fragment positions, counted across the
/// page in reading order. That is all it needs to be: the layout already
/// knows each fragment's text, its box and whether a space follows it.
///
/// Points and boxes are normalized to the upright source, like the layout
/// itself. A caller maps a touch through `PageGeometry` first; nothing here
/// knows about crop, rotation or the screen.
extension PageTextLayout {
    public var fragmentCount: Int { lines.reduce(0) { $0 + $1.fragments.count } }

    /// The layout without the lines that came from `origin`.
    ///
    /// Typed text boxes are part of what find searches, but they are edited
    /// in their own way, so a text selection is made over a layout without
    /// them.
    public func excluding(_ origin: Origin) -> PageTextLayout {
        PageTextLayout(lines: lines.filter { $0.origin != origin })
    }

    /// The fragment whose box is nearest `point`, or nil when the page has
    /// none — or, given a `reach`, when the nearest is farther than that.
    ///
    /// Nearest rather than "under": a drag that wanders into the margin
    /// beside a line still means the end of that line, and a finger is not a
    /// pixel. Distance is to the box, so anywhere inside one is distance
    /// zero, and of two equally near the earlier in reading order wins.
    public func fragmentIndex(nearest point: CGPoint, within reach: Double? = nil) -> Int? {
        var best: (index: Int, distance: Double)?
        var index = 0
        for line in lines {
            for fragment in line.fragments {
                defer { index += 1 }
                let box = fragment.box
                // A character nobody could place cannot be pointed at.
                guard box.width > 0, box.height > 0 else { continue }
                let dx = max(box.x - Double(point.x), 0, Double(point.x) - (box.x + box.width))
                let dy = max(box.y - Double(point.y), 0, Double(point.y) - (box.y + box.height))
                let distance = (dx * dx + dy * dy).squareRoot()
                if best == nil || distance < best!.distance { best = (index, distance) }
            }
        }
        guard let best else { return nil }
        if let reach, best.distance > reach { return nil }
        return best.index
    }

    /// Everything between two points, whichever way the drag went.
    public func selection(from start: CGPoint, to end: CGPoint) -> ClosedRange<Int>? {
        guard let first = fragmentIndex(nearest: start), let last = fragmentIndex(nearest: end) else { return nil }
        return min(first, last)...max(first, last)
    }

    /// The word around a fragment: back to the last space or the start of
    /// the line, forward to the next space or the end of it.
    public func wordRange(around index: Int) -> ClosedRange<Int> {
        let flat = flattened
        guard !flat.isEmpty else { return 0...0 }
        let index = min(max(index, 0), flat.count - 1)
        var lower = index, upper = index
        while lower > 0, flat[lower - 1].line == flat[index].line, !flat[lower - 1].fragment.spaceAfter { lower -= 1 }
        while upper < flat.count - 1, flat[upper + 1].line == flat[index].line, !flat[upper].fragment.spaceAfter {
            upper += 1
        }
        return lower...upper
    }

    /// Every fragment on the same line as this one.
    public func lineRange(around index: Int) -> ClosedRange<Int> {
        let flat = flattened
        guard !flat.isEmpty else { return 0...0 }
        let index = min(max(index, 0), flat.count - 1)
        var lower = index, upper = index
        while lower > 0, flat[lower - 1].line == flat[index].line { lower -= 1 }
        while upper < flat.count - 1, flat[upper + 1].line == flat[index].line { upper += 1 }
        return lower...upper
    }

    /// What a selection says: its fragments with a space where one follows,
    /// and a line break between lines. It never ends in the space or the
    /// break that comes after its last fragment.
    public func text(in range: ClosedRange<Int>) -> String {
        let flat = flattened
        guard let range = clamp(range, count: flat.count) else { return "" }
        var text = ""
        for position in range {
            text += flat[position].fragment.text
            guard position < range.upperBound else { break }
            if flat[position + 1].line != flat[position].line {
                text += "\n"
            } else if flat[position].fragment.spaceAfter {
                text += " "
            }
        }
        return text
    }

    /// What a selection covers: one box per line it touches.
    public func boxes(in range: ClosedRange<Int>) -> [NormalizedRect] {
        let flat = flattened
        guard let range = clamp(range, count: flat.count) else { return [] }
        var boxes: [NormalizedRect] = []
        var currentLine: Int?
        for position in range {
            let box = flat[position].fragment.box
            guard box.width > 0, box.height > 0 else { continue }
            if currentLine == flat[position].line, let last = boxes.indices.last {
                boxes[last] = boxes[last].union(box)
            } else {
                boxes.append(box)
                currentLine = flat[position].line
            }
        }
        return boxes
    }

    private var flattened: [(line: Int, fragment: Fragment)] {
        lines.enumerated().flatMap { index, line in line.fragments.map { (index, $0) } }
    }

    private func clamp(_ range: ClosedRange<Int>, count: Int) -> ClosedRange<Int>? {
        guard count > 0, range.lowerBound < count, range.upperBound >= 0 else { return nil }
        return max(range.lowerBound, 0)...min(range.upperBound, count - 1)
    }
}

extension NormalizedRect {
    /// The smallest box holding both, kept exact: these are text boxes, far
    /// thinner than the smallest crop, and must not be inflated to one.
    public func union(_ other: NormalizedRect) -> NormalizedRect {
        let minX = Swift.min(x, other.x), minY = Swift.min(y, other.y)
        let maxX = Swift.max(x + width, other.x + other.width)
        let maxY = Swift.max(y + height, other.y + other.height)
        return .exact(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

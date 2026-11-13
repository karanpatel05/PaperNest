import CoreGraphics
import Foundation

/// The six pens of the notes editor.
///
/// A preset is not a picture on a button. It is a rule for turning a hand's
/// movement into a line, and the line is what gets stored: every preset ends
/// up as ordinary `InkStroke` points with a width at each one. Nothing about
/// the preset is persisted beside the stroke, so the renderer, the exporter
/// and both platforms draw a fountain-pen line the same way they draw any
/// other, and a document written with one opens anywhere.
///
/// What cannot be expressed as width and opacity — graphite texture, wet-ink
/// pooling — is deliberately not attempted. A texture that only one platform
/// can draw would make the same page look different on the other.
public enum PenPreset: String, Codable, CaseIterable, Sendable {
    case fountain, ballpoint, gel, pencil, marker, brush

    /// Nominal width in source points for a pen picked up for the first time.
    public var defaultWidth: Double {
        switch self {
        case .fountain: 2.5
        case .ballpoint: 1.2
        case .gel: 2
        case .pencil: 1.4
        case .marker: 5
        case .brush: 4
        }
    }

    /// Pencil and marker lay down less than full ink; that is most of what
    /// separates them from a ballpoint of the same width.
    public var defaultOpacity: Double {
        switch self {
        case .pencil: 0.7
        case .marker: 0.9
        case .fountain, .ballpoint, .gel, .brush: 1
        }
    }

    public var widthRange: ClosedRange<Double> {
        switch self {
        case .marker, .brush: 1...16
        case .fountain, .ballpoint, .gel, .pencil: 0.5...12
        }
    }

    /// Whether pressing harder can change this pen's line at all. A ballpoint
    /// and a marker are one width by construction.
    public var respondsToPressure: Bool {
        switch self {
        case .ballpoint, .marker: false
        case .fountain, .gel, .pencil, .brush: true
        }
    }
}

/// One reading of the pointer while a stroke is being drawn, in whatever
/// space the caller is working in. Width shaping only uses differences, so
/// the space does not matter as long as it is uniform.
public struct PenSample: Hashable, Sendable {
    public var x: Double
    public var y: Double
    /// Seconds since the stroke began.
    public var time: Double
    /// 0...1 where the hardware reports it; nil for a mouse, trackpad or
    /// finger, which is most input on a Mac and all of it in a simulator.
    public var pressure: Double?

    public init(x: Double, y: Double, time: Double = 0, pressure: Double? = nil) {
        self.x = x
        self.y = y
        self.time = time
        self.pressure = pressure
    }
}

/// Turns raw samples into stored ink points for a preset.
///
/// The same function draws the live stroke, the saved stroke and the preview
/// in the pen panel, so what the panel promises is what the page gets.
public enum PenDynamics {
    /// Pointer speed, in points per second, treated as "fast". Writing sits
    /// well under this; a flourish reaches it.
    static let fastSpeed = 900.0
    /// The nib of the fountain pen, held at the usual 45° for a right hand.
    static let nibAngle = -Double.pi / 4

    public static func points(from samples: [PenSample], preset: PenPreset,
                              usesPressure: Bool = true) -> [InkPoint] {
        guard !samples.isEmpty else { return [] }
        let count = samples.count
        var scales = [Double](repeating: 1, count: count)
        var previous = 1.0
        for index in 0..<count {
            let raw = rawScale(at: index, in: samples, preset: preset, usesPressure: usesPressure)
            // An exponential average keeps a jittery pointer from producing a
            // jittery outline. Pencil is exempt: its grain *is* the jitter.
            let value = preset == .pencil || index == 0 ? raw : previous * 0.6 + raw * 0.4
            scales[index] = value
            previous = value
        }
        if preset == .fountain || preset == .brush { taper(&scales, floor: preset == .brush ? 0.2 : 0.45) }
        return zip(samples, scales).map { sample, scale in
            InkPoint(x: sample.x, y: sample.y, widthScale: min(max(scale, 0.05), 1), time: sample.time)
        }
    }

    private static func rawScale(at index: Int, in samples: [PenSample], preset: PenPreset,
                                 usesPressure: Bool) -> Double {
        let here = samples[index]
        let before = samples[max(index - 1, 0)]
        let after = samples[min(index + 1, samples.count - 1)]
        let dx = after.x - before.x, dy = after.y - before.y
        let distance = hypot(dx, dy)
        let elapsed = after.time - before.time
        // Without timestamps there is no speed to read, and pretending the
        // pointer was still would thicken every imported or generated line.
        let speed = elapsed > 0.0001 ? min(distance / elapsed / fastSpeed, 1) : 0
        let pressure = usesPressure && preset.respondsToPressure ? here.pressure : nil
        switch preset {
        case .ballpoint, .marker:
            return 1
        case .gel:
            if let pressure { return 0.7 + 0.3 * pressure }
            return 1 - 0.18 * speed
        case .fountain:
            // A broad nib is thin along its own edge and full width across it.
            let across = distance > 0.0001 ? abs(sin(atan2(dy, dx) - nibAngle)) : 0.6
            let nib = 0.3 + 0.7 * across
            if let pressure { return nib * (0.75 + 0.25 * pressure) }
            return nib * (1 - 0.15 * speed)
        case .pencil:
            let grain = 0.82 + 0.18 * noise(index)
            if let pressure { return grain * (0.6 + 0.4 * pressure) }
            return grain * (1 - 0.2 * speed)
        case .brush:
            if let pressure { return 0.15 + 0.85 * pressure }
            return 1 - 0.75 * speed
        }
    }

    /// Thins both ends, the way a nib or brush lands and lifts.
    private static func taper(_ scales: inout [Double], floor: Double) {
        let count = scales.count
        let reach = min(6, count / 3)
        guard reach > 0 else { return }
        for index in 0..<count {
            let fromEnd = min(index, count - 1 - index)
            guard fromEnd < reach else { continue }
            let ramp = floor + (1 - floor) * Double(fromEnd) / Double(reach)
            scales[index] *= ramp
        }
    }

    /// Repeatable noise in 0...1. Deterministic so the same samples always
    /// produce the same stroke: a line that changed every time it was
    /// reshaped could not be tested, and would shimmer in the live preview.
    static func noise(_ index: Int) -> Double {
        let value = sin(Double(index) * 12.9898) * 43758.5453
        return value - value.rounded(.down)
    }
}

/// Evens out a hand-drawn path without moving where it starts or ends.
public enum StrokeSmoothing {
    /// `amount` is 0...1. Zero returns the samples untouched; one runs four
    /// passes of a 1-2-1 average, which is enough to take the stair-steps out
    /// of a mouse without rounding the corners off handwriting.
    public static func smooth(_ samples: [PenSample], amount: Double) -> [PenSample] {
        let passes = Int((min(max(amount, 0), 1) * 4).rounded())
        guard passes > 0, samples.count > 2 else { return samples }
        var current = samples
        for _ in 0..<passes {
            var next = current
            for index in 1..<(current.count - 1) {
                next[index].x = (current[index - 1].x + 2 * current[index].x + current[index + 1].x) / 4
                next[index].y = (current[index - 1].y + 2 * current[index].y + current[index + 1].y) / 4
            }
            current = next
        }
        return current
    }
}

/// A clean shape a rough stroke was understood as.
public enum SnappedShape: Equatable, Sendable {
    case line(CGPoint, CGPoint)
    case ellipse(CGRect)
    case rectangle(CGRect)
    case triangle(CGPoint, CGPoint, CGPoint)

    /// The shape as a polyline. Corners are repeated so a spline-based canvas
    /// keeps them sharp, the same convention `ShapeAnnotation` uses.
    public var outline: [CGPoint] {
        switch self {
        case .line(let a, let b):
            return [a, b]
        case .ellipse(let rect):
            let steps = 72
            var points = (0..<steps).map { index -> CGPoint in
                let angle = Double(index) * 2 * .pi / Double(steps)
                return CGPoint(x: rect.midX + cos(angle) * rect.width / 2,
                               y: rect.midY + sin(angle) * rect.height / 2)
            }
            points.append(points[0])
            return points
        case .rectangle(let rect):
            let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                           CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
                           CGPoint(x: rect.minX, y: rect.minY)]
            return corners.flatMap { [$0, $0, $0] }
        case .triangle(let a, let b, let c):
            return [a, b, c, a].flatMap { [$0, $0, $0] }
        }
    }
}

/// Recognises a rough stroke as a straight line, an ellipse, a rectangle or a
/// triangle.
///
/// Used when the hand pauses at the end of a stroke: the pause is the request,
/// so nothing is ever straightened behind the writer's back. When no shape
/// fits well, the answer is nil and the stroke stays exactly as drawn — a
/// wrong guess is worse than no guess.
public enum StrokeSnapping {
    /// How long the hand has to rest at the end of a stroke to ask for it.
    public static let holdDuration = 0.5

    /// How long the pointer stayed put before it lifted, in seconds.
    ///
    /// Counted back from the lift to the first sample of the final cluster —
    /// the run of samples within `radius` of where the stroke ended — because
    /// the two kinds of input pause differently: a mouse or a finger held
    /// still sends nothing, so the wait is all between the last sample and
    /// the lift, while an Apple Pencil held still keeps reporting tiny
    /// movements, so the wait is all in the samples.
    public static func dwell(_ samples: [PenSample], endTime: Double, radius: Double) -> Double {
        guard let last = samples.last else { return 0 }
        var earliest = last.time
        for sample in samples.reversed() {
            guard hypot(sample.x - last.x, sample.y - last.y) <= radius else { break }
            earliest = sample.time
        }
        return max(endTime, last.time) - earliest
    }

    /// The straight line from where a stroke began to where it ended.
    public static func line(_ points: [CGPoint]) -> SnappedShape? {
        guard let first = points.first, let last = points.last,
              hypot(last.x - first.x, last.y - first.y) > 0.5 else { return nil }
        return .line(first, last)
    }

    public static func recognize(_ points: [CGPoint]) -> SnappedShape? {
        guard points.count >= 3, let first = points.first, let last = points.last else { return nil }
        let length = zip(points, points.dropFirst()).reduce(0.0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        guard length > 12 else { return nil }
        let gap = hypot(last.x - first.x, last.y - first.y)

        // Never far from the straight path between its ends, and never
        // doubling back along it: a line. Judged by distance from the chord
        // and not by how much longer the stroke is than the chord, because a
        // mouse's jitter adds length to a line without making it any less
        // straight.
        if gap > 12 {
            let worst = points.map { distance(from: $0, toLineThrough: first, and: last) }.max() ?? 0
            let along = points.map { (($0.x - first.x) * (last.x - first.x) + ($0.y - first.y) * (last.y - first.y)) / (gap * gap) }
            if worst <= max(gap * 0.06, 2), along.allSatisfy({ $0 > -0.05 && $0 < 1.05 }) {
                return .line(first, last)
            }
        }
        // Anything else has to come back to where it started to be a shape.
        guard gap < length * 0.2 else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        let bounds = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        guard bounds.width > 6, bounds.height > 6 else { return nil }
        let diagonal = hypot(bounds.width, bounds.height)

        let corners = cornerPoints(of: points, tolerance: diagonal * 0.09)
        let ellipseError = meanEllipseError(points, in: bounds)
        if corners.count == 3 {
            return .triangle(corners[0], corners[1], corners[2])
        }
        if corners.count == 4, meanRectangleError(points, in: bounds) < diagonal * 0.05,
           ellipseError > 0.09 {
            return .rectangle(bounds)
        }
        return ellipseError < 0.14 ? .ellipse(bounds) : nil
    }

    /// The vertices left after simplifying a closed stroke, with the closing
    /// duplicate removed.
    static func cornerPoints(of points: [CGPoint], tolerance: Double) -> [CGPoint] {
        var simplified = simplify(points, tolerance: tolerance)
        if let first = simplified.first, let last = simplified.last, simplified.count > 1,
           hypot(last.x - first.x, last.y - first.y) <= tolerance * 2.5 {
            simplified.removeLast()
        }
        // A stroke that began part-way along a side leaves its starting point
        // behind as a vertex that is not a corner. Drop any vertex lying on
        // the line between its neighbours, going round the closed shape.
        var index = 0
        while simplified.count > 3, index < simplified.count {
            let before = simplified[(index + simplified.count - 1) % simplified.count]
            let after = simplified[(index + 1) % simplified.count]
            if distance(from: simplified[index], toSegmentFrom: before, to: after) <= tolerance {
                simplified.remove(at: index)
            } else {
                index += 1
            }
        }
        return simplified
    }

    /// Ramer–Douglas–Peucker.
    static func simplify(_ points: [CGPoint], tolerance: Double) -> [CGPoint] {
        guard points.count > 2, let first = points.first, let last = points.last else { return points }
        var worst = 0.0, split = 0
        for index in 1..<(points.count - 1) {
            let gap = first == last
                ? hypot(points[index].x - first.x, points[index].y - first.y)
                : distance(from: points[index], toSegmentFrom: first, to: last)
            if gap > worst { worst = gap; split = index }
        }
        guard worst > tolerance else { return [first, last] }
        let head = simplify(Array(points[...split]), tolerance: tolerance)
        let tail = simplify(Array(points[split...]), tolerance: tolerance)
        return head.dropLast() + tail
    }

    private static func meanEllipseError(_ points: [CGPoint], in bounds: CGRect) -> Double {
        let rx = bounds.width / 2, ry = bounds.height / 2
        let total = points.reduce(0.0) { sum, point in
            let nx = (point.x - bounds.midX) / rx, ny = (point.y - bounds.midY) / ry
            return sum + abs(hypot(nx, ny) - 1)
        }
        return total / Double(points.count)
    }

    private static func meanRectangleError(_ points: [CGPoint], in bounds: CGRect) -> Double {
        let total = points.reduce(0.0) { sum, point in
            sum + min(abs(point.x - bounds.minX), abs(point.x - bounds.maxX),
                      abs(point.y - bounds.minY), abs(point.y - bounds.maxY))
        }
        return total / Double(points.count)
    }

    private static func distance(from point: CGPoint, toLineThrough a: CGPoint, and b: CGPoint) -> Double {
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        return abs((b.x - a.x) * (a.y - point.y) - (a.x - point.x) * (b.y - a.y)) / length
    }

    private static func distance(from point: CGPoint, toSegmentFrom a: CGPoint, to b: CGPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }
}

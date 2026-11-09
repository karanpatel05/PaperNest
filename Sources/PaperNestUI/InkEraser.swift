import CoreGraphics
import Foundation
import PaperNestCore

enum InkEraserMode: String, CaseIterable { case precision, stroke }

/// Circular erasure in upright source space. A swept circle is a capsule;
/// clipping segments analytically catches fast drags without resampling ink.
enum InkEraser {
    static func fragments(of ink: InkStroke, path: [CGPoint], diameter: Double) -> [InkStroke] {
        guard !path.isEmpty, diameter.isFinite, diameter > 0, !ink.points.isEmpty else { return [ink] }
        if ink.points.count == 1 {
            let point = ink.points[0]
            return cuts(from: CGPoint(x: point.x, y: point.y), to: CGPoint(x: point.x, y: point.y),
                        path: path, radius: diameter / 2 + ink.width(at: point) / 2).isEmpty ? [ink] : []
        }
        var fragments: [[InkPoint]] = []
        var current: [InkPoint] = []
        var changed = false
        for (a, b) in zip(ink.points, ink.points.dropFirst()) {
            let intervals = cuts(from: CGPoint(x: a.x, y: a.y), to: CGPoint(x: b.x, y: b.y), path: path,
                                 radius: diameter / 2 + max(ink.width(at: a), ink.width(at: b)) / 2)
            changed = changed || !intervals.isEmpty
            var start = 0.0
            var kept: [ClosedRange<Double>] = []
            for cut in intervals {
                if cut.lowerBound > start { kept.append(start...cut.lowerBound) }
                start = max(start, cut.upperBound)
            }
            if start < 1 { kept.append(start...1) }
            for range in kept {
                let first = interpolate(a, b, range.lowerBound)
                let last = interpolate(a, b, range.upperBound)
                if let previous = current.last, hypot(previous.x - first.x, previous.y - first.y) > 0.000001 {
                    fragments.append(current); current = []
                }
                if current.isEmpty { current.append(first) }
                current.append(last)
                if range.upperBound < 1 { fragments.append(current); current = [] }
            }
            if kept.isEmpty, !current.isEmpty { fragments.append(current); current = [] }
        }
        guard changed else { return [ink] }
        if !current.isEmpty { fragments.append(current) }
        return fragments.map { points in
            var result = ink
            result.points = points
            return result
        }
    }

    static func hits(_ ink: InkStroke, path: [CGPoint], radius: Double) -> Bool {
        guard let first = ink.points.first, !path.isEmpty else { return false }
        if ink.points.count == 1 {
            let p = CGPoint(x: first.x, y: first.y)
            return !cuts(from: p, to: p, path: path, radius: radius + ink.width(at: first) / 2).isEmpty
        }
        return zip(ink.points, ink.points.dropFirst()).contains { a, b in
            !cuts(from: CGPoint(x: a.x, y: a.y), to: CGPoint(x: b.x, y: b.y), path: path,
                  radius: radius + max(ink.width(at: a), ink.width(at: b)) / 2).isEmpty
        }
    }

    /// The exact segment fractions covered by any capsule, merged in order.
    private static func cuts(from a: CGPoint, to b: CGPoint, path: [CGPoint], radius: Double) -> [ClosedRange<Double>] {
        var intervals: [ClosedRange<Double>] = []
        let dx = b.x - a.x, dy = b.y - a.y
        for center in path {
            let x = a.x - center.x, y = a.y - center.y
            let aa = dx * dx + dy * dy
            let cc = x * x + y * y - radius * radius
            if aa < 1e-12 {
                if cc <= 0 { intervals.append(0...1) }
            } else {
                let bb = 2 * (x * dx + y * dy)
                let discriminant = bb * bb - 4 * aa * cc
                if discriminant >= 0 {
                    let low = max(0, (-bb - sqrt(discriminant)) / (2 * aa))
                    let high = min(1, (-bb + sqrt(discriminant)) / (2 * aa))
                    if low <= high { intervals.append(low...high) }
                }
            }
        }
        for (c, d) in zip(path, path.dropFirst()) {
            let length = hypot(d.x - c.x, d.y - c.y)
            guard length > 1e-9 else { continue }
            let ux = (d.x - c.x) / length, uy = (d.y - c.y) / length
            let x = a.x - c.x, y = a.y - c.y
            var low = 0.0, high = 1.0
            if clip(x * ux + y * uy, dx * ux + dy * uy, minimum: 0, maximum: length, low: &low, high: &high),
               clip(-x * uy + y * ux, -dx * uy + dy * ux, minimum: -radius, maximum: radius, low: &low, high: &high) {
                intervals.append(low...high)
            }
        }
        var merged: [ClosedRange<Double>] = []
        for interval in intervals.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, interval.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, interval.upperBound)
            } else { merged.append(interval) }
        }
        return merged
    }

    private static func clip(_ origin: Double, _ delta: Double, minimum: Double, maximum: Double,
                             low: inout Double, high: inout Double) -> Bool {
        if abs(delta) < 1e-12 { return origin >= minimum && origin <= maximum }
        let a = (minimum - origin) / delta, b = (maximum - origin) / delta
        low = max(low, min(a, b)); high = min(high, max(a, b))
        return low <= high
    }

    private static func interpolate(_ a: InkPoint, _ b: InkPoint, _ t: Double) -> InkPoint {
        InkPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t,
                 widthScale: a.widthScale + (b.widthScale - a.widthScale) * t,
                 time: a.time + (b.time - a.time) * t)
    }
}

import CoreGraphics
import Foundation

/// Writing made of single-stroke letters: each letter is one to three pen
/// paths along its centre line, roughly as a hand draws it, with a seeded
/// wobble, a slight slant and an uneven baseline. Synthetic, and printed
/// rather than joined up: it is nobody's real handwriting, and a test that
/// reads it says only that this kind of writing is read.
///
/// Strokes come back as point paths in page points with a top-left origin,
/// so this file needs nothing from the app's modules and the UI tests can
/// use it too.
public enum SyntheticHandwriting {
    /// The characters this writing can draw, besides spaces and newlines.
    public static var letters: Set<Character> { Set(glyphs.keys) }

    /// The strokes for `text`, written from `origin` (the first baseline's
    /// left end) with an x-height of `size` points. A newline starts a new
    /// line below; anything not in `letters` throws.
    public static func strokes(_ text: String, origin: CGPoint = CGPoint(x: 60, y: 140), size: CGFloat = 18,
                               seed: UInt64 = 1) throws -> [[CGPoint]] {
        var random = Wobble(seed: seed)
        var strokes: [[CGPoint]] = []
        var pen = 0.0, baseline = Double(origin.y)
        for character in text {
            if character == "\n" { pen = 0; baseline += Double(size) * 3.2; continue }
            if character == " " { pen += 0.75; continue }
            guard let glyph = glyphs[character] else { throw Unsupported(character: character) }
            let lift = random.next(0.06)
            for path in glyph.paths {
                strokes.append(path.map { p in
                    let x = pen + p.x + p.y * 0.12 + random.next(0.018)
                    let y = p.y + lift + random.next(0.018)
                    return CGPoint(x: Double(origin.x) + x * Double(size), y: baseline - y * Double(size))
                })
            }
            pen += glyph.advance + 0.22 + random.next(0.04)
        }
        return strokes
    }

    public struct Unsupported: Error, Equatable { public let character: Character }

    // MARK: - Letters

    /// A letter: its paths in em units (x-height 1, baseline 0, y up) and how
    /// far the pen moves on after it.
    struct Glyph {
        let paths: [[(x: Double, y: Double)]]
        let advance: Double
    }

    typealias P = (x: Double, y: Double)

    static func line(_ a: P, _ b: P) -> [P] {
        let steps = max(2, Int((hypot(b.x - a.x, b.y - a.y) / 0.06).rounded(.up)))
        return (0...steps).map { i in
            let t = Double(i) / Double(steps)
            return (a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
        }
    }

    /// An arc of an ellipse from `from` to `to` degrees; counterclockwise
    /// when `to` is greater.
    static func arc(_ c: P, _ rx: Double, _ ry: Double, _ from: Double, _ to: Double) -> [P] {
        let steps = max(4, Int((abs(to - from) / 12).rounded(.up)))
        return (0...steps).map { i in
            let a = (from + (to - from) * Double(i) / Double(steps)) * .pi / 180
            return (c.x + rx * cos(a), c.y + ry * sin(a))
        }
    }

    static func polyline(_ points: P...) -> [P] {
        zip(points, points.dropFirst()).flatMap { line($0, $1) }
    }

    static let bowl = arc((0.45, 0.5), 0.4, 0.5, 30, 390)
    static let arch = arc((0.5, 0.55), 0.4, 0.45, 180, 0) + line((0.9, 0.55), (0.9, 0))

    static let glyphs: [Character: Glyph] = {
        var g: [Character: Glyph] = [:]
        g["o"] = Glyph(paths: [arc((0.5, 0.5), 0.45, 0.5, 90, 450)], advance: 1.0)
        g["c"] = Glyph(paths: [arc((0.5, 0.5), 0.45, 0.5, 50, 310)], advance: 0.9)
        g["e"] = Glyph(paths: [line((0.08, 0.5), (0.92, 0.5)) + arc((0.5, 0.5), 0.42, 0.5, 0, 315)], advance: 0.95)
        g["a"] = Glyph(paths: [bowl, line((0.86, 1), (0.86, 0))], advance: 0.95)
        g["d"] = Glyph(paths: [bowl, line((0.86, 1.9), (0.86, 0))], advance: 0.95)
        g["g"] = Glyph(paths: [bowl, line((0.86, 1), (0.86, -0.45)) + arc((0.5, -0.45), 0.36, 0.35, 0, -160)],
                       advance: 0.95)
        g["b"] = Glyph(paths: [line((0.1, 1.9), (0.1, 0)), arc((0.52, 0.5), 0.42, 0.5, 210, 570)], advance: 1.0)
        g["p"] = Glyph(paths: [line((0.1, 1), (0.1, -0.8)), arc((0.52, 0.5), 0.42, 0.5, 210, 570)], advance: 1.0)
        g["h"] = Glyph(paths: [line((0.1, 1.9), (0.1, 0)), arch], advance: 1.0)
        g["n"] = Glyph(paths: [line((0.1, 1), (0.1, 0)), arch], advance: 1.0)
        g["m"] = Glyph(paths: [line((0.1, 1), (0.1, 0)),
                               arc((0.35, 0.6), 0.25, 0.4, 180, 0) + line((0.6, 0.6), (0.6, 0)),
                               arc((0.85, 0.6), 0.25, 0.4, 180, 0) + line((1.1, 0.6), (1.1, 0))], advance: 1.25)
        g["r"] = Glyph(paths: [line((0.1, 1), (0.1, 0)), arc((0.45, 0.55), 0.35, 0.4, 180, 55)], advance: 0.65)
        g["u"] = Glyph(paths: [line((0.1, 1), (0.1, 0.45)) + arc((0.5, 0.45), 0.4, 0.45, 180, 360)
                               + line((0.9, 0.45), (0.9, 1)), line((0.9, 1), (0.9, 0))], advance: 1.0)
        g["l"] = Glyph(paths: [line((0.15, 1.9), (0.15, 0))], advance: 0.35)
        g["i"] = Glyph(paths: [line((0.15, 1), (0.15, 0)), line((0.15, 1.4), (0.17, 1.45))], advance: 0.35)
        g["t"] = Glyph(paths: [line((0.3, 1.6), (0.3, 0.15)) + arc((0.5, 0.15), 0.2, 0.15, 180, 300),
                               line((0, 1), (0.65, 1))], advance: 0.7)
        g["f"] = Glyph(paths: [arc((0.6, 1.55), 0.3, 0.3, 20, 180) + line((0.3, 1.55), (0.3, 0)),
                               line((0.05, 1), (0.65, 1))], advance: 0.7)
        g["k"] = Glyph(paths: [line((0.1, 1.9), (0.1, 0)), polyline((0.8, 1), (0.12, 0.4), (0.85, 0))], advance: 0.9)
        g["s"] = Glyph(paths: [arc((0.45, 0.75), 0.33, 0.25, 20, 270) + arc((0.45, 0.25), 0.33, 0.25, 90, -160)],
                       advance: 0.85)
        g["v"] = Glyph(paths: [polyline((0, 1), (0.45, 0), (0.9, 1))], advance: 0.9)
        g["w"] = Glyph(paths: [polyline((0, 1), (0.25, 0), (0.5, 0.8), (0.75, 0), (1, 1))], advance: 1.05)
        g["y"] = Glyph(paths: [line((0.05, 1), (0.5, 0)), line((0.95, 1), (0.3, -0.8))], advance: 0.95)
        // Accented letters: the letter, then its mark as a stroke of its own.
        g["é"] = Glyph(paths: g["e"]!.paths + [line((0.42, 1.3), (0.7, 1.7))], advance: 0.95)
        g["á"] = Glyph(paths: g["a"]!.paths + [line((0.4, 1.3), (0.68, 1.7))], advance: 0.95)
        g["ñ"] = Glyph(paths: g["n"]!.paths + [polyline((0.12, 1.35), (0.35, 1.52), (0.6, 1.35), (0.85, 1.52))],
                       advance: 1.0)
        return g
    }()

    /// A small seeded source of jitter, the same for the same seed.
    public struct Wobble {
        var state: UInt64
        public init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
        public mutating func next(_ amplitude: Double) -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let unit = Double((state >> 11) & ((1 << 53) - 1)) / Double(1 << 53)
            return (unit * 2 - 1) * amplitude
        }
    }
}

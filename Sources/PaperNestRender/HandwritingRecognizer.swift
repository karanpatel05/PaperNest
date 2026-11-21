import CoreGraphics
import Foundation
import PaperNestCore

/// Reads handwriting: the pen strokes someone selected, drawn black on white
/// and given to the same on-device Vision recognizer that reads printed pages.
///
/// Only what the strokes themselves show is read. The page underneath, its
/// filters, crop and rotation play no part: strokes live in the page's
/// upright source space, so how the page is shown cannot change the result.
/// Nothing here is guessed. A stroke Vision cannot read gives no line, and
/// a selection with nothing readable gives no lines at all.
public struct HandwritingRecognizer: Sendable {
    /// A line of writing as read, with where it lies in source space.
    public struct Line: Equatable, Sendable {
        /// A word of the line, where Vision could box it. A word it would not
        /// box is left out rather than given an invented box.
        public struct Word: Equatable, Sendable {
            public let text: String
            public let bounds: CGRect

            public init(text: String, bounds: CGRect) {
                self.text = text
                self.bounds = bounds
            }
        }

        public let text: String
        public let confidence: Double
        public let bounds: CGRect
        public let words: [Word]

        public init(text: String, confidence: Double, bounds: CGRect, words: [Word] = []) {
            self.text = text
            self.confidence = confidence
            self.bounds = bounds
            self.words = words
        }
    }

    /// Stored with each kept reading. Change it whenever what Vision is shown
    /// changes (`pixelsPerPoint`, `margin`, how strokes are drawn), so pages
    /// read the old way are read again.
    /// `.2` (2026-11-21) keeps each line's word boxes, so Find can highlight a
    /// handwritten word; pages read by `.1` are read again.
    public static let engineVersion = "vision.handwriting.2"

    /// The languages it reads in, as asked.
    public var languages: [String] { recognizer.languages }

    /// Room left around the writing, as a share of its height: Vision misses
    /// letters that touch the edge of the picture.
    static let margin: CGFloat = 0.35
    /// How many pixels a source point is drawn at. Writing a few points high
    /// on a page would otherwise come out too small for Vision to read.
    static let pixelsPerPoint: CGFloat = 3
    /// The longest side of the picture, so a whole page of writing does not
    /// make an image Vision struggles with.
    static let maximumSide: CGFloat = 4096

    private let recognizer: TextRecognizer

    public init(languages: [String] = TextRecognizer.preferredLanguages) {
        recognizer = TextRecognizer(languages: languages)
    }

    /// The strokes that are writing: pen ink. A highlighter's mark is colour
    /// laid over the page, not letters.
    public static func writing(in strokes: [InkStroke]) -> [InkStroke] {
        strokes.filter { $0.tool == .pen && !$0.points.isEmpty }
    }

    /// The box the strokes cover in source space, their widths included.
    public static func bounds(of strokes: [InkStroke]) -> CGRect? {
        var box: CGRect?
        for stroke in strokes {
            for point in stroke.points {
                let half = stroke.width(at: point) / 2
                let dot = CGRect(x: point.x - half, y: point.y - half, width: half * 2, height: half * 2)
                box = box?.union(dot) ?? dot
            }
        }
        return box
    }

    /// The pen strokes drawn black on white, and the part of the page the
    /// picture covers (source space). Nil when there is no writing.
    public static func picture(of strokes: [InkStroke]) -> (image: CGImage, covers: CGRect)? {
        let pen = writing(in: strokes)
        guard let ink = bounds(of: pen) else { return nil }
        let pad = max(ink.height, 12) * margin
        let covers = ink.insetBy(dx: -pad, dy: -pad)
        let scale = min(pixelsPerPoint, maximumSide / max(covers.width, covers.height))
        let width = Int((covers.width * scale).rounded(.up)), height = Int((covers.height * scale).rounded(.up))
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Source space has its origin at the top left, the bitmap at the
        // bottom left: one flip, here, and nowhere else.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -covers.minX, y: -covers.minY)
        for stroke in pen {
            var black = stroke
            black.color = .black
            PageRenderer.drawInk(black, in: context)
        }
        guard let image = context.makeImage() else { return nil }
        return (image, covers)
    }

    /// Reads the pen strokes among `strokes`, top line first. Empty when there
    /// is no writing or nothing in it Vision can read.
    public func recognize(_ strokes: [InkStroke]) async throws -> [Line] {
        guard let picture = Self.picture(of: strokes) else { return [] }
        let lines = try await recognizer.recognizeOnADedicatedThread(picture.image)
        let covers = picture.covers
        // `TextRecognizer` already gives boxes with a top-left origin, as
        // shares of the picture: back to source space with no further flip.
        func source(_ box: NormalizedRect) -> CGRect {
            CGRect(x: covers.minX + box.x * covers.width, y: covers.minY + box.y * covers.height,
                   width: box.width * covers.width, height: box.height * covers.height)
        }
        return lines.compactMap { line in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return Line(text: text, confidence: line.confidence, bounds: source(line.box),
                        words: line.words.map { Line.Word(text: $0.text, bounds: source($0.box)) })
        }
    }
}

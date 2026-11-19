import CoreGraphics

/// What the camera is pointed at. The cases are in the order the scanner
/// offers them.
///
/// A mode is here only when it changes what a capture does: where its edges
/// are looked for, what it is cropped to, and what look it starts with.
public enum ScanCaptureMode: String, Sendable, CaseIterable {
    /// A sheet of paper: receipts, forms, typed pages, notes.
    case document
    /// A board on a wall: the largest rectangle in view, drawn with strong
    /// contrast and its lighting evened out.
    case whiteboard
    /// The whole frame, with nothing looked for and nothing cropped.
    case photo
    /// A card: a small rectangle of a card's proportions, front and then back.
    case card
    /// An open book: the two-page spread is found as one outline and, when
    /// it is wider than tall, kept as two pages split at the fold
    /// (`ScanSpread`). The curve of the paper near the fold is not flattened.
    case book

    /// How edges are looked for. Nil when the whole frame is kept.
    public var detection: ScanDetection? {
        switch self {
        case .document:
            // Exactly what the scanner has always asked for: one rectangle,
            // the detector's own range of shapes.
            ScanDetection(minimumSize: 0.2, minimumConfidence: 0.7, candidates: 1, aspectRatios: nil,
                          quadratureTolerance: nil, preference: .mostConfident, readyArea: 0.2)
        case .whiteboard:
            // Boards are photographed from the side of a room, so corners
            // are allowed further from square, and what is wanted is the
            // board, not a sheet pinned to it.
            ScanDetection(minimumSize: 0.3, minimumConfidence: 0.6, candidates: 6, aspectRatios: 0.3...1,
                          quadratureTolerance: 40, preference: .largest, readyArea: 0.2)
        case .card:
            // 85.6 by 54 mm. A card fills less of the frame than a page does.
            ScanDetection(minimumSize: 0.1, minimumConfidence: 0.6, candidates: 6, aspectRatios: 0.5...0.8,
                          quadratureTolerance: nil, preference: .aspectRatio(54 / 85.6), readyArea: 0.03)
        case .book:
            // Measured on drawn spreads through the real detector: the whole
            // spread is found, fold shadow, dark fold line and a curl of the
            // page edges toward the fold included, with corners within 2% of
            // the picture; a strong curl in a portrait photo can leave only
            // one page found, which is then kept whole, not split.
            ScanDetection(minimumSize: 0.3, minimumConfidence: 0.5, candidates: 8, aspectRatios: 0.4...1,
                          quadratureTolerance: 35, preference: .largest, readyArea: 0.25)
        case .photo:
            nil
        }
    }

    /// Whether edges are found, outlined and cropped to. Also whether there
    /// is an automatic shutter: it waits for a rectangle to hold still.
    public var findsEdges: Bool { detection != nil }

    /// Whether a second capture is offered as the other side of the first.
    public var pairsSides: Bool { self == .card }

    /// The look a new capture starts with. `defaultPreset` is the person's
    /// own default filter; it is for paper, so a photo is kept as taken and
    /// a board keeps the look that makes it a board scan.
    public func startingAppearance(defaultPreset: ScanPreset) -> ScanAppearance {
        switch self {
        case .document, .card, .book: ScanAppearance(preset: defaultPreset)
        case .photo: .original
        case .whiteboard: ScanAppearance(preset: .highContrast,
                                         cleanup: ScanCleanup(removeShadows: 1, whitenBackground: 0.6, sharpenText: 0.2))
        }
    }
}

/// Four corners found in a picture, as shares of it measured from the top-left.
public struct ScanQuad: Equatable, Sendable {
    public var topLeft: CGPoint
    public var topRight: CGPoint
    public var bottomRight: CGPoint
    public var bottomLeft: CGPoint
    /// 0...1, how sure the detector was.
    public var confidence: Double

    public init(topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint, confidence: Double) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
        self.confidence = confidence
    }

    /// In the order a scanned page's crop uses.
    public var corners: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    /// The share of the picture the quad covers.
    public var area: Double {
        let points = corners
        var twice = 0.0
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            twice += Double(points[index].x * next.y - next.x * points[index].y)
        }
        return abs(twice) / 2
    }

    /// The quad's shorter side over its longer side, 0...1, in the picture's
    /// true proportions. `imageAspect` is the picture's width over its height.
    public func aspectRatio(imageAspect: Double) -> Double {
        func length(_ a: CGPoint, _ b: CGPoint) -> Double {
            let dx = Double(a.x - b.x) * imageAspect, dy = Double(a.y - b.y)
            return (dx * dx + dy * dy).squareRoot()
        }
        let across = (length(topLeft, topRight) + length(bottomLeft, bottomRight)) / 2
        let down = (length(topLeft, bottomLeft) + length(topRight, bottomRight)) / 2
        let longer = max(across, down)
        return longer > 0 ? min(across, down) / longer : 0
    }
}

/// What a mode asks the rectangle detector for, and which of its answers it takes.
public struct ScanDetection: Equatable, Sendable {
    public enum Preference: Equatable, Sendable {
        /// The one the detector is surest of.
        case mostConfident
        /// The one covering most of the picture.
        case largest
        /// The one whose shorter side over its longer side is nearest this.
        case aspectRatio(Double)
    }

    /// The smallest rectangle looked for, as a share of the picture's shorter side.
    public var minimumSize: Double
    public var minimumConfidence: Double
    /// How many rectangles the detector is asked for.
    public var candidates: Int
    /// Shorter side over longer side. Nil leaves the detector's own range.
    public var aspectRatios: ClosedRange<Double>?
    /// How far, in degrees, a corner may be from square. Nil leaves the detector's own.
    public var quadratureTolerance: Double?
    public var preference: Preference
    /// The share of the frame the thing must cover before a capture is worth
    /// taking; smaller, and the scanner says to move closer.
    ///
    /// Above what the detector can find at all (`minimumSize`), or the advice
    /// could never be given: measured on drawn scenes through the real
    /// detector, the smallest found was about 5% of the frame for a sheet,
    /// 11% for a board and 1% for a card (`ScanFeedbackDetectionTests`).
    public var readyArea: Double

    public init(minimumSize: Double, minimumConfidence: Double, candidates: Int, aspectRatios: ClosedRange<Double>?,
                quadratureTolerance: Double?, preference: Preference, readyArea: Double = 0.2) {
        self.minimumSize = minimumSize
        self.minimumConfidence = minimumConfidence
        self.candidates = candidates
        self.aspectRatios = aspectRatios
        self.quadratureTolerance = quadratureTolerance
        self.preference = preference
        self.readyArea = readyArea
    }

    /// The quad to crop to, or nil when nothing found is of a shape this
    /// mode accepts. The detector's shares are of the picture, not of the
    /// thing, so shapes are judged here again in true proportions.
    public func best(of found: [ScanQuad], imageAspect: Double) -> ScanQuad? {
        let fitting = found.filter { quad in
            guard let aspectRatios else { return true }
            return aspectRatios.contains(quad.aspectRatio(imageAspect: imageAspect))
        }
        switch preference {
        case .mostConfident: return fitting.max { $0.confidence < $1.confidence }
        case .largest: return fitting.max { $0.area < $1.area }
        case .aspectRatio(let wanted):
            return fitting.min { abs($0.aspectRatio(imageAspect: imageAspect) - wanted) < abs($1.aspectRatio(imageAspect: imageAspect) - wanted) }
        }
    }
}

import CoreGraphics

/// What the scanner tells someone pointing the camera, in the order it is
/// worth fixing: there is no use holding still over a page in the dark.
public enum ScanCaptureFeedback: String, Sendable, Equatable, CaseIterable {
    /// The frame is too dark to read a page in.
    case improveLighting
    /// The page nearly touches the edge of the frame and may be cut off.
    case moveBack
    /// The page covers too little of the frame to be read well.
    case moveCloser
    /// The page is found but still moving.
    case holdSteady
    /// Good to take: the automatic shutter fires on it, or, with Auto off,
    /// it is good to take by hand.
    case ready
}

/// One look at the camera's frame.
public struct ScanFrameObservation: Sendable, Equatable {
    /// The thing found, as shares of the frame from its top-left, in any
    /// consistent order. Empty when nothing was found.
    public var corners: [CGPoint]
    /// How bright the frame is, 0 black to 1 white. Nil when it could not be
    /// read; unknown brightness never holds a capture back.
    public var luminance: Double?

    public init(corners: [CGPoint], luminance: Double?) {
        self.corners = corners
        self.luminance = luminance
    }
}

/// Decides, frame by frame, what to tell the person and whether the automatic
/// shutter takes the picture — **in one step, from one look**, so the label
/// can never say Ready over a page the shutter will not take.
///
/// Corners are judged in the camera's frame, which is what the photo
/// contains. The preview fills the screen and so trims the frame's sides, so
/// a page can look cut off on screen and still be whole in the photo; this
/// judges the photo.
///
/// Thresholds, other than the steadiness rule the automatic shutter has
/// always used, are untuned on a real camera: the sizes come from drawn
/// scenes through the real detector, and the darkness level is a guess.
public struct ScanCaptureGuide: Sendable {
    /// Every corner within this share of the frame of where it was in the
    /// last look, for this many looks in a row (about two seconds), before a
    /// page counts as steady. The automatic shutter's rule since it existed.
    public static let steadyTolerance = 0.025
    public static let steadyLooks = 8
    /// Too dark below the first, and dark until above the second, so the
    /// advice does not flicker on a borderline frame.
    public static let darkBelow = 0.12
    public static let lightAgainAbove = 0.18
    /// A corner nearer the edge than this is nearly cut off; it is clear
    /// again only past the second. The detector does not report a page
    /// running off the frame at all, nor corners nearer than about 1.6% of
    /// the edge, so this only catches a page about to be cut.
    public static let edgeMargin = 0.025
    public static let edgeClearAgain = 0.035
    /// Close enough again only past this many times `readyArea`.
    public static let closeEnoughAgain = 1.15
    /// Seconds between two automatic captures.
    public static let cooldown = 3.0
    /// Looks with nothing found before the shutter waits for a new sheet no
    /// longer: the kept one has left the frame.
    public static let goneLooks = 3

    public struct Decision: Sendable, Equatable {
        /// Nil: nothing to say.
        public var feedback: ScanCaptureFeedback?
        /// Take the picture now.
        public var fire: Bool
    }

    private let readyArea: Double?
    private var previous: [CGPoint] = []
    private var steadyCount = 0
    private var dark = false
    private var tooSmall = false
    private var nearEdge = false
    private var armed = true
    private var goneCount = 0
    private var lastCapture = -Double.infinity

    /// `detection` nil (a photo): nothing is looked for, so only the light is
    /// judged and the automatic shutter never fires.
    public init(detection: ScanDetection?) {
        readyArea = detection?.readyArea
    }

    /// Starts over: a new mode, the shutter switched, the camera interrupted.
    public mutating func reset() {
        self = ScanCaptureGuide(readyArea: readyArea)
    }

    private init(readyArea: Double?) { self.readyArea = readyArea }

    /// After a capture is kept: the same sheet is probably still in view, so
    /// the automatic shutter waits for it to leave before taking another.
    public mutating func waitForNextSheet() {
        previous = []
        steadyCount = 0
        goneCount = 0
        armed = false
    }

    public mutating func observe(_ look: ScanFrameObservation, at time: Double, automatic: Bool) -> Decision {
        judgeLight(look.luminance)
        let corners = look.corners
        guard corners.count == 4, let readyArea else {
            previous = []
            steadyCount = 0
            goneCount += 1
            if goneCount >= Self.goneLooks { armed = true }
            tooSmall = false
            nearEdge = false
            return Decision(feedback: dark ? .improveLighting : nil, fire: false)
        }
        goneCount = 0
        let steady = previous.count == 4 && zip(corners, previous).allSatisfy {
            Double(hypot($0.x - $1.x, $0.y - $1.y)) < Self.steadyTolerance
        }
        previous = corners
        steadyCount = steady ? steadyCount + 1 : 0
        judgeSize(Self.area(of: corners), readyArea: readyArea)
        judgeEdge(Self.edgeDistance(of: corners))

        // A kept sheet still in view: nothing to say about it, and nothing
        // to take, until it has gone.
        if automatic, !armed { return Decision(feedback: nil, fire: false) }
        let feedback: ScanCaptureFeedback =
            if dark { .improveLighting }
            else if nearEdge { .moveBack }
            else if tooSmall { .moveCloser }
            else if steadyCount < Self.steadyLooks { .holdSteady }
            else { .ready }
        guard feedback == .ready else { return Decision(feedback: feedback, fire: false) }
        guard automatic else { return Decision(feedback: .ready, fire: false) }
        // Steady and good, but too soon after the last one: say nothing
        // rather than Ready over a picture that will not be taken.
        guard time - lastCapture >= Self.cooldown else { return Decision(feedback: nil, fire: false) }
        armed = false
        steadyCount = 0
        lastCapture = time
        return Decision(feedback: .ready, fire: true)
    }

    private mutating func judgeLight(_ luminance: Double?) {
        guard let luminance else { dark = false; return }
        dark = dark ? luminance < Self.lightAgainAbove : luminance < Self.darkBelow
    }

    private mutating func judgeSize(_ area: Double, readyArea: Double) {
        tooSmall = tooSmall ? area < readyArea * Self.closeEnoughAgain : area < readyArea
    }

    private mutating func judgeEdge(_ distance: Double) {
        nearEdge = nearEdge ? distance < Self.edgeClearAgain : distance < Self.edgeMargin
    }

    /// The share of the frame inside the corners (the shoelace formula): the
    /// corners are shares of each side, so this is a share of the frame.
    static func area(of corners: [CGPoint]) -> Double {
        var twice = 0.0
        for index in corners.indices {
            let a = corners[index], b = corners[(index + 1) % corners.count]
            twice += Double(a.x * b.y - b.x * a.y)
        }
        return abs(twice) / 2
    }

    /// How near the nearest corner comes to any edge of the frame.
    static func edgeDistance(of corners: [CGPoint]) -> Double {
        corners.map { Double(min($0.x, 1 - $0.x, $0.y, 1 - $0.y)) }.min() ?? 1
    }
}

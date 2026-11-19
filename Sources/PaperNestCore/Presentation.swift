import CoreGraphics
import Foundation

/// A document shown full screen, one page at a time: which page, and where
/// the presenter can go from it. Nothing about a presentation is saved.
public struct PresentationDeck: Equatable, Sendable {
    public let pageCount: Int
    public private(set) var index: Int

    /// Starts at `index` — the page being read when Present was chosen —
    /// held to the document's pages.
    public init(pageCount: Int, startingAt index: Int) {
        self.pageCount = max(0, pageCount)
        self.index = Self.held(index, count: self.pageCount)
    }

    public var canGoBack: Bool { index > 0 }
    public var canGoForward: Bool { index < pageCount - 1 }

    /// The next page; false, and nothing changes, on the last.
    @discardableResult public mutating func forward() -> Bool {
        guard canGoForward else { return false }
        index += 1
        return true
    }

    /// The page before; false, and nothing changes, on the first.
    @discardableResult public mutating func back() -> Bool {
        guard canGoBack else { return false }
        index -= 1
        return true
    }

    public mutating func go(to index: Int) { self.index = Self.held(index, count: pageCount) }

    private static func held(_ index: Int, count: Int) -> Int { count == 0 ? 0 : min(max(index, 0), count - 1) }
}

/// Where the laser pointer has been in the last moment: a dot with a short
/// tail that fades. Points are shares of the page shown (top-left origin),
/// so the dot stays on the same words however the page is laid out. Times
/// are passed in, never read from a clock. The pointer marks nothing: it is
/// never ink and never saved.
public struct LaserTrail: Equatable, Sendable {
    /// How long a point stays visible, fading all the way.
    public static let lifetime: TimeInterval = 0.6
    /// The most points kept: a long gesture keeps only its newest.
    public static let maximumPoints = 64

    public struct Point: Equatable, Sendable {
        public let location: CGPoint
        public let time: TimeInterval
    }

    public private(set) var points: [Point] = []

    public init() {}

    /// Adds where the pointer is at `time`, and drops points too old to show.
    public mutating func add(_ location: CGPoint, at time: TimeInterval) {
        points.removeAll { time - $0.time >= Self.lifetime }
        points.append(Point(location: location, time: time))
        if points.count > Self.maximumPoints { points.removeFirst(points.count - Self.maximumPoints) }
    }

    /// The points showing at `time`, oldest first, each with its opacity:
    /// 1 when new, falling to nothing at `lifetime`.
    public func visible(at time: TimeInterval) -> [(location: CGPoint, opacity: Double)] {
        points.compactMap { point in
            let age = time - point.time
            guard age >= 0, age < Self.lifetime else { return nil }
            return (point.location, 1 - age / Self.lifetime)
        }
    }

    /// Whether anything still shows at `time`: while it does, the trail is redrawn.
    public func isAlive(at time: TimeInterval) -> Bool {
        points.contains { time - $0.time < Self.lifetime && time >= $0.time }
    }

    public mutating func clear() { points.removeAll() }
}

/// What a finger does on a presented page: nothing but tap and swipe, point
/// with the laser, or draw with the pen. One at a time.
public enum PresentationPointer: String, CaseIterable, Sendable {
    case none
    case laser
    case pen
}

/// What the presenter draws with the pen pointer on the page shown: strokes
/// as shares of the page (top-left origin). Never ink and never saved —
/// cleared when the page changes or on request.
public struct PenSketch: Equatable, Sendable {
    /// The strokes finished, oldest first.
    public private(set) var strokes: [[CGPoint]] = []
    /// The stroke being drawn, if any.
    public private(set) var current: [CGPoint]?

    public init() {}

    /// Continues the stroke being drawn to `point`, starting one if none is.
    /// Points are held to the page.
    public mutating func extend(to point: CGPoint) {
        let held = CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
        if current == nil { current = [] }
        if current?.last != held { current?.append(held) }
    }

    /// Finishes the stroke being drawn. A touch that never moved is a tap,
    /// not a stroke, and leaves nothing.
    public mutating func end() {
        if let current, current.count > 1 { strokes.append(current) }
        current = nil
    }

    public mutating func clear() {
        strokes.removeAll()
        current = nil
    }

    public var isEmpty: Bool { strokes.isEmpty && current == nil }
}

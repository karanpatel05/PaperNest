import Foundation

/// Conservative automatic shutter: stable rectangle, cooldown, then require the
/// previous sheet to leave the frame before another automatic exposure.
struct ScannerCapturePolicy {
    private var previous: [CGPoint] = []
    private var stableFrames = 0
    private var absentFrames = 0
    private var armed = true
    private var lastCapture = -Double.infinity

    mutating func reset() { self = ScannerCapturePolicy() }

    mutating func waitForNextSheet() {
        previous = []; stableFrames = 0; absentFrames = 0; armed = false
    }

    mutating func observe(_ points: [CGPoint], at time: Double) -> Bool {
        guard points.count == 4 else {
            absentFrames += 1
            stableFrames = 0
            previous = []
            if absentFrames >= 3 { armed = true }
            return false
        }
        absentFrames = 0
        let stable = previous.count == 4 && zip(points, previous).allSatisfy {
            hypot($0.x - $1.x, $0.y - $1.y) < 0.025
        }
        previous = points
        stableFrames = stable ? stableFrames + 1 : 0
        guard armed, stableFrames >= 8, time - lastCapture >= 3 else { return false }
        armed = false
        stableFrames = 0
        lastCapture = time
        return true
    }
}

/// Permission completion and interruption recovery must honor the latest view
/// intent, including a stop issued while the permission dialog is pending.
struct ScannerSessionIntent {
    private(set) var wantsRunning = false
    mutating func start() { wantsRunning = true }
    mutating func stop() { wantsRunning = false }
}


/// A captured draft stays separate from the accepted scan queue until Keep.
/// Reject late/duplicate deliveries while a decision is already on screen.
struct ScannerCaptureReview<Capture> {
    private(set) var pending: Capture?

    mutating func stage(_ capture: Capture) -> Bool {
        guard pending == nil else { return false }
        pending = capture
        return true
    }

    mutating func keep() -> Capture? {
        defer { pending = nil }
        return pending
    }

    mutating func discard() { pending = nil }
}

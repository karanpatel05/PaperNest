import Foundation

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

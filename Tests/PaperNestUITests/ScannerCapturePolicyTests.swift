import Foundation
import Testing
@testable import PaperNestUI

struct ScannerCapturePolicyTests {
    @Test func failedPageNeverProducesPartialScan() {
        #expect(ScanCaptureEncoding.pages(count: 3) { $0 == 1 ? nil : Data([$0 == 0 ? 1 : 3]) } == nil)
    }

    @Test func capturedOrderSurvivesEncoding() {
        #expect(ScanCaptureEncoding.pages(count: 3) { Data([UInt8($0)]) } == [Data([0]), Data([1]), Data([2])])
    }

    @Test func emptyScanCannotBeSaved() {
        #expect(ScanCaptureEncoding.pages(count: 0) { _ in Data() } == nil)
    }
}

struct ScannerAutomaticCaptureTests {
    let rectangle = [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.1), CGPoint(x: 0.9, y: 0.9), CGPoint(x: 0.1, y: 0.9)]

    @Test func stableSheetCapturesOnlyOnceUntilRemoved() {
        var policy = ScannerCapturePolicy()
        var captures = 0
        for frame in 0..<40 {
            if policy.observe(rectangle, at: Double(frame)) { captures += 1 }
        }
        #expect(captures == 1)
        for frame in 40..<43 { let result = policy.observe([], at: Double(frame)); #expect(!result) }
        for frame in 43..<60 {
            if policy.observe(rectangle, at: Double(frame)) { captures += 1 }
        }
        #expect(captures == 2)
    }

    @Test func keepingReviewWaitsForTheNextSheet() {
        var policy = ScannerCapturePolicy()
        policy.waitForNextSheet()
        for frame in 0..<20 { let result = policy.observe(rectangle, at: Double(frame)); #expect(!result) }
        for frame in 20..<23 { let result = policy.observe([], at: Double(frame)); #expect(!result) }
        var captured = false
        for frame in 23..<40 { captured = policy.observe(rectangle, at: Double(frame)) || captured }
        #expect(captured)
    }

    @Test func motionAndInterruptionResetStability() {
        var policy = ScannerCapturePolicy()
        for frame in 0..<6 { let result = policy.observe(rectangle, at: Double(frame)); #expect(!result) }
        policy.reset()
        for frame in 6..<12 { let result = policy.observe(rectangle, at: Double(frame)); #expect(!result) }
        let moved = rectangle.map { CGPoint(x: $0.x + 0.1, y: $0.y) }
        let result = policy.observe(moved, at: 12)
        #expect(!result)
    }
}

struct ScannerSessionIntentTests {
    @Test func pendingPermissionCannotRestartDismissedCamera() {
        var intent = ScannerSessionIntent()
        intent.start() // Permission requested.
        intent.stop() // Review, dismissal, picker or background wins.
        #expect(!intent.wantsRunning) // Delayed permission success must not start.
        #expect(!intent.wantsRunning) // Interruption-ended must not start either.
        intent.start() // Explicit return to capture can resume.
        #expect(intent.wantsRunning)
    }
}


struct ScannerCaptureReviewTests {
    @Test func captureNeedsExplicitKeepBeforeJoiningQueue() {
        var review = ScannerCaptureReview<Data>()
        var queue = [Data([1])]
        let staged = review.stage(Data([2]))
        #expect(staged)
        #expect(queue == [Data([1])])
        let rejected = review.stage(Data([3]))
        #expect(!rejected)
        if let kept = review.keep() { queue.append(kept) }
        #expect(queue == [Data([1]), Data([2])])
        #expect(review.pending == nil)
        #expect(review.keep() == nil)
    }

    @Test func deletingPendingCaptureNeverRemovesAcceptedPages() {
        var review = ScannerCaptureReview<Data>()
        let queue = [Data([1])]
        _ = review.stage(Data([2]))
        review.discard()
        #expect(review.pending == nil)
        #expect(queue == [Data([1])])
        let staged = review.stage(Data([3]))
        #expect(staged)
        #expect(review.keep() == Data([3]))
    }
}

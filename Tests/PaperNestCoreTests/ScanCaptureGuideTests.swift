import CoreGraphics
import Testing
@testable import PaperNestCore

/// What the scanner says while the camera is pointed, and when the automatic
/// shutter fires — decided together, so Ready is never shown over a page the
/// shutter will not take.
@Suite struct ScanCaptureGuideTests {
    /// A sheet covering 64% of the frame, well clear of the edges.
    let sheet = [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.1), CGPoint(x: 0.9, y: 0.9), CGPoint(x: 0.1, y: 0.9)]

    func document() -> ScanCaptureGuide { ScanCaptureGuide(detection: ScanCaptureMode.document.detection) }

    func look(_ corners: [CGPoint], _ luminance: Double? = 0.5) -> ScanFrameObservation {
        ScanFrameObservation(corners: corners, luminance: luminance)
    }

    /// A square of `side` centred at (`x`, `y`).
    func square(_ side: Double, x: Double = 0.5, y: Double = 0.5) -> [CGPoint] {
        let h = side / 2
        return [CGPoint(x: x - h, y: y - h), CGPoint(x: x + h, y: y - h), CGPoint(x: x + h, y: y + h), CGPoint(x: x - h, y: y + h)]
    }

    // MARK: - The automatic shutter, as it has always behaved

    @Test func aSteadySheetIsTakenOnceUntilItIsRemoved() {
        var guide = document()
        var captures = 0
        for frame in 0..<40 where guide.observe(look(sheet, nil), at: Double(frame), automatic: true).fire { captures += 1 }
        #expect(captures == 1)
        for frame in 40..<43 { #expect(!guide.observe(look([], nil), at: Double(frame), automatic: true).fire) }
        for frame in 43..<60 where guide.observe(look(sheet, nil), at: Double(frame), automatic: true).fire { captures += 1 }
        #expect(captures == 2)
    }

    @Test func afterAKeepTheShutterWaitsForTheNextSheet() {
        var guide = document()
        guide.waitForNextSheet()
        for frame in 0..<20 { #expect(!guide.observe(look(sheet), at: Double(frame), automatic: true).fire) }
        for frame in 20..<23 { #expect(!guide.observe(look([]), at: Double(frame), automatic: true).fire) }
        var captured = false
        for frame in 23..<40 { captured = guide.observe(look(sheet), at: Double(frame), automatic: true).fire || captured }
        #expect(captured)
    }

    @Test func movementAndInterruptionStartTheCountAgain() {
        var guide = document()
        for frame in 0..<6 { #expect(!guide.observe(look(sheet), at: Double(frame), automatic: true).fire) }
        guide.reset()
        for frame in 6..<12 { #expect(!guide.observe(look(sheet), at: Double(frame), automatic: true).fire) }
        // Twice the steadiness tolerance, and still clear of the edge.
        let moved = sheet.map { CGPoint(x: $0.x + 0.05, y: $0.y) }
        let decision = guide.observe(look(moved), at: 12, automatic: true)
        #expect(!decision.fire)
        #expect(decision.feedback == .holdSteady)
    }

    // MARK: - What it says

    @Test func holdSteadyUntilEightSteadyLooksThenReady() {
        var guide = document()
        var said: [ScanCaptureFeedback?] = []
        for frame in 0..<10 { said.append(guide.observe(look(sheet), at: Double(frame), automatic: false).feedback) }
        // The first look has nothing to compare with; eight steady looks after it.
        #expect(Array(said.prefix(9)) == Array(repeating: .holdSteady, count: 8) + [.ready])
        #expect(said.last == .ready, "with Auto off, Ready stays while it is good to take by hand")
    }

    @Test func aSmallPageIsToldToComeCloserAndTheEdgeOfTheThresholdDoesNotFlicker() {
        var guide = document()
        // Document wants 20% of the frame. 0.4 × 0.4 is 16%.
        #expect(guide.observe(look(square(0.4)), at: 0, automatic: false).feedback == .moveCloser)
        // 0.46 × 0.46 is 21%: over 20%, but not over 23% (20% × 1.15), so still too small.
        #expect(guide.observe(look(square(0.46)), at: 1, automatic: false).feedback == .moveCloser)
        // 0.5 × 0.5 is 25%: close enough again.
        #expect(guide.observe(look(square(0.5)), at: 2, automatic: false).feedback == .holdSteady)
        // And 21% now stays close enough.
        #expect(guide.observe(look(square(0.46)), at: 3, automatic: false).feedback == .holdSteady)
    }

    @Test func aPageNearlyTouchingTheEdgeIsToldToMoveBack() {
        var guide = document()
        let tight = [CGPoint(x: 0.017, y: 0.1), CGPoint(x: 0.8, y: 0.1), CGPoint(x: 0.8, y: 0.9), CGPoint(x: 0.017, y: 0.9)]
        #expect(guide.observe(look(tight), at: 0, automatic: false).feedback == .moveBack)
        // 3% from the edge: past the 2.5% margin, short of the 3.5% to clear it.
        let nearly = tight.map { $0.x < 0.5 ? CGPoint(x: 0.03, y: $0.y) : $0 }
        #expect(guide.observe(look(nearly), at: 1, automatic: false).feedback == .moveBack)
        let clear = tight.map { $0.x < 0.5 ? CGPoint(x: 0.05, y: $0.y) : $0 }
        #expect(guide.observe(look(clear), at: 2, automatic: false).feedback == .holdSteady)
    }

    @Test func aDarkFrameAsksForLightFirstAndClearsWithSomeMargin() {
        var guide = document()
        #expect(guide.observe(look(square(0.4), 0.05), at: 0, automatic: false).feedback == .improveLighting,
                "light first: a small page in the dark is told about the dark")
        #expect(guide.observe(look([], 0.05), at: 1, automatic: false).feedback == .improveLighting,
                "even with no page found, since the dark may be why")
        #expect(guide.observe(look(sheet, 0.15), at: 2, automatic: false).feedback == .improveLighting,
                "15% is above the 12% that starts it but below the 18% that ends it")
        #expect(guide.observe(look(sheet, 0.25), at: 3, automatic: false).feedback == .holdSteady)
    }

    @Test func unknownBrightnessHoldsNothingBack() {
        var guide = document()
        var last: ScanCaptureGuide.Decision?
        var fired = false
        for frame in 0..<12 {
            last = guide.observe(look(sheet, nil), at: Double(frame), automatic: true)
            fired = fired || last?.fire == true
        }
        #expect(fired)
    }

    @Test func nothingFoundInGoodLightSaysNothing() {
        var guide = document()
        #expect(guide.observe(look([]), at: 0, automatic: false) == .init(feedback: nil, fire: false))
    }

    // MARK: - Ready agrees with the shutter

    @Test func withAutoOnReadyIsShownOnlyWhenTheShutterFires() {
        var guide = document()
        var decisions: [ScanCaptureGuide.Decision] = []
        for frame in 0..<9 { decisions.append(guide.observe(look(sheet), at: Double(frame), automatic: true)) }
        #expect(decisions.filter { $0.feedback == .ready } == [ScanCaptureGuide.Decision(feedback: .ready, fire: true)])
        #expect(decisions.last?.fire == true)
    }

    /// The kept sheet is still in view after Keep: the shutter will not take
    /// it again, so the scanner does not say Ready over it, or anything else.
    @Test func aKeptSheetStillInViewIsNeverCalledReady() {
        var guide = document()
        guide.waitForNextSheet()
        for frame in 0..<20 {
            let decision = guide.observe(look(sheet), at: Double(frame), automatic: true)
            #expect(decision.feedback == nil && !decision.fire)
        }
        for frame in 20..<23 { _ = guide.observe(look([]), at: Double(frame), automatic: true) }
        #expect(guide.observe(look(sheet), at: 23, automatic: true).feedback == .holdSteady, "a new sheet")
    }

    @Test func tooSoonAfterACaptureSaysNothingRatherThanReady() {
        var guide = document()
        for frame in 0..<9 { _ = guide.observe(look(sheet), at: Double(frame) * 0.1, automatic: true) }
        // Taken at 0.8 s. The sheet leaves and another arrives within three seconds.
        for frame in 0..<3 { _ = guide.observe(look([]), at: 0.9 + Double(frame) * 0.1, automatic: true) }
        var said: [ScanCaptureFeedback?] = []
        for frame in 0..<12 {
            let decision = guide.observe(look(sheet), at: 1.2 + Double(frame) * 0.1, automatic: true)
            #expect(!decision.fire, "within three seconds of the last capture")
            said.append(decision.feedback)
        }
        #expect(!said.contains(.ready))
        #expect(said.last == .some(nil))
    }

    /// A change of behaviour, on purpose: Auto used to take any rectangle that
    /// held still. It no longer takes one too small, too dark or nearly cut off.
    @Test func autoNoLongerTakesASteadyPageThatIsNotGoodEnough() {
        let cases: [(String, [CGPoint], Double?)] = [
            ("too small", square(0.35), 0.5),
            ("too dark", sheet, 0.05),
            ("nearly cut off", [CGPoint(x: 0.01, y: 0.1), CGPoint(x: 0.8, y: 0.1), CGPoint(x: 0.8, y: 0.9), CGPoint(x: 0.01, y: 0.9)], 0.5),
        ]
        for (name, corners, luminance) in cases {
            var guide = document()
            var fired = false
            for frame in 0..<30 { fired = guide.observe(look(corners, luminance), at: Double(frame), automatic: true).fire || fired }
            #expect(!fired, "\(name)")
        }
    }

    // MARK: - Each mode

    @Test func aCardIsCloseEnoughSoonerThanAPage() {
        // 0.25 × 0.15 is 3.75% of the frame: a card's 3% is met, a page's 20% is not.
        let card = [CGPoint(x: 0.3, y: 0.4), CGPoint(x: 0.55, y: 0.4), CGPoint(x: 0.55, y: 0.55), CGPoint(x: 0.3, y: 0.55)]
        var cards = ScanCaptureGuide(detection: ScanCaptureMode.card.detection)
        var pages = document()
        #expect(cards.observe(look(card), at: 0, automatic: false).feedback == .holdSteady)
        #expect(pages.observe(look(card), at: 0, automatic: false).feedback == .moveCloser)
    }

    @Test func aPhotoIsOnlyToldAboutTheLightAndNeverTakenAutomatically() {
        var guide = ScanCaptureGuide(detection: ScanCaptureMode.photo.detection)
        #expect(guide.observe(look([], 0.05), at: 0, automatic: true).feedback == .improveLighting)
        var fired = false
        for frame in 1..<20 {
            let decision = guide.observe(look([], 0.6), at: Double(frame), automatic: true)
            fired = fired || decision.fire
            #expect(decision.feedback == nil)
        }
        #expect(!fired)
    }

    @Test func everyModeThatLooksForEdgesWantsMoreThanTheDetectorCanFind() {
        for mode in ScanCaptureMode.allCases {
            guard let detection = mode.detection else { continue }
            // The detector's floor is a share of the shorter side; its square
            // is the least area it could find. Ready must ask for more.
            #expect(detection.readyArea > detection.minimumSize * detection.minimumSize, "\(mode)")
        }
    }

    @Test func areaAndEdgeAreMeasuredInSharesOfTheFrame() {
        #expect(abs(ScanCaptureGuide.area(of: sheet) - 0.64) < 1e-9)
        #expect(abs(ScanCaptureGuide.edgeDistance(of: sheet) - 0.1) < 1e-9)
    }
}

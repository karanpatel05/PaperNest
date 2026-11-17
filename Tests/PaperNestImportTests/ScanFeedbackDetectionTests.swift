import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestRender

/// The scanner's advice is only worth having if it can be given: "Move
/// closer" for a page the detector finds but is too small, "Move back" for a
/// page it finds nearly cut off. Each is checked here on scenes drawn the way
/// `ScanEdgeDetectorTests` draws them, through the real detector and then the
/// guide. One at a time: the detector parks the thread it is called on.
@Suite(.serialized) struct ScanFeedbackDetectionTests {
    typealias Scenes = ScanEdgeDetectorTests

    /// What the guide says about the first look at `picture` in `mode`.
    func advice(_ mode: ScanCaptureMode, _ picture: CGImage) throws -> (ScanQuad?, ScanCaptureFeedback?) {
        let detection = try #require(mode.detection)
        let found = ScanEdgeDetector.detect(detection, in: picture)
        var guide = ScanCaptureGuide(detection: detection)
        let look = ScanFrameObservation(corners: found?.corners ?? [], luminance: 0.5)
        return (found, guide.observe(look, at: 0, automatic: false).feedback)
    }

    @Test func aSmallSheetIsFoundAndToldToComeCloser() throws {
        // 0.3 of the width by 0.39 of the height: 12% of the frame, under Document's 20%.
        let sheet = Scenes.corners((0.35, 0.305), (0.65, 0.305), (0.65, 0.695), (0.35, 0.695))
        let (found, said) = try advice(.document, Scenes.scene(width: 1200, height: 1600, ground: 0.2, [(sheet, 0.95)]))
        #expect(found != nil, "the detector does not find it, so the advice could never be given")
        #expect(said == .moveCloser)
    }

    @Test func aSmallBoardIsFoundAndToldToComeCloser() throws {
        // 0.4 of the width by 0.28 of the height: about 11–12% of the frame, under Whiteboard's 20%.
        let board = Scenes.corners((0.30, 0.36), (0.70, 0.36), (0.70, 0.64), (0.30, 0.64))
        let (found, said) = try advice(.whiteboard, Scenes.scene(width: 1600, height: 1200, ground: 0.45, [(board, 0.93)]))
        #expect(found != nil)
        #expect(said == .moveCloser)
    }

    @Test func aSmallCardIsFoundAndToldToComeCloser() throws {
        // 0.2 of the width, a card's shape: about 2% of the frame, under Card's 3%.
        let height = 0.2 * 0.75 / 1.586
        let card = Scenes.corners((0.3, 0.4), (0.5, 0.4), (0.5, 0.4 + height), (0.3, 0.4 + height))
        let (found, said) = try advice(.card, Scenes.scene(width: 1200, height: 1600, ground: 0.25, [(card, 0.80)]))
        #expect(found != nil)
        #expect(said == .moveCloser)
    }

    @Test func aSheetFillingTheFrameWellIsNotToldAnything() throws {
        let sheet = Scenes.corners((0.18, 0.15), (0.80, 0.12), (0.86, 0.84), (0.14, 0.88))
        let (found, said) = try advice(.document, Scenes.scene(width: 1200, height: 1600, ground: 0.2, [(sheet, 0.95)]))
        #expect(found != nil)
        #expect(said == .holdSteady, "found, big enough, clear of the edges: it only has to hold still")
    }

    /// Drawn 0.8% from the edge, the detector reports the corner about 1.7%
    /// away (measured), inside the 2.5% margin.
    @Test func aSheetNearlyTouchingTheEdgeIsFoundAndToldToMoveBack() throws {
        let sheet = Scenes.corners((0.008, 0.10), (0.80, 0.10), (0.80, 0.90), (0.008, 0.90))
        let (found, said) = try advice(.document, Scenes.scene(width: 1200, height: 1600, ground: 0.2, [(sheet, 0.95)]))
        #expect(found != nil)
        #expect(said == .moveBack)
    }

    /// What "Move back" cannot do: a sheet already running off the frame is
    /// not found at all, so it gets no outline and no advice.
    @Test func aSheetRunningOffTheFrameIsNotFoundAndGetsNoAdvice() throws {
        let sheet = Scenes.corners((-0.05, 0.10), (0.80, 0.10), (0.80, 0.90), (-0.05, 0.90))
        let (found, said) = try advice(.document, Scenes.scene(width: 1200, height: 1600, ground: 0.2, [(sheet, 0.95)]))
        #expect(found == nil)
        #expect(said == nil)
    }
}

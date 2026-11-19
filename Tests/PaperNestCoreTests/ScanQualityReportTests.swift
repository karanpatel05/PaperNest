import CoreGraphics
import Foundation
import Testing
@testable import PaperNestCore

/// The verdict drawn from a captured page's measurements: which issues, in
/// which order, and when a measurement is not trusted.
@Suite struct ScanQualityReportTests {
    private let whole = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]

    @Test func aGoodPageHasNothingToSay() {
        #expect(ScanQualityReport(sharpness: 0.5, paperBrightness: 0.9, stretch: 1.1).issues.isEmpty)
    }

    @Test func eachMeasureHasItsIssue() {
        #expect(ScanQualityReport(sharpness: 0.05, paperBrightness: 0.9, stretch: 1).issues == [.blurry])
        #expect(ScanQualityReport(sharpness: 0.5, paperBrightness: 0.1, stretch: 1).issues == [.tooDark])
        #expect(ScanQualityReport(sharpness: 0.5, paperBrightness: 0.9, stretch: 1.8).issues == [.steepAngle])
    }

    /// A dark capture is grainy and grain reads as detail, so its focus is
    /// not judged; and the darkness comes first, since refocusing in the dark
    /// would not help.
    @Test func aDarkPageIsNotAlsoCalledBlurry() {
        #expect(ScanQualityReport(sharpness: 0.05, paperBrightness: 0.1, stretch: 1.8).issues == [.tooDark, .steepAngle])
    }

    /// A page with too little on it to judge is not blurry, and one with no
    /// corners is not at an angle.
    @Test func whatWasNotMeasuredSaysNothing() {
        #expect(ScanQualityReport(sharpness: nil, paperBrightness: 0.9, stretch: nil).issues.isEmpty)
    }

    /// A photo is kept as taken, so nothing is said about it; a card may be
    /// dark itself, so only its darkness goes unsaid.
    @Test func whatIsSaidDependsOnWhatWasPhotographed() {
        let everything = ScanQualityReport(sharpness: 0.05, paperBrightness: 0.1, stretch: 1.8)
        #expect(everything.issues(in: .document) == [.tooDark, .steepAngle])
        #expect(everything.issues(in: .whiteboard) == [.tooDark, .steepAngle])
        #expect(everything.issues(in: .card) == [.steepAngle])
        #expect(everything.issues(in: .photo).isEmpty)
        let blurred = ScanQualityReport(sharpness: 0.05, paperBrightness: 0.9, stretch: 1)
        #expect(blurred.issues(in: .card) == [.blurry])
        #expect(blurred.issues(in: .photo).isEmpty)
    }

    @Test func aPageSquareOnIsNotStretched() throws {
        let stretch = try #require(ScanQualityReport.stretch(of: whole, photoSize: CGSize(width: 3000, height: 4000)))
        #expect(abs(stretch - 1) < 1e-9)
    }

    /// The far side about three fifths of the near one: two thirds is already the limit.
    @Test func aPageFromASteepAngleIsStretched() throws {
        let corners = [CGPoint(x: 0.3, y: 0.2), CGPoint(x: 0.7, y: 0.2), CGPoint(x: 0.85, y: 0.8), CGPoint(x: 0.2, y: 0.8)]
        let stretch = try #require(ScanQualityReport.stretch(of: corners, photoSize: CGSize(width: 3000, height: 4000)))
        #expect(abs(stretch - 0.65 / 0.4) < 1e-9)
        #expect(ScanQualityReport(sharpness: 0.5, paperBrightness: 0.9, stretch: stretch).issues == [.steepAngle])
    }

    /// Shares across and down are different lengths in a photo taller than
    /// it is wide, so the sides are measured in the photo's pixels.
    @Test func lengthsAreMeasuredInThePhotoNotInShares() throws {
        let corners = [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.1), CGPoint(x: 0.6, y: 0.6), CGPoint(x: 0.1, y: 0.4)]
        let stretch = try #require(ScanQualityReport.stretch(of: corners, photoSize: CGSize(width: 3000, height: 4000)))
        // The right side runs 900 across and 2000 down; the left 1200 down.
        #expect(abs(stretch - hypot(900, 2000) / 1200) < 1e-9)
        // In shares the same sides would give hypot(0.3, 0.5) / 0.3, about 1.94.
        #expect(abs(stretch - hypot(0.3, 0.5) / 0.3) > 0.1)
    }

    @Test func cornersThatAreNotAnOutlineGiveNoStretch() {
        #expect(ScanQualityReport.stretch(of: Array(whole.prefix(3)), photoSize: CGSize(width: 10, height: 10)) == nil)
        #expect(ScanQualityReport.stretch(of: whole, photoSize: .zero) == nil)
        let collapsed = [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        #expect(ScanQualityReport.stretch(of: collapsed, photoSize: CGSize(width: 10, height: 10)) == nil)
    }
}

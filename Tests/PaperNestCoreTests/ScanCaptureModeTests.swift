import CoreGraphics
import Testing
@testable import PaperNestCore

@Suite struct ScanCaptureModeTests {
    /// A quad with straight sides, given as its edges in shares of the picture.
    private func box(x: ClosedRange<Double>, y: ClosedRange<Double>, confidence: Double = 0.9) -> ScanQuad {
        ScanQuad(topLeft: CGPoint(x: x.lowerBound, y: y.lowerBound), topRight: CGPoint(x: x.upperBound, y: y.lowerBound),
                 bottomRight: CGPoint(x: x.upperBound, y: y.upperBound), bottomLeft: CGPoint(x: x.lowerBound, y: y.upperBound),
                 confidence: confidence)
    }

    // MARK: What a quad measures

    @Test func aQuadsAreaIsItsShareOfThePicture() {
        #expect(abs(box(x: 0.1...0.9, y: 0.25...0.75).area - 0.4) < 0.0001)
        // Leaning: a parallelogram a quarter of the picture wide and half as tall.
        let leaning = ScanQuad(topLeft: CGPoint(x: 0.2, y: 0.2), topRight: CGPoint(x: 0.45, y: 0.2),
                               bottomRight: CGPoint(x: 0.55, y: 0.7), bottomLeft: CGPoint(x: 0.3, y: 0.7), confidence: 1)
        #expect(abs(leaning.area - 0.125) < 0.0001)
    }

    /// Shares of the picture are not proportions of the thing: half the width
    /// of a wide picture is longer than half its height.
    @Test func aQuadsProportionsAllowForThePicturesOwn() {
        let quad = box(x: 0.1...0.9, y: 0.25...0.75)
        // In a 4:3 picture: 0.8 * 4 wide by 0.5 * 3 tall is 3.2 by 1.5.
        #expect(abs(quad.aspectRatio(imageAspect: 4.0 / 3) - 1.5 / 3.2) < 0.0001)
        // The same shares of a 3:4 picture: 2.4 wide by 2 tall.
        #expect(abs(quad.aspectRatio(imageAspect: 3.0 / 4) - 2.0 / 2.4) < 0.0001)
    }

    @Test func cornersComeInTheOrderTheCropUses() {
        let quad = box(x: 0.1...0.9, y: 0.2...0.8)
        #expect(quad.corners == [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.9, y: 0.2), CGPoint(x: 0.9, y: 0.8), CGPoint(x: 0.1, y: 0.8)])
    }

    // MARK: Choosing among what was found

    @Test func aBoardIsTheLargestThingInView() throws {
        let board = box(x: 0.05...0.95, y: 0.2...0.8, confidence: 0.7)
        let sheetPinnedToIt = box(x: 0.4...0.6, y: 0.3...0.6, confidence: 0.99)
        let detection = try #require(ScanCaptureMode.whiteboard.detection)
        #expect(detection.best(of: [sheetPinnedToIt, board], imageAspect: 4.0 / 3) == board)
    }

    @Test func aCardIsTheThingShapedLikeACard() throws {
        // A bank card is 85.6 by 54 mm: its short side is 0.63 of its long side.
        // In a 3:4 picture, 0.6 of the width by 0.2835 of the height is 1.8 by 1.134.
        let card = box(x: 0.2...0.8, y: 0.5...0.7835, confidence: 0.75)
        // A sheet of A4 lying beside it: 2.1 by 2.97, short side 0.707 of long.
        let sheet = box(x: 0.1...0.8, y: 0.0...0.7425, confidence: 0.95)
        let detection = try #require(ScanCaptureMode.card.detection)
        #expect(detection.best(of: [sheet, card], imageAspect: 3.0 / 4) == card)
    }

    @Test func aDocumentIsWhatTheDetectorIsSurestOf() throws {
        let sure = box(x: 0.3...0.7, y: 0.3...0.7, confidence: 0.95)
        let larger = box(x: 0.05...0.95, y: 0.05...0.95, confidence: 0.8)
        let detection = try #require(ScanCaptureMode.document.detection)
        #expect(detection.best(of: [larger, sure], imageAspect: 3.0 / 4) == sure)
    }

    /// A long receipt is nothing like a card. With only that in view, Card
    /// mode finds nothing rather than cropping to the wrong thing.
    @Test func aShapeOutsideTheModesRangeIsNotChosen() throws {
        // 0.2 of the width by 0.9 of the height of a 3:4 picture: 0.6 by 3.6.
        let receipt = box(x: 0.4...0.6, y: 0.05...0.95)
        let detection = try #require(ScanCaptureMode.card.detection)
        #expect(detection.best(of: [receipt], imageAspect: 3.0 / 4) == nil)
        #expect(detection.best(of: [], imageAspect: 3.0 / 4) == nil)
    }

    // MARK: What each mode does

    @Test func onlyAPhotoKeepsTheWholeFrame() {
        #expect(ScanCaptureMode.photo.detection == nil)
        #expect(!ScanCaptureMode.photo.findsEdges)
        for mode in [ScanCaptureMode.document, .whiteboard, .card, .book] {
            #expect(mode.findsEdges, "\(mode)")
        }
    }

    @Test func onlyACardHasTwoSides() {
        #expect(ScanCaptureMode.allCases.filter(\.pairsSides) == [.card])
    }

    /// The default filter is for paper. A photo is kept as it was taken, and
    /// a board has a look of its own that the default does not replace.
    @Test func aNewCaptureStartsWithItsModesLook() {
        #expect(ScanCaptureMode.document.startingAppearance(defaultPreset: .blackAndWhite) == ScanAppearance(preset: .blackAndWhite))
        #expect(ScanCaptureMode.card.startingAppearance(defaultPreset: .enhanced) == ScanAppearance(preset: .enhanced))
        #expect(ScanCaptureMode.book.startingAppearance(defaultPreset: .grayscale) == ScanAppearance(preset: .grayscale))
        #expect(ScanCaptureMode.photo.startingAppearance(defaultPreset: .blackAndWhite) == .original)
        let board = ScanCaptureMode.whiteboard.startingAppearance(defaultPreset: .grayscale)
        #expect(board.preset == .highContrast)
        #expect(board.cleanup.removeShadows > 0.5 && board.cleanup.whitenBackground > 0, "\(board.cleanup)")
        #expect(board == ScanCaptureMode.whiteboard.startingAppearance(defaultPreset: .original))
    }
}

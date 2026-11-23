import CoreGraphics
import Foundation
import Testing
@testable import PaperNestCore

@Suite struct SelectionEditsTests {
    private let page = PageID(rawValue: "page")

    private func ink(_ points: [(Double, Double)], width: Double = 2, z: String = "a") -> PageObject {
        PageObject(pageID: page, zKey: z, payload: .ink(InkStroke(tool: .pen, color: .black, width: width,
            points: points.enumerated().map { index, point in
                InkPoint(x: point.0, y: point.1, widthScale: 0.5 + Double(index) * 0.25, time: Double(index) * 0.1)
            })), modifiedAt: Date(timeIntervalSince1970: 0))
    }

    private func text(_ frame: CGRect, size: Double = 12, z: String = "b") -> PageObject {
        PageObject(pageID: page, zKey: z, payload: .text(TextBox(frame: frame, text: "Note", fontSize: size)),
                   modifiedAt: Date(timeIntervalSince1970: 0))
    }

    private func image(_ frame: CGRect, z: String = "c") -> PageObject {
        PageObject(pageID: page, zKey: z, payload: .image(PlacedImage(assetID: AssetID(sha256: "abc"), frame: frame)),
                   modifiedAt: Date(timeIntervalSince1970: 0))
    }

    private func points(_ object: PageObject) -> [CGPoint] {
        guard case .ink(let stroke) = object.payload else { return [] }
        return stroke.points.map { CGPoint(x: $0.x, y: $0.y) }
    }

    private func close(_ a: CGPoint, _ b: CGPoint, _ tolerance: Double = 1e-6) -> Bool {
        abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance
    }

    private func close(_ a: CGRect, _ b: CGRect, _ tolerance: Double = 1e-6) -> Bool {
        close(a.origin, b.origin, tolerance) && abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
    }

    // MARK: Scaling

    @Test func scalingGrowsEveryKindTogetherAboutTheAnchor() throws {
        let geometry = PageGeometry(sourceSize: CGSize(width: 600, height: 800))
        let objects = [ink([(100, 100), (140, 120)]), text(CGRect(x: 100, y: 150, width: 80, height: 30)),
                       image(CGRect(x: 200, y: 100, width: 40, height: 20))]
        let scaled = try SelectionEdits.scaled(objects, by: 2, about: CGPoint(x: 100, y: 100), in: geometry)
        #expect(scaled.map(\.id) == objects.map(\.id))
        #expect(scaled.map(\.zKey) == objects.map(\.zKey))
        #expect(points(scaled[0]) == [CGPoint(x: 100, y: 100), CGPoint(x: 180, y: 140)])
        guard case .ink(let stroke) = scaled[0].payload, case .ink(let original) = objects[0].payload,
              case .text(let box) = scaled[1].payload, case .image(let picture) = scaled[2].payload else {
            Issue.record("Every kind must survive scaling"); return
        }
        // The line grows with the writing; pressure and timing stay as recorded.
        #expect(stroke.width == 4)
        #expect(stroke.points.map(\.widthScale) == original.points.map(\.widthScale))
        #expect(stroke.points.map(\.time) == original.points.map(\.time))
        // Type grows with its box, or the words would no longer fit it.
        #expect(box.frame == CGRect(x: 100, y: 200, width: 160, height: 60))
        #expect(box.fontSize == 24)
        #expect(picture.frame == CGRect(x: 300, y: 100, width: 80, height: 40))
    }

    @Test(arguments: QuarterTurns.allCases) func scalingOnATurnedPageGrowsTowardsWhatTheReaderSees(_ rotation: QuarterTurns) throws {
        let geometry = PageGeometry(sourceSize: CGSize(width: 600, height: 800),
                                    crop: NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8), rotation: rotation)
        let stroke = ink([(200, 300), (260, 340)])
        let before = SelectionEdits.pageBounds(of: [stroke], in: geometry)!
        let scaled = try SelectionEdits.scaled([stroke], by: 1.5, about: before.origin, in: geometry)
        let after = SelectionEdits.pageBounds(of: scaled, in: geometry)!
        // The corner the reader held stays put, whichever way the page is turned.
        #expect(close(after.origin, before.origin, 1e-4))
        #expect(abs(after.width - before.width * 1.5) < 1e-4)
        #expect(abs(after.height - before.height * 1.5) < 1e-4)
    }

    @Test func scalingStopsAtThePageEdgeAndAtTheSmallestSize() throws {
        let geometry = PageGeometry(sourceSize: CGSize(width: 600, height: 800))
        let stroke = ink([(400, 400), (500, 450)], width: 0.5)
        let bounds = SelectionEdits.pageBounds(of: [stroke], in: geometry)!
        let grown = try SelectionEdits.scaled([stroke], by: 10, about: bounds.origin, in: geometry)
        let grownBounds = SelectionEdits.pageBounds(of: grown, in: geometry)!
        #expect(grownBounds.maxX <= 600 + 1e-6)
        #expect(abs(grownBounds.maxX - 600) < 1e-6)
        let shrunk = try SelectionEdits.scaled([stroke], by: 0.0001, about: bounds.origin, in: geometry)
        let shrunkBounds = SelectionEdits.pageBounds(of: shrunk, in: geometry)!
        #expect(max(shrunkBounds.width, shrunkBounds.height) >= SelectionEdits.minimumSide - 1e-6)
    }

    @Test func clampedScaleNeverPushesASelectionAlreadyPastTheEdge() {
        let page = CGRect(x: 0, y: 0, width: 600, height: 800)
        let hanging = CGRect(x: 550, y: 100, width: 100, height: 50)
        #expect(SelectionEdits.clampedScale(2, bounds: hanging, anchor: hanging.origin, page: page) == 1)
        #expect(SelectionEdits.clampedScale(0.5, bounds: hanging, anchor: hanging.origin, page: page) == 0.5)
    }

    @Test func scalingRefusesNonsense() {
        let geometry = PageGeometry(sourceSize: CGSize(width: 600, height: 800))
        let objects = [ink([(100, 100), (140, 120)])]
        for factor in [0, -1, Double.nan, .infinity] {
            #expect(throws: SelectionEdits.Failure.invalid) {
                try SelectionEdits.scaled(objects, by: factor, about: .zero, in: geometry)
            }
        }
        let comment = PageObject(pageID: page, zKey: "z", payload: .comment("Private"), modifiedAt: Date())
        #expect(throws: SelectionEdits.Failure.invalid) {
            try SelectionEdits.scaled(objects + [comment], by: 2, about: .zero, in: geometry)
        }
    }

    // MARK: Turning

    @Test func turningInkKeepsItsShapeAndTurnsAboutItsCentre() throws {
        let geometry = PageGeometry(sourceSize: CGSize(width: 600, height: 800))
        let stroke = ink([(100, 100), (200, 100)])
        let turned = try SelectionEdits.rotated([stroke], by: .pi / 2, in: geometry)
        let moved = points(turned[0])
        // A quarter turn clockwise on a y-down page: left-to-right becomes top-to-bottom.
        #expect(close(moved[0], CGPoint(x: 150, y: 50)))
        #expect(close(moved[1], CGPoint(x: 150, y: 150)))
        guard case .ink(let after) = turned[0].payload else { Issue.record("Still ink"); return }
        #expect(abs(after.width - 2) < 1e-9)
    }

    @Test(arguments: QuarterTurns.allCases) func turningOnATurnedPageTurnsTheWayTheReaderTurned(_ rotation: QuarterTurns) throws {
        let geometry = PageGeometry(sourceSize: CGSize(width: 600, height: 800), rotation: rotation)
        let stroke = ink([(250, 300), (350, 300)])
        let before = points(stroke).map { $0.applying(geometry.sourceToPage) }
        let turned = try SelectionEdits.rotated([stroke], by: .pi / 2, in: geometry)
        let after = points(turned[0]).map { $0.applying(geometry.sourceToPage) }
        // As the reader sees it, the line's direction turned a quarter clockwise.
        let was = CGPoint(x: before[1].x - before[0].x, y: before[1].y - before[0].y)
        let now = CGPoint(x: after[1].x - after[0].x, y: after[1].y - after[0].y)
        #expect(close(now, CGPoint(x: -was.y, y: was.x), 1e-6))
    }

    @Test func turningPullsInkBackOntoThePage() throws {
        let geometry = PageGeometry(sourceSize: CGSize(width: 600, height: 800))
        // A long line hugging the top edge would turn halfway off the page.
        let stroke = ink([(100, 5), (500, 5)])
        let turned = try SelectionEdits.rotated([stroke], by: .pi / 2, in: geometry)
        let bounds = SelectionEdits.pageBounds(of: turned, in: geometry)!
        #expect(bounds.minY >= -1e-6 && bounds.maxY <= 800 + 1e-6)
    }

    @Test func textBoxesAndImagesCannotBeTurned() {
        let geometry = PageGeometry(sourceSize: CGSize(width: 600, height: 800))
        #expect(throws: SelectionEdits.Failure.cannotRotate) {
            try SelectionEdits.rotated([ink([(1, 1), (5, 5)]), text(CGRect(x: 10, y: 10, width: 50, height: 20))],
                                       by: 0.3, in: geometry)
        }
        #expect(throws: SelectionEdits.Failure.cannotRotate) {
            try SelectionEdits.rotated([image(CGRect(x: 10, y: 10, width: 50, height: 20))], by: .pi, in: geometry)
        }
    }

    @Test(arguments: QuarterTurns.allCases) func scalingATextBoxOnATurnedPageIsNotMistakenForTurning(_ rotation: QuarterTurns) throws {
        let geometry = PageGeometry(sourceSize: CGSize(width: 600, height: 800), rotation: rotation)
        let box = text(CGRect(x: 100, y: 100, width: 100, height: 40))
        let bounds = SelectionEdits.pageBounds(of: [box], in: geometry)!
        let scaled = try SelectionEdits.scaled([box], by: 1.5, about: bounds.origin, in: geometry)
        guard case .text(let after) = scaled[0].payload else { Issue.record("Still a text box"); return }
        #expect(abs(after.fontSize - 18) < 1e-9)
        #expect(abs(after.frame.width - 150) < 1e-6 && abs(after.frame.height - 60) < 1e-6)
    }

    // MARK: Copies

    @Test func copiesHaveNewIdsAndKeepTheirOrderAndContent() throws {
        let geometry = PageGeometry(sourceSize: CGSize(width: 600, height: 800))
        let target = PageID(rawValue: "other")
        let objects = [image(CGRect(x: 300, y: 300, width: 40, height: 20), z: "c"),
                       ink([(100, 100), (140, 120)], z: "a"), text(CGRect(x: 100, y: 150, width: 80, height: 30), z: "b")]
        let copies = try SelectionEdits.copies(of: objects, from: geometry, onto: geometry, pageID: target)
        #expect(copies.count == 3)
        #expect(Set(copies.map(\.id)).isDisjoint(with: objects.map(\.id)))
        #expect(Set(copies.map(\.id)).count == 3)
        #expect(copies.allSatisfy { $0.pageID == target })
        // Bottom to top, as the originals were painted.
        #expect(copies.map(\.payload.kind) == ["ink", "text", "image"])
        #expect(copies.map(\.zKey) == ["a", "b", "c"])
        #expect(copies[0].payload == objects[1].payload)
        #expect(copies[1].payload == objects[2].payload)
        #expect(copies[2].payload == objects[0].payload)
    }

    @Test func aShiftedCopyMovesByTheShiftAndStaysOnThePage() throws {
        let geometry = PageGeometry(sourceSize: CGSize(width: 600, height: 800))
        let stroke = ink([(100, 100), (140, 120)])
        let copy = try SelectionEdits.copies(of: [stroke], from: geometry, onto: geometry, pageID: page,
                                             shiftedBy: CGPoint(x: 20, y: 20))
        #expect(points(copy[0]) == [CGPoint(x: 120, y: 120), CGPoint(x: 160, y: 140)])
        let corner = ink([(560, 760), (595, 795)])
        let pulled = try SelectionEdits.copies(of: [corner], from: geometry, onto: geometry, pageID: page,
                                               shiftedBy: CGPoint(x: 20, y: 20))
        let bounds = SelectionEdits.pageBounds(of: pulled, in: geometry)!
        #expect(bounds.maxX <= 600 + 1e-6 && bounds.maxY <= 800 + 1e-6)
    }

    @Test func inkCopiedToADifferentlyTurnedPageStillReadsUpright() throws {
        let origin = PageGeometry(sourceSize: CGSize(width: 600, height: 800))
        let target = PageGeometry(sourceSize: CGSize(width: 800, height: 600), rotation: .clockwise90)
        // Left to right on the page it came from…
        let stroke = ink([(100, 100), (200, 100)])
        let copy = try SelectionEdits.copies(of: [stroke], from: origin, onto: target, pageID: page)
        let seen = points(copy[0]).map { $0.applying(target.sourceToPage) }
        // …and left to right as the reader sees the turned page, in the same place.
        #expect(close(seen[0], CGPoint(x: 100, y: 100), 1e-6))
        #expect(close(seen[1], CGPoint(x: 200, y: 100), 1e-6))
    }

    @Test func aTextBoxCopiedToATurnedPageKeepsItsOwnSize() throws {
        let origin = PageGeometry(sourceSize: CGSize(width: 600, height: 800))
        let target = PageGeometry(sourceSize: CGSize(width: 800, height: 600), rotation: .clockwise90)
        let box = text(CGRect(x: 100, y: 100, width: 120, height: 40))
        let copy = try SelectionEdits.copies(of: [box], from: origin, onto: target, pageID: page)
        guard case .text(let after) = copy[0].payload else { Issue.record("Still a text box"); return }
        #expect(after.frame.size == CGSize(width: 120, height: 40))
        #expect(after.fontSize == 12)
        // Its centre lands where the original's centre was, as the reader sees it.
        let centre = CGPoint(x: after.frame.midX, y: after.frame.midY).applying(target.sourceToPage)
        #expect(close(centre, CGPoint(x: 160, y: 120), 1e-6))
    }

    @Test func aCopyTooLargeForThePageIsMadeSmallerToFit() throws {
        let origin = PageGeometry(sourceSize: CGSize(width: 600, height: 800))
        let target = PageGeometry(sourceSize: CGSize(width: 200, height: 300))
        let objects = [ink([(20, 20), (580, 780)]), text(CGRect(x: 100, y: 100, width: 400, height: 100), size: 20)]
        let copies = try SelectionEdits.copies(of: objects, from: origin, onto: target, pageID: page)
        let bounds = SelectionEdits.pageBounds(of: copies, in: target)!
        #expect(bounds.minX >= -1e-6 && bounds.minY >= -1e-6)
        #expect(bounds.maxX <= 200 + 1e-6 && bounds.maxY <= 300 + 1e-6)
        guard case .text(let box) = copies[1].payload else { Issue.record("Still a text box"); return }
        #expect(box.fontSize < 20)
    }

    @Test func copiesRefuseWhatIsNotPaintedOnThePage() {
        let geometry = PageGeometry(sourceSize: CGSize(width: 600, height: 800))
        let comment = PageObject(pageID: page, zKey: "z", payload: .comment("Private"), modifiedAt: Date())
        #expect(throws: SelectionEdits.Failure.invalid) {
            try SelectionEdits.copies(of: [comment], from: geometry, onto: geometry, pageID: page)
        }
        #expect(throws: SelectionEdits.Failure.invalid) {
            try SelectionEdits.copies(of: [], from: geometry, onto: geometry, pageID: page)
        }
    }
}

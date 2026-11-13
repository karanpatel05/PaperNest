import CoreGraphics
import Foundation
import Testing
@testable import PaperNestCore

/// The six pens are only worth having if they draw six different lines. These
/// tests are about the lines, not the labels.
@Suite struct PenDynamicsTests {
    /// A stroke that changes direction and speed: down-right slowly, then
    /// up-right quickly. Enough for every pen's rule to have something to act on.
    private func hook(pressure: Double? = nil) -> [PenSample] {
        var samples: [PenSample] = []
        var time = 0.0
        for index in 0...30 {
            samples.append(PenSample(x: Double(index) * 2, y: Double(index) * 2, time: time, pressure: pressure))
            time += 0.03
        }
        for index in 1...30 {
            samples.append(PenSample(x: 60 + Double(index) * 6, y: 60 - Double(index) * 6, time: time, pressure: pressure))
            time += 0.004
        }
        return samples
    }

    private func scales(_ preset: PenPreset, _ samples: [PenSample], usesPressure: Bool = true) -> [Double] {
        PenDynamics.points(from: samples, preset: preset, usesPressure: usesPressure).map(\.widthScale)
    }

    @Test(arguments: PenPreset.allCases) func everySampleBecomesOnePointInTheSamePlace(_ preset: PenPreset) {
        let samples = hook()
        let points = PenDynamics.points(from: samples, preset: preset)
        #expect(points.count == samples.count)
        for (point, sample) in zip(points, samples) {
            #expect(point.x == sample.x && point.y == sample.y && point.time == sample.time)
            #expect(point.widthScale > 0 && point.widthScale <= 1, "\(preset) \(point.widthScale)")
        }
    }

    @Test func aBallpointAndAMarkerAreOneWidthAllTheWayAlong() {
        for preset in [PenPreset.ballpoint, .marker] {
            #expect(scales(preset, hook()).allSatisfy { $0 == 1 }, "\(preset)")
            // Pressing harder changes nothing either.
            #expect(scales(preset, hook(pressure: 0.2)).allSatisfy { $0 == 1 }, "\(preset)")
            #expect(!preset.respondsToPressure)
        }
    }

    /// The claim the pen panel makes. Two presets that produced the same line
    /// from the same hand would be one preset with two names.
    @Test func noTwoPensDrawTheSameLine() {
        let samples = hook()
        var seen: [(PenPreset, String)] = []
        for preset in PenPreset.allCases {
            let profile = scales(preset, samples).map { String(format: "%.3f", $0) }.joined(separator: ",")
            let signature = "\(profile)|\(preset.defaultWidth)|\(preset.defaultOpacity)"
            for (other, otherSignature) in seen {
                #expect(signature != otherSignature, "\(preset) draws exactly what \(other) draws")
            }
            seen.append((preset, signature))
        }
        // And the four that shape their line really do shape it differently,
        // not merely start from a different width.
        let shaped = [PenPreset.fountain, .gel, .pencil, .brush].map { scales($0, samples) }
        for a in shaped.indices {
            for b in shaped.indices where a < b {
                let gap = zip(shaped[a], shaped[b]).map { abs($0 - $1) }.max() ?? 0
                #expect(gap > 0.05, "profiles \(a) and \(b) differ by only \(gap)")
            }
        }
    }

    @Test func aFountainPenIsThinAlongItsNibAndFullAcrossIt() {
        func line(angle: Double) -> [PenSample] {
            (0...40).map { PenSample(x: cos(angle) * Double($0) * 3, y: sin(angle) * Double($0) * 3) }
        }
        // The nib sits at -45°: a stroke that way runs along its edge.
        let along = scales(.fountain, line(angle: -.pi / 4))[20]
        let across = scales(.fountain, line(angle: .pi / 4))[20]
        #expect(along < 0.4)
        #expect(across > 0.9)
    }

    @Test func aBrushThinsWithSpeedAndTapersAtBothEnds() {
        func line(seconds: Double) -> [PenSample] {
            (0...40).map { PenSample(x: Double($0) * 5, y: 0, time: seconds * Double($0) / 40) }
        }
        let slow = scales(.brush, line(seconds: 4))
        let fast = scales(.brush, line(seconds: 0.2))
        #expect(slow[20] > 0.9)
        #expect(fast[20] < 0.5)
        #expect(slow[0] < slow[20] && slow[40] < slow[20], "a brush lands and lifts thin")
    }

    @Test func pressureWidensThePensThatListenToIt() {
        for preset in [PenPreset.gel, .fountain, .pencil, .brush] {
            let light = scales(preset, hook(pressure: 0.1))[15]
            let heavy = scales(preset, hook(pressure: 1))[15]
            #expect(heavy > light, "\(preset)")
            // With pressure switched off the reading is ignored entirely.
            #expect(scales(preset, hook(pressure: 0.1), usesPressure: false)
                    == scales(preset, hook(pressure: 1), usesPressure: false), "\(preset)")
        }
    }

    @Test func theSameHandAlwaysDrawsTheSameLine() {
        for preset in PenPreset.allCases {
            #expect(scales(preset, hook()) == scales(preset, hook()), "\(preset)")
        }
    }

    @Test func aStrokeWithNoTimestampsIsNotTreatedAsStandingStill() {
        // Generated and imported strokes carry no times. They must not come
        // out as if the pen had dwelt on every point.
        let untimed = (0...20).map { PenSample(x: Double($0) * 4, y: 0) }
        #expect(scales(.gel, untimed).allSatisfy { abs($0 - 1) < 0.0001 })
        #expect(PenDynamics.points(from: [], preset: .gel).isEmpty)
    }

    @Test func defaultsStayInsideEachPensOwnRange() {
        for preset in PenPreset.allCases {
            #expect(preset.widthRange.contains(preset.defaultWidth), "\(preset)")
            #expect((0.1...1).contains(preset.defaultOpacity), "\(preset)")
        }
    }
}

@Suite struct StrokeSmoothingTests {
    private func zigzag() -> [PenSample] {
        (0...40).map { PenSample(x: Double($0) * 3, y: $0.isMultiple(of: 2) ? 0 : 4, time: Double($0) * 0.01) }
    }

    @Test func zeroLeavesTheStrokeAlone() {
        #expect(StrokeSmoothing.smooth(zigzag(), amount: 0) == zigzag())
    }

    @Test func smoothingFlattensWobbleButKeepsBothEnds() {
        let before = zigzag(), after = StrokeSmoothing.smooth(before, amount: 1)
        #expect(after.count == before.count)
        #expect(after.first == before.first && after.last == before.last)
        // Measured away from the ends, which are pinned on purpose: a stroke
        // must still start and stop where the hand did.
        func wobble(_ samples: [PenSample]) -> Double {
            let middle = Array(samples[6...34])
            return zip(middle, middle.dropFirst()).map { abs($1.y - $0.y) }.max() ?? 0
        }
        #expect(wobble(after) < wobble(before) / 4)
        // Timing and pressure are not positions and are not averaged.
        #expect(after.map(\.time) == before.map(\.time))
    }

    @Test func aTwoPointStrokeHasNothingToSmooth() {
        let pair = [PenSample(x: 0, y: 0), PenSample(x: 10, y: 10)]
        #expect(StrokeSmoothing.smooth(pair, amount: 1) == pair)
    }
}

@Suite struct StrokeSnappingTests {
    private func circle(radius: Double = 50, wobble: Double = 0) -> [CGPoint] {
        (0...60).map { index in
            let angle = Double(index) * 2 * .pi / 60
            let r = radius + (index.isMultiple(of: 2) ? wobble : -wobble)
            return CGPoint(x: 100 + cos(angle) * r, y: 100 + sin(angle) * r)
        }
    }

    private func polyline(_ corners: [CGPoint], steps: Int = 12) -> [CGPoint] {
        var points: [CGPoint] = []
        for (a, b) in zip(corners, corners.dropFirst()) {
            for step in 0..<steps {
                let t = Double(step) / Double(steps)
                points.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        points.append(corners[corners.count - 1])
        return points
    }

    @Test func aNearlyStraightStrokeIsALineBetweenItsEnds() {
        let wobbly = (0...30).map { CGPoint(x: Double($0) * 5, y: $0.isMultiple(of: 2) ? 1.5 : -1.5) }
        #expect(StrokeSnapping.recognize(wobbly) == .line(wobbly[0], wobbly[30]))
    }

    @Test func aRoughCircleIsAnEllipseInItsOwnBounds() throws {
        guard case .ellipse(let rect) = StrokeSnapping.recognize(circle(wobble: 2)) else {
            Issue.record("a wobbly circle was not recognised as an ellipse"); return
        }
        #expect(abs(rect.midX - 100) < 3 && abs(rect.midY - 100) < 3)
        #expect(abs(rect.width - 100) < 8 && abs(rect.height - 100) < 8)
    }

    @Test func aBoxIsARectangle() {
        let box = polyline([CGPoint(x: 0, y: 0), CGPoint(x: 120, y: 2), CGPoint(x: 118, y: 80),
                            CGPoint(x: 1, y: 79), CGPoint(x: 0, y: 0)])
        guard case .rectangle(let rect) = StrokeSnapping.recognize(box) else {
            Issue.record("a hand-drawn box was not recognised as a rectangle"); return
        }
        #expect(abs(rect.width - 120) < 3 && abs(rect.height - 80) < 3)
    }

    /// Where the stroke starts must not matter. Starting half-way along a side
    /// leaves a vertex that is not a corner, and that used to make four.
    @Test func aTriangleIsATriangleWhereverItWasStarted() {
        let a = CGPoint(x: 50, y: 0), b = CGPoint(x: 100, y: 90), c = CGPoint(x: 0, y: 90)
        let fromCorner = polyline([a, b, c, a])
        let midSide = CGPoint(x: 75, y: 45)
        let fromSide = polyline([midSide, b, c, a, midSide])
        for stroke in [fromCorner, fromSide] {
            guard case .triangle(let p, let q, let r) = StrokeSnapping.recognize(stroke) else {
                Issue.record("triangle not recognised"); continue
            }
            for corner in [a, b, c] {
                #expect([p, q, r].contains { hypot($0.x - corner.x, $0.y - corner.y) < 6 })
            }
        }
    }

    /// The cost of a wrong guess is someone's handwriting, so anything that is
    /// not clearly a shape has to be left exactly as it was drawn.
    @Test func handwritingIsLeftAlone() {
        let wave = (0...60).map { CGPoint(x: Double($0) * 3, y: sin(Double($0) / 5) * 20) }
        #expect(StrokeSnapping.recognize(wave) == nil)
        let scribble = (0...80).map { index -> CGPoint in
            let angle = Double(index) * 0.9
            return CGPoint(x: 50 + cos(angle) * Double(index % 13) * 4, y: 50 + sin(angle * 1.7) * Double(index % 7) * 6)
        }
        #expect(StrokeSnapping.recognize(scribble) == nil)
        // A dot and a tick are too small to be asking for anything.
        #expect(StrokeSnapping.recognize([CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 0)]) == nil)
        // An open arc — most of a letter "c" — is not a closed shape.
        #expect(StrokeSnapping.recognize(Array(circle().prefix(40))) == nil)
    }

    @Test func outlinesCloseAndKeepTheirCorners() {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 60)
        let box = SnappedShape.rectangle(rect).outline
        #expect(box.first == box.last)
        #expect(box.filter { $0 == CGPoint(x: rect.maxX, y: rect.minY) }.count == 3, "corners are repeated to stay sharp")
        let oval = SnappedShape.ellipse(rect).outline
        #expect(oval.first == oval.last)
        #expect(oval.allSatisfy { rect.insetBy(dx: -0.001, dy: -0.001).contains($0) })
        #expect(SnappedShape.line(.zero, CGPoint(x: 5, y: 5)).outline.count == 2)
    }

    @Test func theRestIsMeasuredForBothKindsOfInput() {
        // A finger or a mouse held still sends nothing: the wait is the gap
        // between the last sample and the lift.
        let moving = (0...20).map { PenSample(x: Double($0) * 10, y: 0, time: Double($0) * 0.01) }
        #expect(StrokeSnapping.dwell(moving, endTime: 0.21, radius: 5) < 0.05)
        #expect(StrokeSnapping.dwell(moving, endTime: 0.9, radius: 5) > StrokeSnapping.holdDuration)
        // An Apple Pencil held still keeps reporting tiny movements: the wait
        // is inside the samples.
        var resting = moving
        for index in 1...60 {
            resting.append(PenSample(x: 200 + Double(index % 2), y: Double(index % 3) * 0.5, time: 0.2 + Double(index) * 0.01))
        }
        #expect(StrokeSnapping.dwell(resting, endTime: 0.8, radius: 5) > StrokeSnapping.holdDuration)
        #expect(StrokeSnapping.dwell([], endTime: 3, radius: 5) == 0)
    }
}

@Suite struct InkStrokeCapTests {
    @Test func strokesSavedBeforeCapsExistedStillDecodeAsRound() throws {
        let old = #"{"tool":"highlighter","color":{"red":1,"green":0.8,"blue":0,"alpha":1},"width":20,"points":[{"x":1,"y":2,"widthScale":1,"time":0}]}"#
        let stroke = try JSONDecoder().decode(InkStroke.self, from: Data(old.utf8))
        #expect(stroke.cap == nil)
        #expect(stroke.width == 20 && stroke.points.count == 1)
    }

    /// A stroke with no cap must be stored exactly as it always was: no new
    /// key, so nothing that reads the stored form sees a difference.
    @Test func aRoundStrokeIsStoredWithoutACapKey() throws {
        let stroke = InkStroke(tool: .pen, color: .black, width: 2, points: [InkPoint(x: 0, y: 0)])
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(stroke)) as? [String: Any])
        #expect(json["cap"] == nil)
        #expect(Set(json.keys) == ["tool", "color", "width", "points"])
    }

    @Test func aFlatCapSurvivesARoundTrip() throws {
        let stroke = InkStroke(tool: .highlighter, color: .black, width: 20, points: [InkPoint(x: 0, y: 0)], cap: .flat)
        #expect(try JSONDecoder().decode(InkStroke.self, from: JSONEncoder().encode(stroke)) == stroke)
    }
}

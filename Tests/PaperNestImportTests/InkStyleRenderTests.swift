import CoreGraphics
import Testing
import PaperNestCore
@testable import PaperNestRender

/// How the two things added for the notes editor's tools reach the page: a
/// flat-ended highlighter, and a see-through pen whose width varies.
@Suite struct InkStyleRenderTests {
    /// Draws a stroke into a white bitmap at `scale` pixels per point and
    /// returns its red channel, row-major, top row first.
    private func red(_ stroke: InkStroke, width: Int, height: Int, scale: Double) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            context.setShouldAntialias(false)
            context.translateBy(x: 0, y: Double(height))
            context.scaleBy(x: scale, y: -scale)
            PageRenderer.drawInk(stroke, in: context)
        }
        return stride(from: 0, to: pixels.count, by: 4).map { pixels[$0] }
    }

    /// A flat tip stops where the stroke stops. A round one carries on for
    /// half its width, which on a 20-point highlighter is most of a letter.
    @Test func aFlatHighlighterDoesNotRunPastItsEnds() throws {
        let width = 200, height = 60
        func painted(_ cap: InkStroke.Cap?) throws -> ClosedRange<Int> {
            let stroke = InkStroke(tool: .highlighter, color: RGBAColor(red: 0, green: 0, blue: 1), width: 20,
                                   points: [InkPoint(x: 50, y: 30), InkPoint(x: 150, y: 30)], cap: cap)
            let channel = try red(stroke, width: width, height: height, scale: 1)
            let columns = (0..<width).filter { channel[30 * width + $0] < 250 }
            return try #require(columns.first)...(try #require(columns.last))
        }
        let flat = try painted(.flat), round = try painted(nil)
        #expect(abs(flat.lowerBound - 50) <= 1 && abs(flat.upperBound - 149) <= 1, "flat: \(flat)")
        #expect(round.lowerBound <= 41 && round.upperBound >= 158, "round: \(round)")
    }

    /// A faded pen of varying width is drawn in pieces. Each piece at its own
    /// alpha would overlap its neighbour at every join and show a darker bead
    /// there; the stroke has to be one even tone from end to end.
    @Test func aFadedPenOfVaryingWidthIsOneEvenTone() throws {
        let width = 240, height = 60
        let points = (0...20).map { InkPoint(x: 20 + Double($0) * 10, y: 30, widthScale: $0.isMultiple(of: 2) ? 1 : 0.6) }
        let stroke = InkStroke(tool: .pen, color: RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.5), width: 12, points: points)
        let channel = try red(stroke, width: width, height: height, scale: 1)
        // Along the centre line, well inside both ends: the ink is black at
        // half strength over white, so every pixel is mid-grey — never darker.
        let tones = Set((40...200).map { channel[30 * width + $0] })
        #expect(tones.count == 1, "the stroke is \(tones.sorted()) along its length")
        let tone = try #require(tones.first)
        #expect(abs(Int(tone) - 128) <= 3)
    }

    /// The rule that already held for every other pen must still hold: a full
    /// strength stroke of varying width keeps its widths.
    @Test func anOpaquePenStillFollowsItsWidths() throws {
        let width = 120, height = 60
        let points = [InkPoint(x: 20, y: 30, widthScale: 1), InkPoint(x: 60, y: 30, widthScale: 1),
                      InkPoint(x: 100, y: 30, widthScale: 0.25)]
        let stroke = InkStroke(tool: .pen, color: .black, width: 16, points: points)
        let channel = try red(stroke, width: width, height: height, scale: 1)
        func thickness(at column: Int) -> Int { (0..<height).filter { channel[$0 * width + column] < 128 }.count }
        #expect(thickness(at: 40) >= 15)
        #expect(thickness(at: 90) < thickness(at: 40))
    }
}

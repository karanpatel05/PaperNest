import CoreGraphics
import Testing
import PaperNestCore
@testable import PaperNestRender

@Suite struct TextMarkupRenderTests {
    @Test(arguments: [TextMarkupStyle.underline, .strikethrough], [0.1, 12.0])
    func renderedMarksKeepTheirExactWidth(_ style: TextMarkupStyle, _ height: Double) throws {
        let size = CGSize(width: 20, height: 16)
        let line = RecognizedLine(text: "Synthetic line",
                                  box: .exact(x: 0.2, y: 0.125, width: 0.6, height: height / 16), confidence: 1)
        let stroke = try style.stroke(for: line, in: size)
        // At 100 pixels per source point, even a 0.1-point mark must paint
        // ten rows. Rounding 1.2 to 1.25 also becomes a measurable overflow.
        let scale = 100.0, width = 2000, rows = 1600
        var pixels = [UInt8](repeating: 255, count: width * rows * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: width, height: rows,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            context.setShouldAntialias(false)
            context.translateBy(x: 0, y: Double(rows))
            context.scaleBy(x: scale, y: -scale)
            PageRenderer.drawInk(stroke, in: context)
        }
        let centerColumn = width / 2
        let paintedRows = (0..<rows).filter { pixels[($0 * width + centerColumn) * 4] < 128 }
        #expect(abs(Double(paintedRows.count) - stroke.width * scale) <= 1,
                "The \(stroke.width)-point mark must retain its visible thickness")
        let firstRow = try #require(paintedRows.first)
        let lastRow = try #require(paintedRows.last)
        let centerY = stroke.points[0].y * scale
        #expect(Double(firstRow) >= centerY - stroke.width * scale / 2 - 1)
        #expect(Double(lastRow + 1) <= centerY + stroke.width * scale / 2 + 1)
        let sourceBox = line.box.denormalized(in: size)
        #expect(Double(firstRow) >= sourceBox.minY * scale - 1)
        #expect(Double(lastRow + 1) <= sourceBox.maxY * scale + 1)
    }
}

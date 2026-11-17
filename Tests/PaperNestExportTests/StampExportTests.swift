import AppKit
import CoreGraphics
import Foundation
import PDFKit
import Testing
import PaperNestCore
import PaperNestRender
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestExport

/// A text stamp on the way out: part of the page, so every export draws it,
/// its words still real text and its border in its colour.
@Suite struct StampExportTests {
    @Test func aStampIsExportedAsRealTextInsideItsBorder() async throws {
        let fixture = try ExportFixture()
        let item = try await fixture.importer.importItem(
            .data(SyntheticDocuments.textPDF(pages: ["Invoice 1042"]), name: "Invoice"))
        let page = try await fixture.store.pages(of: item.id)[0]
        let design = StampDesign(text: "APPROVED", style: .outlined, color: StampPreset.approved.color)
        var stamp = design.textBox(dateLine: nil, fontSize: 28)
        let size = PageRenderer.stampSize(for: stamp)
        stamp.frame = CGRect(x: 300, y: 500, width: size.width, height: size.height)
        _ = try await fixture.store.placeText(stamp.text, on: page.id, frame: stamp.frame, fontSize: stamp.fontSize,
                                              color: stamp.color, alignment: .center, isBold: true, stamp: .outlined)

        let output = try await fixture.exporter.export(
            itemName: item.name, pages: try await fixture.store.pages(of: item.id),
            options: ExportOptions(format: .pdf, paperSize: .original))
        defer { output.removeTemporaryFiles() }

        let data = try Data(contentsOf: output.files[0])
        let text = try #require(PDFDocument(data: data)?.page(at: 0)?.string)
        #expect(text.contains("APPROVED"), "the stamp's word is not selectable text: \(text)")
        // The middle of the stamp's left border, on a 612 × 792 page drawn at 2×.
        let image = try #require(PixelProbe.renderPDFPage(data, index: 0, scale: 2))
        let border = PixelProbe.pixel(image, x: (stamp.frame.minX + stamp.stampLineWidth / 2) / 612,
                                      y: stamp.frame.midY / 792)
        #expect(Int(border.g) > Int(border.r) + 50 && Int(border.g) > Int(border.b) + 20,
                "no green border in the export: \(border)")
        // Just outside the frame, the paper.
        let outside = PixelProbe.pixel(image, x: (stamp.frame.minX - 6) / 612, y: stamp.frame.midY / 792)
        #expect(outside.r > 240 && outside.g > 240 && outside.b > 240)
    }
}

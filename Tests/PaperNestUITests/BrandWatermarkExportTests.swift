import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestExport
import PaperNestRender
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestUI

/// The PaperNest watermark from the export sheet's own options to the file
/// it writes: a free user's export carries the small mark even with the
/// switch off, Pro's does not, and the large branded preset draws the real
/// mark beside the name. Read back from the written PDF.
@Suite struct BrandWatermarkExportTests {
    private struct Fixture {
        let root: URL
        let exporter: Exporter
        let pages: [Page]
    }

    private func fixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestBrandMark-\(UUID())")
        let store = try LibraryStore(directory: root)
        let asset = try store.assets.store(SyntheticDocuments.textPDF(pages: ["Quarterly report"]), kind: .pdf,
                                           originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Report", pages: [
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: 0)),
        ], assets: [asset])
        let exports = root.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        return Fixture(root: root, exporter: Exporter(renderer: PageRenderer(store: store), temporaryRoot: exports),
                       pages: try await store.pages(of: item.id))
    }

    /// The first page of the exported PDF, drawn 2 pixels per point.
    private func exported(_ fixture: Fixture, _ options: ExportOptions) async throws -> CGImage {
        let output = try await fixture.exporter.export(itemName: "Report", pages: fixture.pages, options: options)
        defer { output.removeTemporaryFiles() }
        let data = try Data(contentsOf: output.files[0])
        return try #require(PixelProbe.renderPDFPage(data, index: 0, scale: 2))
    }

    /// Pixels of the brand's purple (clearly bluer and redder than green) in
    /// a rectangle given as shares of the picture, measured from the top-left.
    private func purple(_ image: CGImage, x: ClosedRange<Double>, y: ClosedRange<Double>) -> Int {
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var count = 0
        for py in Int(y.lowerBound * Double(height))..<Int(y.upperBound * Double(height)) {
            for px in Int(x.lowerBound * Double(width))..<Int(x.upperBound * Double(width)) {
                let i = (py * width + px) * 4
                let r = Int(buffer[i]), g = Int(buffer[i + 1]), b = Int(buffer[i + 2])
                if b > g + 30 && r > g + 10 && b > r { count += 1 }
            }
        }
        return count
    }

    /// Options exactly as the sheet makes them for an export.
    private func sheetOptions(switchOn: Bool, allowsRemoval: Bool, draft: WatermarkDraft = WatermarkDraft()) -> ExportOptions {
        ExportSheet.optionsToExport(ExportOptions(format: .pdf, paperSize: .original), watermark: draft,
                                    includesBrandMark: ExportSheet.brandMarkToExport(switchOn: switchOn,
                                                                                    allowsRemoval: allowsRemoval))
    }

    @Test func aFreeUsersExportCarriesTheMarkEvenWithTheSwitchOff() async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let free = try await exported(fixture, sheetOptions(switchOn: false, allowsRemoval: false))
        let pro = try await exported(fixture, sheetOptions(switchOn: false, allowsRemoval: true))

        let corner = (x: 0.0...0.45, y: 0.85...1.0)
        #expect(purple(free, x: corner.x, y: corner.y) > 150, "no PaperNest mark in a free user's bottom-left corner")
        #expect(purple(pro, x: corner.x, y: corner.y) == 0, "Pro with the switch off still marked")
    }

    /// The branded preset draws the real mark: purple in the middle of the
    /// page that a plain export lacks, the logo included.
    @Test func theBrandedPresetDrawsTheMarkAcrossThePage() async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var draft = WatermarkDraft()
        draft.choose(.paperNest)
        draft.opacity = 0.6
        let branded = try await exported(fixture, sheetOptions(switchOn: false, allowsRemoval: true, draft: draft))
        let plain = try await exported(fixture, sheetOptions(switchOn: false, allowsRemoval: true))

        let middle = (x: 0.15...0.85, y: 0.3...0.7)
        #expect(purple(branded, x: middle.x, y: middle.y) > 2_000, "the branded preset drew little or nothing")
        #expect(purple(plain, x: middle.x, y: middle.y) == 0)
        #expect(try #require(draft.watermark()).logo != nil, "the branded preset carries the mark")
    }
}

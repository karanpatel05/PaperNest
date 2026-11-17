import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestRender
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestExport

/// How large an export will be, worked out before it is made: exact for a
/// few pages, close for many, through the same writer, leaving nothing
/// behind and storing nothing.
@Suite struct ExportSizeEstimateTests {
    // MARK: - Arithmetic

    @Test func samplePagesAreSpreadEvenlyFirstAndLastIncluded() {
        #expect(ExportSizeModel.sampleIndices(count: 10, limit: 4) == [0, 3, 6, 9])
        #expect(ExportSizeModel.sampleIndices(count: 30, limit: 4) == [0, 10, 19, 29])
        #expect(ExportSizeModel.sampleIndices(count: 3, limit: 4) == [0, 1, 2])
        #expect(ExportSizeModel.sampleIndices(count: 1, limit: 4) == [0])
        #expect(ExportSizeModel.sampleIndices(count: 0, limit: 4).isEmpty)
    }

    /// A file of 1,000 bytes paid once and 100 per page: one page is 1,100,
    /// four are 1,400, so thirty are 4,000 — where scaling four pages up
    /// would say 10,500.
    @Test func theCostPaidOnceIsNotMultiplied() {
        #expect(ExportSizeModel.estimate(one: 1_100, sample: 1_400, sampleCount: 4, total: 30) == 4_000)
        #expect(ExportSizeModel.estimate(one: 500, sample: 400, sampleCount: 4, total: 30) == 500, "never below one page")
    }

    // MARK: - Through the writer

    private func scans(_ fixture: ExportFixture, count: Int) async throws -> [Page] {
        var staged: [AssetFileStore.StagedAsset] = []
        var pages: [LibraryStore.NewPage] = []
        for index in 0..<count {
            let image = SyntheticDocuments.textImage(lines: ["Ledger page \(index + 1)", "Opening balance \(index * 37)",
                                                             "Closing balance \(index * 41 + 9)"], type: .jpeg)
            let asset = try fixture.store.assets.store(image, kind: .jpeg, originalFilename: nil)
            staged.append(asset)
            pages.append(.init(sourceSize: CGSize(width: 600, height: 840), content: .image(asset.id)))
        }
        let item = try await fixture.store.createItem(kind: .document, name: "Ledger", pages: pages, assets: staged)
        return try await fixture.store.pages(of: item.id)
    }

    private func realSize(_ fixture: ExportFixture, _ pages: [Page], _ options: ExportOptions) async throws -> Int64 {
        let output = try await fixture.exporter.export(itemName: "Doc", pages: pages, options: options)
        defer { output.removeTemporaryFiles() }
        return output.totalByteCount
    }

    /// An exporter writing into a folder of its own, so other tests' exports
    /// running alongside are not counted as this one's leftovers.
    private func privateExporter(_ fixture: ExportFixture) throws -> Exporter {
        let root = fixture.url.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return Exporter(renderer: PageRenderer(store: fixture.store), temporaryRoot: root)
    }

    private func leftovers(_ exporter: Exporter) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: exporter.temporaryRoot.path)
    }

    /// A few pages are all exported: the size is the export's, said as exact.
    @Test func aFewPagesAreMeasuredExactly() async throws {
        let fixture = try ExportFixture()
        let (_, pages) = try await fixture.importPDF(["Quarterly report", "Second page of figures"])
        let options = ExportOptions(format: .pdf, paperSize: .original)

        let estimate = try await fixture.exporter.estimateSize(itemName: "Doc", pages: pages, options: options)
        let real = try await realSize(fixture, pages, options)

        #expect(estimate.isExact)
        // A PDF carries its own creation date and identifier; the length is what matters.
        #expect(abs(estimate.byteCount - real) <= 64, "estimate \(estimate.byteCount), real \(real)")
    }

    @Test func twentyScannedPagesAreEstimatedWithinFifteenPercent() async throws {
        let fixture = try ExportFixture()
        let pages = try await scans(fixture, count: 20)
        for options in [ExportOptions(format: .pdf, paperSize: .original),
                        ExportOptions(format: .jpeg, paperSize: .original)] {
            let estimate = try await fixture.exporter.estimateSize(itemName: "Doc", pages: pages, options: options)
            let real = try await realSize(fixture, pages, options)
            #expect(!estimate.isExact)
            let error = abs(Double(estimate.byteCount - real)) / Double(real)
            #expect(error < 0.15, "\(options.format): estimate \(estimate.byteCount), real \(real), off by \(Int(error * 100))%")
        }
    }

    /// A text PDF pays for its fonts once: the case scaling a few pages up gets badly wrong.
    @Test func thirtyTextPagesAreEstimatedWithinTwentyPercent() async throws {
        let fixture = try ExportFixture()
        let words = "The committee reviewed the budget and approved the plan for the coming year"
        let (_, pages) = try await fixture.importPDF((1...30).map { "Page \($0). \(words), item \($0 * 7)." })
        let options = ExportOptions(format: .pdf, paperSize: .a4)

        let estimate = try await fixture.exporter.estimateSize(itemName: "Doc", pages: pages, options: options)
        let real = try await realSize(fixture, pages, options)

        let error = abs(Double(estimate.byteCount - real)) / Double(real)
        #expect(error < 0.20, "estimate \(estimate.byteCount), real \(real), off by \(Int(error * 100))%")
    }

    /// A Word file carries its whole package once — styles, settings, the
    /// zip around them — and a page of words adds little: scaling four pages
    /// up would say several times the real size.
    @Test func thirtyPagesOfWordsAsAWordFileAreEstimatedWithinTwentyPercent() async throws {
        let fixture = try ExportFixture()
        let words = "The committee reviewed the budget and approved the plan for the coming year"
        let (_, pages) = try await fixture.importPDF((1...30).map { "Page \($0). \(words), item \($0 * 7)." })
        let options = ExportOptions(format: .docx, docxLayout: .editableText)

        let estimate = try await fixture.exporter.estimateSize(itemName: "Doc", pages: pages, options: options)
        let real = try await realSize(fixture, pages, options)

        let error = abs(Double(estimate.byteCount - real)) / Double(real)
        #expect(error < 0.20, "estimate \(estimate.byteCount), real \(real), off by \(Int(error * 100))%")
    }

    @Test func nothingIsLeftBehindAndNothingStored() async throws {
        let fixture = try ExportFixture()
        let pages = try await scans(fixture, count: 9)
        let exporter = try privateExporter(fixture)

        _ = try await exporter.estimateSize(itemName: "Doc", pages: pages,
                                            options: ExportOptions(format: .pdf, paperSize: .original))

        #expect(try leftovers(exporter).isEmpty)
        let after = try await fixture.store.pages(of: pages[0].itemID)
        #expect(after.map(\.revision) == pages.map(\.revision), "an estimate changed a page")
        for page in pages { #expect(try await fixture.store.recognition(for: page.id) == nil, "an estimate read text") }
    }

    @Test func cancellingStopsItAndLeavesNothing() async throws {
        let fixture = try ExportFixture()
        let pages = try await scans(fixture, count: 12)
        let exporter = try privateExporter(fixture)
        let task = Task {
            try await exporter.estimateSize(itemName: "Doc", pages: pages, options: ExportOptions(format: .pdf, paperSize: .original))
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try leftovers(exporter).isEmpty)
    }

    /// The words of a text export that has none on its sample pages say so,
    /// as the export would: nothing to estimate.
    @Test func aTextExportOfWordlessPagesIsRefusedAsTheExportWouldBe() async throws {
        let fixture = try ExportFixture()
        let pages = try await scans(fixture, count: 2)
        await #expect(throws: ExportError.noTextToExport) {
            try await fixture.exporter.estimateSize(itemName: "Doc", pages: pages, options: ExportOptions(format: .txt))
        }
    }
}

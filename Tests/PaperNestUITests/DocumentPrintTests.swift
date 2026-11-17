import CoreGraphics
import Foundation
import PDFKit
import Testing
import PaperNestCore
import PaperNestExport
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestUI

/// Printing the open document: what the system's print panel is handed, and
/// what is left behind afterwards. The panel itself is the system's; these
/// tests stand in for it and look at the file it would have printed.
@MainActor @Suite struct DocumentPrintTests {
    /// Stands in for the print panel: keeps what it was shown, and reads the
    /// file while it is still there, as the real panel does.
    @MainActor final class Panel {
        var jobs: [PrintJob] = []
        var pageCounts: [Int] = []
        var texts: [String] = []
        var data: [Data] = []
        /// Held open until released, so a test can act while the panel is up.
        var hold: CheckedContinuation<Void, Never>?
        var holds = false

        func show(_ job: PrintJob) async {
            jobs.append(job)
            let document = PDFDocument(url: job.file)
            pageCounts.append(document?.pageCount ?? -1)
            texts.append(document?.string ?? "")
            data.append((try? Data(contentsOf: job.file)) ?? Data())
            if holds { await withCheckedContinuation { hold = $0 } }
        }
    }

    private func environment() throws -> (URL, AppEnvironment) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestPrint-\(UUID().uuidString)", isDirectory: true)
        return (url, try AppEnvironment(libraryURL: url))
    }

    /// Takes the library's original files away from under it.
    private static func removeOriginals(in library: URL) throws {
        let assets = library.appendingPathComponent("Assets", isDirectory: true)
        let files = try FileManager.default.subpathsOfDirectory(atPath: assets.path).filter { $0.hasSuffix(".pdf") }
        #expect(!files.isEmpty)
        for file in files { try FileManager.default.removeItem(at: assets.appendingPathComponent(file)) }
    }

    private func report(_ pages: [String], in environment: AppEnvironment) async throws
        -> (PaperNestCore.LibraryItem, [Page]) {
        let item = try await environment.importer
            .importItem(.data(SyntheticDocuments.textPDF(pages: pages), name: "Report"))
        return (item, try await environment.store.pages(of: item.id))
    }

    @Test func theWholeDocumentReachesThePrintPanelAsOnePDFUnderItsOwnName() async throws {
        let (url, environment) = try environment()
        defer { try? FileManager.default.removeItem(at: url) }
        let (item, _) = try await report(["First", "Second", "Third"], in: environment)
        let panel = Panel()
        let printer = DocumentPrinter(panel: panel.show)

        await printer.print(item.id, in: environment)?.value

        #expect(panel.jobs.count == 1)
        #expect(panel.jobs.first?.name == "Report")
        #expect(panel.jobs.first?.pageCount == 3)
        #expect(panel.pageCounts == [3])
        #expect(panel.jobs.first?.file.pathExtension == "pdf")
        #expect(panel.texts.first?.contains("Second") == true)
        #expect(printer.phase == .idle)
        #expect(!printer.isShowingFailure)
    }

    /// Paper shows what the page shows: the pen and the typed words too.
    @Test func whatWasDrawnAndTypedOnThePageIsPrinted() async throws {
        let (url, environment) = try environment()
        defer { try? FileManager.default.removeItem(at: url) }
        let (item, pages) = try await report(["Statement"], in: environment)
        try await environment.store.saveObject(PageObject(
            pageID: pages[0].id, zKey: "m",
            payload: .ink(InkStroke(tool: .pen, color: .black, width: 20,
                                    points: [InkPoint(x: 300, y: 600), InkPoint(x: 500, y: 600)])),
            modifiedAt: Date()))
        try await environment.store.saveObject(PageObject(
            pageID: pages[0].id, zKey: "n",
            payload: .text(TextBox(frame: CGRect(x: 100, y: 200, width: 400, height: 80), text: "PAID IN FULL",
                                   fontSize: 28, color: .black, alignment: .leading)),
            modifiedAt: Date()))
        let panel = Panel()

        await DocumentPrinter(panel: panel.show).print(item.id, in: environment)?.value

        let text = try #require(panel.texts.first)
        #expect(text.contains("PAID IN FULL"), "the typed words are not on the printed page: \(text)")
        let printed = try #require(panel.data.first)
        let image = try #require(PixelProbe.renderPDFPage(printed, index: 0, scale: 0.5))
        #expect(PixelProbe.pixel(image, x: 400.0 / 612, y: 600.0 / 792).isDark, "the pen stroke is not printed")
        #expect(PixelProbe.pixel(image, x: 400.0 / 612, y: 700.0 / 792).isWhite)
    }

    /// A comment is a private note to oneself. It is not on the page, so it
    /// is not on the paper either.
    @Test func aPrivateCommentIsNotPrinted() async throws {
        let (url, environment) = try environment()
        defer { try? FileManager.default.removeItem(at: url) }
        let (item, pages) = try await report(["Statement"], in: environment)
        _ = try await environment.store.setPageComment(on: pages[0].id, replacing: nil,
                                                       text: "ask the landlord about this")
        let panel = Panel()

        await DocumentPrinter(panel: panel.show).print(item.id, in: environment)?.value

        let text = try #require(panel.texts.first)
        #expect(text.contains("Statement"))
        #expect(!text.localizedCaseInsensitiveContains("landlord"))
        #expect(panel.pageCounts == [1])
    }

    /// The pages are read when Print is chosen, in the order they are in now.
    @Test func itPrintsThePagesAsTheyAreSavedNow() async throws {
        let (url, environment) = try environment()
        defer { try? FileManager.default.removeItem(at: url) }
        let (item, pages) = try await report(["First", "Second", "Third"], in: environment)
        _ = try await environment.store.deletePages([pages[1].id])
        let panel = Panel()

        await DocumentPrinter(panel: panel.show).print(item.id, in: environment)?.value

        #expect(panel.pageCounts == [2])
        #expect(panel.texts.first?.contains("Second") == false)
        #expect(panel.texts.first?.contains("Third") == true)
    }

    @Test func theTemporaryFileIsThereForThePanelAndGoneAfterwards() async throws {
        let (url, environment) = try environment()
        defer { try? FileManager.default.removeItem(at: url) }
        let (item, _) = try await report(["First"], in: environment)
        let panel = Panel()
        panel.holds = true
        let printer = DocumentPrinter(panel: panel.show)

        let task = try #require(printer.print(item.id, in: environment))
        while panel.hold == nil { await Task.yield() }
        let file = try #require(panel.jobs.first?.file)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(printer.phase == .presenting)

        panel.hold?.resume()
        await task.value

        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))
        #expect(printer.phase == .idle)
    }

    /// ⌘P held down, or a second tap while a long document is still being
    /// made ready, must not stack print panels.
    @Test func askingAgainWhileOnePrintIsUnderWayDoesNothing() async throws {
        let (url, environment) = try environment()
        defer { try? FileManager.default.removeItem(at: url) }
        let (item, _) = try await report(["First"], in: environment)
        let panel = Panel()
        panel.holds = true
        let printer = DocumentPrinter(panel: panel.show)

        let first = try #require(printer.print(item.id, in: environment))
        #expect(printer.phase == .preparing)
        #expect(printer.print(item.id, in: environment) == nil)
        while panel.hold == nil { await Task.yield() }
        #expect(printer.print(item.id, in: environment) == nil)
        panel.hold?.resume()
        await first.value

        #expect(panel.jobs.count == 1)
        // And once it is over, printing works again.
        panel.holds = false
        await printer.print(item.id, in: environment)?.value
        #expect(panel.jobs.count == 2)
    }

    @Test func cancellingWhileTheDocumentIsMadeReadyShowsNoPanelAndLeavesNoFile() async throws {
        let (url, environment) = try environment()
        defer { try? FileManager.default.removeItem(at: url) }
        let (item, _) = try await report(Array(repeating: "Page", count: 40), in: environment)
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestPrintScratch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let panel = Panel()
        let printer = DocumentPrinter(panel: panel.show, temporaryRoot: scratch)

        let task = try #require(printer.print(item.id, in: environment))
        printer.cancel()
        await task.value

        #expect(panel.jobs.isEmpty)
        #expect(printer.phase == .idle)
        #expect(!printer.isShowingFailure, "stopping it oneself is not a failure")
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.path).isEmpty)
    }

    @Test func aDocumentWithNoPagesShowsNoPanelAndNoError() async throws {
        let (url, environment) = try environment()
        defer { try? FileManager.default.removeItem(at: url) }
        let (item, pages) = try await report(["Only"], in: environment)
        _ = try await environment.store.deletePages([pages[0].id])
        let panel = Panel()
        let printer = DocumentPrinter(panel: panel.show)

        await printer.print(item.id, in: environment)?.value

        #expect(panel.jobs.isEmpty)
        #expect(printer.phase == .idle)
        #expect(!printer.isShowingFailure)
    }

    /// A page whose original cannot be read must say so, not print blank
    /// paper and not fail silently.
    @Test func aDocumentThatCannotBeReadSaysSoInsteadOfPrinting() async throws {
        let (url, environment) = try environment()
        defer { try? FileManager.default.removeItem(at: url) }
        let (item, _) = try await report(["First"], in: environment)
        try Self.removeOriginals(in: url)
        let panel = Panel()
        let printer = DocumentPrinter(panel: panel.show)

        await printer.print(item.id, in: environment)?.value

        #expect(panel.jobs.isEmpty)
        #expect(printer.isShowingFailure)
        #expect(printer.phase == .idle)
    }

    /// Print must never run into the Pro gate or a password: it is the plain
    /// document, at the size of its own pages.
    /// Coloured pixels in the page's bottom-left corner, where the PaperNest
    /// mark sits. The test document has nothing of its own there.
    private static func cornerInk(_ image: CGImage) -> Int {
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var count = 0
        for y in Int(Double(height) * 0.93)..<height {
            for x in 0..<Int(Double(width) * 0.26) {
                let i = (y * width + x) * 4
                if buffer[i] < 250 || buffer[i + 1] < 250 || buffer[i + 2] < 250 { count += 1 }
            }
        }
        return count
    }

    /// A free user's printout carries the PaperNest mark in every page's
    /// corner, as their exports do: printing to a PDF is not a way round it.
    @Test func aFreeUsersPrintCarriesThePaperNestMark() async throws {
        let (url, environment) = try environment()
        defer { try? FileManager.default.removeItem(at: url) }
        let (item, _) = try await report(["", ""], in: environment)
        let panel = Panel()
        let printer = DocumentPrinter(panel: panel.show, freeMark: { Watermark.freeExportMark(allowsRemoval: false) })

        await printer.print(item.id, in: environment)?.value

        let data = try #require(panel.data.first)
        for index in 0..<2 {
            let image = try #require(PixelProbe.renderPDFPage(data, index: index, scale: 1))
            #expect(Self.cornerInk(image) > 100, "page \(index + 1) was printed without the mark")
        }
        // Drawn as outlines, like every watermark: never in the page's text.
        #expect(panel.texts.first?.contains("PaperNest") != true)
        #expect(!printer.isShowingFailure)
    }

    @Test func aProUsersPrintIsUnmarked() async throws {
        let (url, environment) = try environment()
        defer { try? FileManager.default.removeItem(at: url) }
        let (item, _) = try await report([""], in: environment)
        let panel = Panel()

        await DocumentPrinter(panel: panel.show, freeMark: { nil }).print(item.id, in: environment)?.value

        let data = try #require(panel.data.first)
        let image = try #require(PixelProbe.renderPDFPage(data, index: 0, scale: 1))
        #expect(Self.cornerInk(image) == 0, "a Pro user's print was marked")
    }

    /// The print's options are the plain document's, with the mark added.
    @Test func printingAddsTheMarkToThePlainDocument() {
        let mark = Watermark.freeExportMark(allowsRemoval: false)
        let options = DocumentPrinter.options(attribution: mark)
        #expect(options.attribution == mark)
        #expect(options.format == .pdf && options.paperSize == .original && !options.includesRecognizedText)
        #expect(DocumentPrinter.options(attribution: nil).attribution == nil)
    }

    @Test func printingAsksForThePlainDocumentAtItsOwnPageSizes() {
        #expect(DocumentPrinter.options.format == .pdf)
        #expect(DocumentPrinter.options.paperSize == .original)
        #expect(!DocumentPrinter.options.includesRecognizedText)
    }
}

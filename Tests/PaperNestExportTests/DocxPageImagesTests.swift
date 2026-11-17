import CoreGraphics
import Foundation
import ImageIO
import Testing
import PaperNestCore
import PaperNestRender
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestExport

/// The brief's second Word option: "appearance-preserving page images
/// embedded in DOCX". The risk is not whether pictures land in the archive
/// but whether a word processor opens it and shows one page per page: Word
/// refuses a package whose references do not resolve, or whose parts have no
/// content type, as "unreadable content" even when every part is valid XML.
@Suite struct DocxPageImagesTests {
    /// An exported `.docx`, unpacked by `/usr/bin/unzip` — an independent
    /// reader, not the writer's own idea of what it wrote.
    struct Package {
        let entries: [String]
        let root: URL

        func data(_ part: String) throws -> Data { try Data(contentsOf: root.appendingPathComponent(part)) }
        func text(_ part: String) throws -> String { String(decoding: try data(part), as: UTF8.self) }

        static func matches(_ pattern: String, in text: String) -> [[String]] {
            let regex = try! NSRegularExpression(pattern: pattern)
            let range = NSRange(text.startIndex..., in: text)
            return regex.matches(in: text, range: range).map { match in
                // An optional group that did not take part comes back empty.
                (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
            }
        }

        var document: String { (try? text("word/document.xml")) ?? "" }

        /// `w:pgSz` and `w:pgMar` of each section, in order.
        var sections: [(width: Int, height: Int, landscape: Bool, top: Int, right: Int, bottom: Int, left: Int)] {
            let sizes = Self.matches(#"<w:pgSz w:w="(\d+)" w:h="(\d+)"( w:orient="landscape")?/>"#, in: document)
            let margins = Self.matches(#"<w:pgMar w:top="(\d+)" w:right="(\d+)" w:bottom="(\d+)" w:left="(\d+)""#, in: document)
            return zip(sizes, margins).map { size, margin in
                (Int(size[0])!, Int(size[1])!, !size[2].isEmpty,
                 Int(margin[0])!, Int(margin[1])!, Int(margin[2])!, Int(margin[3])!)
            }
        }

        /// Each picture's `wp:extent`, in order.
        var extents: [(cx: Int, cy: Int)] {
            Self.matches(#"<wp:extent cx="(\d+)" cy="(\d+)"/>"#, in: document).map { (Int($0[0])!, Int($0[1])!) }
        }
    }

    private func export(_ fixture: ExportFixture, _ pages: [Page], _ options: ExportOptions = .pageImages)
        async throws -> (Package, ExportOutput) {
        // Inside the fixture's own folder rather than the system's temporary
        // one: `BulkExportTests` fails on any export folder it finds there,
        // and a run of this suite that stops early must not leave one.
        let exporter = Exporter(renderer: fixture.exporter.renderer, temporaryRoot: fixture.url)
        let output = try await exporter.export(itemName: "Pictures", pages: pages, options: options)
        let file = try #require(output.files.first)
        #expect(output.files.count == 1)
        #expect(file.pathExtension == "docx")
        let listed = try unzip(["-Z1", file.path])
        #expect(listed.status == 0, "the file has to be a readable ZIP: \(listed.output)")
        let root = output.directory.appendingPathComponent("unpacked", isDirectory: true)
        let unpacked = try unzip(["-q", file.path, "-d", root.path])
        #expect(unpacked.status == 0, "\(unpacked.output)")
        return (Package(entries: listed.output.split(separator: "\n").map(String.init), root: root), output)
    }

    private func blankNotebook(_ fixture: ExportFixture, pages: Int, size: CGSize = CGSize(width: 600, height: 800))
        async throws -> [Page] {
        let item = try await fixture.store.createItem(kind: .notebook, name: "Sketches", pages: (0..<pages).map { _ in
            .init(sourceSize: size, content: .template(.blank))
        }, assets: [])
        return try await fixture.store.pages(of: item.id)
    }

    private func picture(_ package: Package, page: Int) throws -> CGImage {
        let data = try package.data("word/media/page\(page).jpeg")
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == "public.jpeg", "the part is named .jpeg; its bytes must be JPEG")
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    // MARK: - The point of the layout

    /// The pair that makes this layout worth having. A notebook of drawings
    /// has no words, so the text layout refuses it — rightly — and the
    /// picture layout must not.
    @Test func aNotebookWithNoTextExportsAsPicturesWhereEditableTextIsRefused() async throws {
        let fixture = try ExportFixture()
        let pages = try await blankNotebook(fixture, pages: 2)

        await #expect(throws: ExportError.noTextToExport) {
            try await fixture.exporter.export(itemName: "Sketches", pages: pages,
                                              options: ExportOptions(format: .docx, docxLayout: .editableText))
        }
        let (package, output) = try await export(fixture, pages)
        defer { output.removeTemporaryFiles() }
        #expect(package.entries.filter { $0.hasPrefix("word/media/") }.sorted()
                == ["word/media/page1.jpeg", "word/media/page2.jpeg"])
    }

    /// Pictures of words are not words, and the file must not pretend
    /// otherwise: not one text run, even for a page that has text to give.
    @Test func noWordsAreWrittenEvenWhenThePageHasThem() async throws {
        let fixture = try ExportFixture()
        let (_, pages) = try await fixture.importPDF(["Quarterly statement"])

        let (package, output) = try await export(fixture, pages)
        defer { output.removeTemporaryFiles() }

        #expect(!package.document.contains("<w:t"))
        #expect(!package.document.contains("Quarterly statement"))
    }

    // MARK: - A package Word will open

    @Test func everyReferenceResolvesAndEveryPartHasAContentType() async throws {
        let fixture = try ExportFixture()
        let (_, pages) = try await fixture.importPDF(["One", "Two", "Three"])
        let (package, output) = try await export(fixture, pages)
        defer { output.removeTemporaryFiles() }

        for part in ["[Content_Types].xml", "_rels/.rels", "word/document.xml", "word/_rels/document.xml.rels"] {
            #expect(package.entries.contains(part), "\(part) is missing")
            #expect(XMLParser(data: try package.data(part)).parse(), "\(part) is not well-formed XML")
        }

        // The package relationship points at the document that is there.
        let packageTargets = Package.matches(#"Target="([^"]+)""#, in: try package.text("_rels/.rels")).map { $0[0] }
        #expect(packageTargets == ["word/document.xml"])

        // Every picture's r:embed is a relationship, and every relationship's
        // target is a file in the archive.
        let relationships = Dictionary(uniqueKeysWithValues: Package.matches(
            #"<Relationship Id="([^"]+)" Type="[^"]+/image" Target="([^"]+)"/>"#,
            in: try package.text("word/_rels/document.xml.rels")).map { ($0[0], $0[1]) })
        let embeds = Package.matches(#"r:embed="([^"]+)""#, in: package.document).map { $0[0] }
        #expect(embeds.count == 3)
        for embed in embeds {
            let target = try #require(relationships[embed], "\(embed) has no relationship")
            #expect(package.entries.contains("word/" + target), "\(target) is not in the archive")
        }
        #expect(Set(relationships.keys) == Set(embeds), "a relationship nothing uses, or one used twice")

        // Every part's extension, or its own name, has a content type.
        let types = try package.text("[Content_Types].xml")
        let defaults = Set(Package.matches(#"<Default Extension="([^"]+)""#, in: types).map { $0[0] })
        let overrides = Set(Package.matches(#"<Override PartName="/([^"]+)""#, in: types).map { $0[0] })
        for entry in package.entries where entry != "[Content_Types].xml" && !entry.hasSuffix("/") {
            // What follows the last dot, as the packaging spec reads it:
            // `.rels` is extension "rels", where NSString sees a dot-file
            // with no extension at all.
            let ext = entry.split(separator: "/").last.flatMap { $0.split(separator: ".").last }.map(String.init) ?? ""
            #expect(defaults.contains(ext) || overrides.contains(entry), "\(entry) has no content type")
        }
        #expect(overrides.contains("word/document.xml"))

        // Drawing ids must be unique in the document.
        let ids = Package.matches(#"<wp:docPr id="(\d+)""#, in: package.document).map { $0[0] }
        #expect(ids.count == 3 && Set(ids).count == 3)
    }

    /// One section per page, the next starting a new Word page. A
    /// page-break paragraph after a full-page picture would leave a blank
    /// page behind every page.
    @Test func eachPageIsItsOwnSectionWithNoPageBreakParagraphs() async throws {
        let fixture = try ExportFixture()
        let pages = try await blankNotebook(fixture, pages: 3)
        let (package, output) = try await export(fixture, pages)
        defer { output.removeTemporaryFiles() }

        #expect(!package.document.contains("w:br"))
        #expect(Package.matches(#"(<w:p>)"#, in: package.document).count == 3, "one paragraph per page, nothing else")
        #expect(Package.matches(#"(<w:sectPr>)"#, in: package.document).count == 3)
        #expect(package.document.hasSuffix("</w:sectPr></w:body></w:document>"),
                "the last page's section belongs to the body itself")
    }

    // MARK: - Pages the size they are

    @Test func aPortraitAndARotatedPageKeepTheirSizeAndOrientation() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["Portrait", "Turned"])
        try await fixture.store.updateTransform(pages[1].id, to: PageTransform(rotation: .clockwise90))
        let current = try await fixture.store.pages(of: item.id)

        let (package, output) = try await export(fixture, current)
        defer { output.removeTemporaryFiles() }

        let sections = package.sections
        try #require(sections.count == 2)
        #expect(sections[0].width == 612 * 20 && sections[0].height == 792 * 20 && !sections[0].landscape)
        #expect(sections[1].width == 792 * 20 && sections[1].height == 612 * 20 && sections[1].landscape)
        #expect(sections.allSatisfy { $0.top == 0 && $0.right == 0 && $0.bottom == 0 && $0.left == 0 },
                "at the page's own size the picture is the whole page")
        // The picture fills its page exactly.
        let extents = package.extents
        #expect(extents.count == 2)
        #expect(extents[0].cx == 612 * 20 * 635 && extents[0].cy == 792 * 20 * 635)
        #expect(extents[1].cx == 792 * 20 * 635 && extents[1].cy == 612 * 20 * 635)
    }

    @Test func aCroppedPageIsTheSizeOfWhatIsLeft() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["Cropped"])
        try await fixture.store.updateTransform(
            pages[0].id, to: PageTransform(crop: NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)))
        let current = try await fixture.store.pages(of: item.id)

        let (package, output) = try await export(fixture, current)
        defer { output.removeTemporaryFiles() }

        #expect(package.sections.first?.width == 306 * 20)
        #expect(package.sections.first?.height == 396 * 20)
    }

    @Test func letterPaperFitsTheWholePageWithMarginsAroundIt() async throws {
        let fixture = try ExportFixture()
        let (_, pages) = try await fixture.importPDF(["Receipt"], size: CGSize(width: 300, height: 1200))

        let (package, output) = try await export(
            fixture, pages, ExportOptions(format: .docx, paperSize: .usLetter, docxLayout: .pageImages))
        defer { output.removeTemporaryFiles() }

        let section = try #require(package.sections.first)
        #expect(section.width == 12240 && section.height == 15840)
        #expect(section.top == 0 && section.bottom == 0, "a tall receipt fills the sheet's height")
        #expect(section.left > 0 && abs(section.left - section.right) <= 1, "and is centred across it")
        let extent = try #require(package.extents.first)
        #expect(extent.cx == (section.width - section.left - section.right) * 635)
        #expect(abs(Double(extent.cx) / Double(extent.cy) - 300.0 / 1200.0) < 0.002, "nothing stretched")
    }

    /// The arithmetic on its own, for sizes no fixture makes: margins and
    /// picture always add up to the page exactly, nothing is negative, and no
    /// side is larger than Word allows.
    @Test(arguments: [
        (CGSize(width: 612, height: 792), PaperSize.original),
        (CGSize(width: 300, height: 1200), .a4),
        (CGSize(width: 1200, height: 300), .usLetter),
        (CGSize(width: 841.89, height: 595.28), .original),
        (CGSize(width: 0.4, height: 0.4), .original),
        (CGSize(width: 3000, height: 2000), .original),
    ])
    func marginsAndPictureAlwaysMakeUpThePage(_ size: CGSize, _ paper: PaperSize) {
        let section = DocxPageSection(pageSize: size, paper: paper)
        #expect([section.leftTwips, section.topTwips, section.rightTwips, section.bottomTwips].allSatisfy { $0 >= 0 })
        #expect(section.leftTwips + section.pictureWidthTwips + section.rightTwips == section.pageWidthTwips)
        #expect(section.topTwips + section.pictureHeightTwips + section.bottomTwips == section.pageHeightTwips)
        #expect(section.pictureWidthTwips >= 1 && section.pictureHeightTwips >= 1)
        #expect(max(section.pageWidthTwips, section.pageHeightTwips) <= DocxPageSection.maximumSideTwips)
    }

    /// A poster-sized PDF page is bigger than any page Word will make. It is
    /// scaled down whole, and drawn with correspondingly fewer pixels.
    @Test func aPageLargerThanWordAllowsIsShrunkWhole() {
        let section = DocxPageSection(pageSize: CGSize(width: 3000, height: 2000), paper: .original)

        #expect(section.pageWidthTwips == 31680)
        #expect(section.pageHeightTwips == 21120)
        #expect(section.isLandscape)
        #expect(abs(section.pictureScale(for: CGSize(width: 3000, height: 2000)) - 0.528) < 0.0001)
    }

    // MARK: - The picture is the page

    @Test func thePictureIsTheRenderedPageUprightAtTheChosenResolution() async throws {
        let fixture = try ExportFixture()
        let (_, pages) = try await fixture.importPDF(["Marked"])

        let (package, output) = try await export(
            fixture, pages, ExportOptions(format: .docx, imageDPI: 150, docxLayout: .pageImages))
        defer { output.removeTemporaryFiles() }

        let image = try picture(package, page: 1)
        #expect(image.width == 1275 && image.height == 1650, "612 × 792 points at 150 dpi")
        // The fixture's orientation marker, top-left.
        let marker = Double(SyntheticDocuments.markerInset + SyntheticDocuments.markerSize / 2)
        #expect(PixelProbe.pixel(image, x: marker / 612, y: marker / 792).isDark)
        #expect(PixelProbe.pixel(image, x: 0.97, y: 0.97).isWhite)
    }

    /// Appearance-preserving means what was drawn on the page comes too.
    @Test func inkDrawnOnThePageIsInThePicture() async throws {
        let fixture = try ExportFixture()
        let pages = try await blankNotebook(fixture, pages: 1)
        let stroke = InkStroke(tool: .pen, color: .black, width: 40,
                               points: [InkPoint(x: 100, y: 400), InkPoint(x: 500, y: 400)])
        try await fixture.store.saveObject(PageObject(pageID: pages[0].id, zKey: "m", payload: .ink(stroke),
                                                      modifiedAt: Date()))

        let (package, output) = try await export(
            fixture, pages, ExportOptions(format: .docx, imageDPI: 72, docxLayout: .pageImages))
        defer { output.removeTemporaryFiles() }

        let image = try picture(package, page: 1)
        #expect(PixelProbe.pixel(image, x: 0.5, y: 0.5).isDark, "the stroke across the middle")
        #expect(PixelProbe.pixel(image, x: 0.5, y: 0.2).isWhite, "and the paper around it")
    }

    // MARK: - What it refuses

    @Test func aPasswordIsRefusedBecauseAWordFileCannotCarryOne() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["Memo"])

        await #expect(throws: ExportError.passwordNotSupported) {
            try await fixture.exporter.export(itemName: item.name, pages: pages, options: .pageImages,
                                              password: "secret-2026")
        }
    }

    @Test func cancellingStopsAndLeavesNothingBehind() async throws {
        let fixture = try ExportFixture()
        let pages = try await blankNotebook(fixture, pages: 6)
        let root = fixture.url.appendingPathComponent("docx-exports", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let exporter = Exporter(renderer: fixture.exporter.renderer, temporaryRoot: root)
        // Held at page 2 until the cancel has been issued, so a fast machine
        // cannot finish first and turn this into a race.
        let reachedPageTwo = AsyncStream<Void>.makeStream()
        let cancelIssued = DispatchSemaphore(value: 0)
        let task = Task {
            try await exporter.export(itemName: "Sketches", pages: pages, options: .pageImages) { progress in
                if progress.completedPages == 2 {
                    reachedPageTwo.continuation.yield()
                    cancelIssued.wait()
                }
            }
        }
        for await _ in reachedPageTwo.stream { break }
        task.cancel()
        cancelIssued.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    // MARK: - What the options say about it

    @Test func onlyEditableTextKeepsOnlyWords() {
        #expect(ExportOptions(format: .docx).keepsOnlyWords, "editable text stays the default")
        #expect(ExportOptions(format: .docx, docxLayout: .editableText).keepsOnlyWords)
        #expect(!ExportOptions(format: .docx, docxLayout: .pageImages).keepsOnlyWords)
        #expect(ExportOptions(format: .txt, docxLayout: .pageImages).keepsOnlyWords, "the layout is Word's alone")
        #expect(!ExportOptions(format: .jpeg).keepsOnlyWords)
    }

    /// A Word or text file of many pages is still one file. Copy was refused
    /// for one because the screen took any non-PDF of several pages for a ZIP.
    @Test func onlySeveralPicturesInAZipMakeAnArchive() {
        for format in [ExportFormat.pdf, .txt, .docx] {
            for packaging in ImagePackaging.allCases {
                #expect(!ExportOptions(format: format, packaging: packaging).writesArchive(pageCount: 5), "\(format)")
            }
        }
        #expect(!ExportOptions(format: .docx, packaging: .zip, docxLayout: .pageImages).writesArchive(pageCount: 5))
        for format in [ExportFormat.jpeg, .png, .heic] {
            #expect(ExportOptions(format: format, packaging: .zip).writesArchive(pageCount: 2), "\(format)")
            #expect(!ExportOptions(format: format, packaging: .zip).writesArchive(pageCount: 1), "\(format)")
            #expect(!ExportOptions(format: format, packaging: .separateFiles).writesArchive(pageCount: 2), "\(format)")
        }
    }

    @Test func severalPageImagesAreOneWordFileEvenWithZipChosen() async throws {
        let fixture = try ExportFixture()
        let pages = try await blankNotebook(fixture, pages: 3)
        let (_, output) = try await export(
            fixture, pages, ExportOptions(format: .docx, imageDPI: 72, packaging: .zip, docxLayout: .pageImages))
        defer { output.removeTemporaryFiles() }
        #expect(output.files.map(\.lastPathComponent) == ["Pictures.docx"])
    }
}

extension ExportOptions {
    /// A Word file of page images at a small resolution, so tests stay quick.
    fileprivate static let pageImages = ExportOptions(format: .docx, imageDPI: 72, docxLayout: .pageImages)
}

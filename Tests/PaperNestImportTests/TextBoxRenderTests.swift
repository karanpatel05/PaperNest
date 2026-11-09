import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestImport
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestRender

/// The rest of row 21: text typed onto a page.
///
/// Probes scan a *region* for any dark pixel rather than reading one point,
/// because a single sample can land in the gap between two letters and say
/// "nothing here" about text that is plainly there.
@Suite struct TextBoxRenderTests {
    @Test func selectionTracksVisibleAlignedAndWrappedGlyphs() {
        let frame = CGRect(x: 100, y: 200, width: 240, height: 90)
        for alignment in [TextBox.Alignment.leading, .center, .trailing] {
            let box = TextBox(frame: frame, text: "Hi", fontSize: 20, alignment: alignment)
            let rects = PageRenderer.textSelectionRects(box)
            #expect(rects.count == 2)
            let bounds = rects.reduce(CGRect.null) { $0.union($1) }
            #expect(frame.contains(bounds))
            #expect(bounds.maxY < frame.minY + 30)
            switch alignment {
            case .leading: #expect(bounds.maxX < frame.minX + 30)
            case .center: #expect(abs(bounds.midX - frame.midX) < 3)
            case .trailing: #expect(bounds.minX > frame.maxX - 30)
            }
        }
        let wrapped = TextBox(frame: CGRect(x: 100, y: 200, width: 80, height: 90),
                              text: "First second third fourth fifth sixth", fontSize: 20)
        let rects = PageRenderer.textSelectionRects(wrapped)
        #expect(!rects.isEmpty)
        #expect(rects.allSatisfy { wrapped.frame.contains($0) })
        #expect(rects.contains { $0.minY > wrapped.frame.minY + 30 })
        for blank in ["", "   ", "\n\n"] {
            #expect(PageRenderer.textSelectionRects(TextBox(frame: frame, text: blank)).isEmpty)
        }
    }

    private struct Library {
        let directory: URL
        let store: LibraryStore
        let page: Page
        let renderer: PageRenderer
    }

    private func seeded() async throws -> Library {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestTextBox-\(UUID().uuidString)", isDirectory: true)
        let store = try LibraryStore(directory: directory)
        let item = try await DocumentImporter(store: store)
            .importItem(.data(SyntheticDocuments.textPDF(pages: ["Statement"]), name: "Statement"))
        return Library(directory: directory, store: store,
                       page: try await store.pages(of: item.id)[0], renderer: PageRenderer(store: store))
    }

    /// The box sits in the page's lower half, which the fixture leaves white —
    /// its own line of text and its corner marker are up top, so anything dark
    /// down here came from the text box.
    private let box = CGRect(x: 100, y: 450, width: 400, height: 250)

    private func write(_ library: Library, _ text: String, fontSize: Double = 28,
                       alignment: TextBox.Alignment = .leading) async throws {
        try await library.store.saveObject(PageObject(
            pageID: library.page.id, zKey: "m",
            payload: .text(TextBox(frame: box, text: text, fontSize: fontSize,
                                   color: .black, alignment: alignment)),
            modifiedAt: Date()))
    }

    /// The rendered page read **once** into memory.
    ///
    /// `PixelProbe.pixel` redraws the whole image for every sample, which is
    /// fine for a handful of points and hopeless for a region scan — the first
    /// version of these tests took a minute each.
    private struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        init(_ image: CGImage) {
            width = image.width
            height = image.height
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            let ctx = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            bytes = buffer
        }

        func isDark(x: Double, y: Double) -> Bool {
            let px = min(width - 1, max(0, Int(Double(width) * x)))
            let py = min(height - 1, max(0, Int(Double(height) * y)))
            let i = (py * width + px) * 4
            return bytes[i] < 80 && bytes[i + 1] < 80 && bytes[i + 2] < 80
        }
    }

    /// Any dark pixel in a rectangle given in fractions of the page. A region
    /// rather than a point, because one sample can land in the gap between two
    /// letters and report nothing about text that is plainly there.
    private func anyDark(_ pixels: Pixels, x: ClosedRange<Double>, y: ClosedRange<Double>) -> Bool {
        let steps = 120
        for i in 0...steps {
            for j in 0...steps {
                let px = x.lowerBound + (x.upperBound - x.lowerBound) * Double(i) / Double(steps)
                let py = y.lowerBound + (y.upperBound - y.lowerBound) * Double(j) / Double(steps)
                if pixels.isDark(x: px, y: py) { return true }
            }
        }
        return false
    }

    @Test func typedTextIsPaintedInsideItsBox() async throws {
        let library = try await seeded()
        defer { try? FileManager.default.removeItem(at: library.directory) }
        try await write(library, "HELLO WORLD")

        let rendered = Pixels(try await library.renderer.renderImage(library.page, pixelsPerPoint: 2))

        #expect(anyDark(rendered, x: 0.16...0.80, y: 0.57...0.88), "no text was painted in the box")
        // To the left of the box, in a band the fixture leaves white.
        #expect(!anyDark(rendered, x: 0.02...0.14, y: 0.60...0.88), "something was painted outside the box")
    }

    /// Text begins at the **top** of its box and runs down. Drawn the other way
    /// up it would still be dark pixels inside the box, so the only thing that
    /// catches a flip is where in the box they land.
    @Test func textStartsAtTheTopOfItsBox() async throws {
        let library = try await seeded()
        defer { try? FileManager.default.removeItem(at: library.directory) }
        try await write(library, "TOP LINE")

        let rendered = Pixels(try await library.renderer.renderImage(library.page, pixelsPerPoint: 2))

        // One short line at 28pt fills roughly the first 40pt of a 250pt box.
        #expect(anyDark(rendered, x: 0.16...0.80, y: 0.57...0.61), "the line is not at the top of the box")
        #expect(!anyDark(rendered, x: 0.16...0.80, y: 0.70...0.88), "the line was drawn upside down")
    }

    @Test func alignmentPutsTheTextWhereItSays() async throws {
        let library = try await seeded()
        defer { try? FileManager.default.removeItem(at: library.directory) }
        try await write(library, "END", alignment: .trailing)

        let rendered = Pixels(try await library.renderer.renderImage(library.page, pixelsPerPoint: 2))

        #expect(anyDark(rendered, x: 0.60...0.81, y: 0.57...0.62), "trailing text is not at the right edge")
        #expect(!anyDark(rendered, x: 0.17...0.40, y: 0.57...0.62), "trailing text was drawn on the left")
    }

    @Test func anEmptyBoxPaintsNothing() async throws {
        let library = try await seeded()
        defer { try? FileManager.default.removeItem(at: library.directory) }
        try await write(library, "")

        let rendered = Pixels(try await library.renderer.renderImage(library.page, pixelsPerPoint: 2))

        #expect(!anyDark(rendered, x: 0.16...0.80, y: 0.57...0.88))
    }
    @Test func excludingEditedTextRemovesOnlyItsBackingRendering() async throws {
        let library = try await seeded()
        defer { try? FileManager.default.removeItem(at: library.directory) }
        let (_, selected) = try await library.store.placeText("EDIT ME", on: library.page.id, frame: box,
            fontSize: 28, color: .black, alignment: .leading)
        let (_, retained) = try await library.store.placeText("KEEP ME", on: library.page.id,
            frame: CGRect(x: 100, y: 600, width: 400, height: 80), fontSize: 28,
            color: .black, alignment: .leading)
        let layers = try await library.renderer.layers(for: library.page, pixelsPerPoint: 1,
            excludingObjectIDs: [selected.id])
        #expect(layers.count == 1)
        guard case .text(let retainedBox) = retained.payload,
              case .text(let layerBox) = layers.first else { Issue.record("missing retained text"); return }
        #expect(layerBox == retainedBox)
        let rendered = Pixels(try await library.renderer.renderImage(library.page, pixelsPerPoint: 1,
            excludingObjectIDs: [selected.id]))
        #expect(!anyDark(rendered, x: 0.16...0.80, y: 0.57...0.61))
        #expect(anyDark(rendered, x: 0.16...0.80, y: 0.76...0.80))
        let thumbnail = Pixels(try await library.renderer.renderThumbnail(library.page, maxPixelSize: 792,
            excludingObjectIDs: [selected.id]))
        #expect(!anyDark(thumbnail, x: 0.16...0.80, y: 0.57...0.61))
        #expect(anyDark(thumbnail, x: 0.16...0.80, y: 0.76...0.80))
        #expect(try await library.store.objects(on: library.page.id).count == 2)
    }

}

import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestImport
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestRender

/// Row 21's placed images. The models existed and the store already kept them;
/// nothing painted them.
///
/// The fixture image is white with a **red square across its top-left fifth**
/// and a black stripe through its middle, so a probe just inside the placed
/// frame's top-left corner says not only whether the image landed but *where*
/// — an image drawn at the wrong place, or flipped, fails these.
@Suite struct PlacedImageRenderTests {
    private struct Library {
        let directory: URL
        let store: LibraryStore
        let page: Page
        let renderer: PageRenderer
        let stamp: AssetID
    }

    /// A one-page PDF to place things on, and a separate imported image to
    /// place. Placing reuses that image's asset, which is what a screen would
    /// do rather than storing the bytes twice.
    private func seeded() async throws -> Library {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestPlacedImage-\(UUID().uuidString)", isDirectory: true)
        let store = try LibraryStore(directory: directory)
        let importer = DocumentImporter(store: store)
        let document = try await importer.importItem(
            .data(SyntheticDocuments.textPDF(pages: ["Statement"]), name: "Statement"))
        let stampItem = try await importer.importItem(
            .data(SyntheticDocuments.image(width: 200, height: 200, type: .png), name: "Stamp"))
        let stampAsset = try #require(try await store.pages(of: stampItem.id)[0].content.assetID)
        return Library(directory: directory, store: store,
                       page: try await store.pages(of: document.id)[0],
                       renderer: PageRenderer(store: store), stamp: stampAsset)
    }

    /// Where the image goes, in upright source points on a 612×792 page: the
    /// start of the lower-right quadrant.
    private let frame = CGRect(x: 306, y: 396, width: 200, height: 200)
    /// Inside the frame's red corner — source (318, 408).
    private let inRedCorner = (x: 0.52, y: 0.515)

    private func place(_ library: Library, zKey: String) async throws {
        try await library.store.saveObject(PageObject(
            pageID: library.page.id, zKey: zKey,
            payload: .image(PlacedImage(assetID: library.stamp, frame: frame)),
            modifiedAt: Date()))
    }

    /// A thick black stroke straight through the red corner, so whichever of
    /// the two is painted last decides that pixel.
    private func drawInk(_ library: Library, zKey: String) async throws {
        let stroke = InkStroke(tool: .pen, color: .black, width: 30,
                               points: [InkPoint(x: 300, y: 410), InkPoint(x: 520, y: 410)])
        try await library.store.saveObject(PageObject(
            pageID: library.page.id, zKey: zKey, payload: .ink(stroke), modifiedAt: Date()))
    }

    @Test func aPlacedImageIsPaintedOnThePage() async throws {
        let library = try await seeded()
        defer { try? FileManager.default.removeItem(at: library.directory) }
        try await place(library, zKey: "m")

        let rendered = try await library.renderer.renderImage(library.page, pixelsPerPoint: 1)

        let inside = PixelProbe.pixel(rendered, x: inRedCorner.x, y: inRedCorner.y)
        #expect(inside.r > 200 && inside.g < 80 && inside.b < 80,
                "the image's red corner is not where it was put: \(inside)")
        // Nothing was painted outside the frame it was given.
        let outside = PixelProbe.pixel(rendered, x: 0.2, y: 0.85)
        #expect(outside.r > 240 && outside.g > 240 && outside.b > 240,
                "something was painted outside the frame: \(outside)")
    }

    /// Order is the page's own `zKey` order, not "images under ink".
    @Test func anImagePlacedOverInkCoversIt() async throws {
        let library = try await seeded()
        defer { try? FileManager.default.removeItem(at: library.directory) }
        try await drawInk(library, zKey: "a")
        try await place(library, zKey: "z")

        let rendered = try await library.renderer.renderImage(library.page, pixelsPerPoint: 1)

        let pixel = PixelProbe.pixel(rendered, x: inRedCorner.x, y: inRedCorner.y)
        #expect(pixel.r > 200 && pixel.g < 80 && pixel.b < 80,
                "the ink is still on top of an image placed over it: \(pixel)")
    }

    @Test func inkDrawnOverAnImageCoversIt() async throws {
        let library = try await seeded()
        defer { try? FileManager.default.removeItem(at: library.directory) }
        try await place(library, zKey: "a")
        try await drawInk(library, zKey: "z")

        let rendered = try await library.renderer.renderImage(library.page, pixelsPerPoint: 1)

        let pixel = PixelProbe.pixel(rendered, x: inRedCorner.x, y: inRedCorner.y)
        #expect(pixel.isDark, "the image covered ink drawn on top of it: \(pixel)")
    }

    /// `includingInk: false` is for the ink editor, which paints the strokes it
    /// is editing itself. A placed image is not ink, so it has to stay — or the
    /// page would appear to lose it the moment someone started drawing.
    @Test func theInkEditorStillSeesAPlacedImage() async throws {
        let library = try await seeded()
        defer { try? FileManager.default.removeItem(at: library.directory) }
        try await place(library, zKey: "a")
        try await drawInk(library, zKey: "z")

        let rendered = try await library.renderer.renderImage(
            library.page, pixelsPerPoint: 1, includingInk: false)

        let pixel = PixelProbe.pixel(rendered, x: inRedCorner.x, y: inRedCorner.y)
        #expect(pixel.r > 200 && pixel.g < 80 && pixel.b < 80,
                "the image went missing with the ink, or the ink is still drawn: \(pixel)")
    }
}

import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestRender

@Suite struct SelectionRenderTests {
    private struct Fixture {
        let root: URL
        let store: LibraryStore
        let page: Page
        let renderer: PageRenderer
        let ink: PageObject
        let text: PageObject
        let image: PageObject
        let unselected: PageObject
    }

    private func fixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SelectionRender-\(UUID())")
        let store = try LibraryStore(directory: root)
        let item = try await store.createItem(kind: .notebook, name: "Selection", pages: [
            .init(sourceSize: CGSize(width: 400, height: 400), content: .template(.grid))
        ], assets: [])
        let page = try await store.pages(of: item.id)[0]
        let ink = PageObject(pageID: page.id, zKey: "a", payload: .ink(InkStroke(tool: .pen,
            color: .black, width: 8, points: [.init(x: 40, y: 50), .init(x: 80, y: 50)])), modifiedAt: Date())
        let text = PageObject(pageID: page.id, zKey: "b", payload: .text(TextBox(
            frame: CGRect(x: 120, y: 30, width: 150, height: 60), text: "SELECT", fontSize: 24)), modifiedAt: Date())
        let unselected = PageObject(pageID: page.id, zKey: "c", payload: .ink(InkStroke(tool: .pen,
            color: .black, width: 12, points: [.init(x: 40, y: 300), .init(x: 100, y: 300)])), modifiedAt: Date())
        _ = try await store.applyObjectChanges(on: page.id, saving: [ink, text, unselected], deleting: [])
        let staged = try store.assets.store(SyntheticDocuments.image(width: 100, height: 100, type: .png),
                                             kind: .png, originalFilename: nil)
        let (updated, image) = try await store.placeImage(staged, on: page.id,
            frame: CGRect(x: 100, y: 130, width: 100, height: 100))
        return Fixture(root: root, store: store, page: updated, renderer: PageRenderer(store: store),
                       ink: ink, text: text, image: image, unselected: unselected)
    }

    @Test func mixedSelectionContainsOnlyChosenLayersOnTransparentPaper() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let before = try await f.store.objects(on: f.page.id)
        let image = try await f.renderer.renderSelection(f.page,
            objectIDs: [f.ink.id, f.text.id, f.image.id], pixelsPerPoint: 1)
        let pixels = try Pixels(image)
        #expect(image.width == 400 && image.height == 400)
        #expect(image.alphaInfo == .premultipliedLast)
        #expect(pixels.pixel(x: 5, y: 5).a == 0, "neither white paper nor the grid template belongs in the preview")
        #expect(pixels.pixel(x: 60, y: 50).a > 240)
        #expect(pixels.hasAlpha(in: CGRect(x: 120, y: 30, width: 150, height: 40)), "selected text must stay visible")
        let red = pixels.pixel(x: 108, y: 138)
        #expect(red.r > 200 && red.g < 80 && red.b < 80 && red.a > 240)
        #expect(pixels.pixel(x: 60, y: 300).a == 0, "unselected ink must not move with the preview")
        #expect(try await f.store.objects(on: f.page.id) == before)
        #expect(try await f.store.page(f.page.id) == f.page, "rendering a drag preview never flattens or writes objects")

        let imageOnly = try Pixels(try await f.renderer.renderSelection(f.page, objectIDs: [f.image.id], pixelsPerPoint: 1))
        #expect(imageOnly.pixel(x: 108, y: 138).a > 240)
        #expect(imageOnly.pixel(x: 60, y: 50).a == 0)
        #expect(!imageOnly.hasAlpha(in: CGRect(x: 120, y: 30, width: 150, height: 40)))
    }

    @Test func selectionFollowsCropAndQuarterTurnAndClipsOutsideInk() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let inside = PageObject(pageID: f.page.id, zKey: "z", payload: .ink(InkStroke(tool: .pen,
            color: .black, width: 8, points: [.init(x: 120, y: 140), .init(x: 180, y: 140)])), modifiedAt: Date())
        try await f.store.saveObject(inside)
        var transform = f.page.transform
        transform.crop = .init(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        transform.rotation = .clockwise90
        let page = try await f.store.updateTransform(f.page.id, to: transform)
        let image = try await f.renderer.renderSelection(page, objectIDs: [inside.id, f.ink.id], pixelsPerPoint: 2)
        #expect(image.width == 400 && image.height == 400)
        let pixels = try Pixels(image)
        // In the displayed 200×200 crop, source (150,140) rotates to (160,50).
        #expect(pixels.pixel(x: 320, y: 100).a > 240)
        #expect(pixels.pixel(x: 80, y: 100).a == 0, "a flipped or unrotated selection is misplaced")
        #expect(pixels.pixel(x: 10, y: 10).a == 0)
        #expect(!pixels.hasAlpha(in: CGRect(x: 0, y: 0, width: 280, height: 400)), "selected ink outside the crop remains clipped")
    }

    @Test func emptySelectionAndUnselectedMissingAssetsStayTransparent() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let missing = PageObject(pageID: f.page.id, zKey: "z", payload: .image(PlacedImage(
            assetID: AssetID(sha256: String(repeating: "f", count: 64)), frame: CGRect(x: 20, y: 20, width: 80, height: 80))), modifiedAt: Date())
        try await f.store.saveObject(missing)
        // A transient ink preview must not try to decode an unrelated image.
        let inkOnly = try Pixels(try await f.renderer.renderSelection(f.page, objectIDs: [f.ink.id], pixelsPerPoint: 1))
        #expect(inkOnly.pixel(x: 60, y: 50).a > 240)
        let empty = try Pixels(try await f.renderer.renderSelection(f.page, objectIDs: [], pixelsPerPoint: 1))
        #expect(!empty.hasAlpha(in: CGRect(x: 0, y: 0, width: 400, height: 400)))
    }

    @Test func invalidOrExcessivePreviewScaleIsRefusedBeforeAllocation() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        for scale: CGFloat in [0, -1, .nan, .infinity, 1_000_000] {
            await #expect(throws: RenderError.outputTooLarge) {
                try await f.renderer.renderSelection(f.page, objectIDs: [], pixelsPerPoint: scale)
            }
        }
    }

    private struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        init(_ image: CGImage) throws {
            width = image.width; height = image.height
            var data = [UInt8](repeating: 0, count: width * height * 4)
            let w = width, h = height
            try data.withUnsafeMutableBytes { buffer in
                let context = try #require(CGContext(data: buffer.baseAddress, width: w, height: h,
                    bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            bytes = data
        }

        func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            let i = (y * width + x) * 4
            return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
        }

        func hasAlpha(in rect: CGRect) -> Bool {
            for y in max(0, Int(rect.minY))..<min(height, Int(rect.maxY)) {
                for x in max(0, Int(rect.minX))..<min(width, Int(rect.maxX)) where pixel(x: x, y: y).a > 10 { return true }
            }
            return false
        }
    }
}

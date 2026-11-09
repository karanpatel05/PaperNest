import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

@Suite struct SignaturePlacementTests {
    private func signature() throws -> SavedSignature {
        try #require(SavedSignature(name: "Reusable", capturing: [
            InkStroke(tool: .pen, color: .black, width: 2,
                      points: [InkPoint(x: 0, y: 0), InkPoint(x: 200, y: 50)]),
            InkStroke(tool: .pen, color: .black, width: 2,
                      points: [InkPoint(x: 100, y: 20), InkPoint(x: 150, y: 30)])
        ]))
    }

    @Test func placementMapsDisplayedCropAndRotationToSourceAndCommitsTogether() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await store.createItem(kind: .notebook, name: "Signature", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        ], assets: [])
        var page = try await store.pages(of: item.id)[0]
        var transform = page.transform
        transform.crop = .init(x: 0.1, y: 0.2, width: 0.8, height: 0.5)
        transform.rotation = .clockwise90
        page = try await store.updateTransform(page.id, to: transform)
        let saved = try signature()
        let result = try await store.placeSignature(saved, on: page,
            target: .init(x: 0.2, y: 0.3, width: 0.4, height: 0.2))
        #expect(result.objects.count == 2)
        #expect(result.page.revision == page.revision + 1)
        #expect(try await store.objects(on: page.id) == result.objects)
        guard case .ink(let first) = result.objects[0].payload else { Issue.record("not ink"); return }
        // Displayed page is 400 × 480. Signature fits 160 × 40 at (80, 172).
        // The inverse quarter turn/crop maps these endpoints to source below.
        #expect(abs(first.points[0].x - 232) < 0.001)
        #expect(abs(first.points[0].y - 480) < 0.001)
        #expect(abs(first.points[1].x - 272) < 0.001)
        #expect(abs(first.points[1].y - 320) < 0.001)
        await #expect(throws: StoreError.pageObjectsChanged) {
            try await store.placeSignature(saved, on: page, target: .full)
        }
        #expect(try await store.objects(on: page.id) == result.objects, "a stale placement must add no partial strokes")
    }

    @Test func emptyOrInvalidSignatureCannotAdvancePageRevision() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await store.createItem(kind: .notebook, name: "Signature", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        ], assets: [])
        let page = try await store.pages(of: item.id)[0]
        let invalid = SavedSignature(name: "Invalid", strokes: [
            InkStroke(tool: .pen, color: .black, width: 2, points: [InkPoint(x: .nan, y: 0)])
        ])
        for signature in [SavedSignature(name: "Empty", strokes: []), invalid] {
            await #expect(throws: StoreError.invalidPlacement) {
                try await store.placeSignature(signature, on: page, target: .full)
            }
        }
        await #expect(throws: StoreError.invalidPlacement) {
            try await store.placeSignature(signature(), on: page, target: .exact(x: 0.9, y: 0, width: 0.4, height: 0.2))
        }
        #expect(try await store.objects(on: page.id).isEmpty)
        #expect(try await store.page(page.id) == page)
    }
}

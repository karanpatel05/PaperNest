import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

@Suite struct PageDuplicationTests {
    @Test func duplicatePreservesEditableContentAndRecognitionWithFreshIdentities() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let asset = try store.assets.store(Data("synthetic image".utf8), kind: .png, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Source", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank)),
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.grid))
        ], assets: [asset])
        let first = try #require(try await store.pages(of: item.id).first)
        let marks = [
            PageObject(pageID: first.id, zKey: "A", payload: .text(.init(frame: CGRect(x: 10, y: 20, width: 100, height: 50), text: "Editable", fontFamily: .serif, isBold: true)), modifiedAt: Date()),
            PageObject(pageID: first.id, zKey: "B", payload: .image(.init(assetID: asset.id, frame: CGRect(x: 100, y: 100, width: 40, height: 50))), modifiedAt: Date()),
            PageObject(pageID: first.id, zKey: "C", payload: .comment("Private note"), modifiedAt: Date())
        ]
        _ = try await store.applyObjectChanges(on: first.id, saving: marks, deleting: [])
        let source = try await store.updateTransform(first.id, to: .init(rotation: .clockwise90))
        let recognition = PageRecognition(pageID: source.id, sourceRevision: source.revision, engineVersion: "synthetic", status: .completed, languages: ["en-US"], lines: [.init(text: "Recognized", box: .full, confidence: 1)])
        try await store.saveRecognition(recognition)
        let change = try await store.duplicatePages([source.id], in: item.id, after: source.id)
        let copy = try #require(change.pages.first)
        let order = try await store.pages(of: item.id)
        #expect(order[0].id == source.id && order[1].id == copy.id && order.count == 3)
        #expect(copy.id != source.id && copy.transform == source.transform && copy.content == source.content)
        let copied = try await store.objects(on: copy.id)
        #expect(copied.map(\.payload) == marks.map(\.payload))
        #expect(Set(copied.map(\.id)).isDisjoint(with: marks.map(\.id)))
        #expect(try await store.recognition(for: copy.id)?.lines == recognition.lines)
        #expect(try await store.recognition(for: copy.id)?.sourceRevision == copy.revision)
        _ = try await store.applyObjectChanges(on: copy.id, saving: [], deleting: copied.map(\.id))
        #expect(try await store.objects(on: source.id) == marks)
        let reopened = try LibraryStore(directory: dir.url)
        #expect(try await reopened.pages(of: item.id).map(\.id) == order.map(\.id))
        #expect(try await reopened.assetData(asset.id).0 == Data("synthetic image".utf8))
        #expect(try await reopened.integrityCheck().isEmpty)
    }

    @Test func duplicateUndoRedoPreservesIdentitiesAndRejectsConcurrentEdits() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await store.createItem(kind: .notebook, name: "Book", pages: [
            .init(sourceSize: CGSize(width: 100, height: 200), content: .template(.lined))
        ], assets: [])
        let source = try #require(try await store.pages(of: item.id).first)
        let made = try await store.duplicatePages([source.id], in: item.id, after: source.id)
        let copy = try #require(made.pages.first)
        // Derived recognition may arrive after duplication. It survives both
        // transitions and must not make the user's Undo stop working.
        let backgroundRecognition = PageRecognition(pageID: copy.id, sourceRevision: copy.revision,
            engineVersion: "synthetic", status: .completed, languages: ["en-US"],
            lines: [.init(text: "Background result", box: .full, confidence: 1)])
        try await store.saveRecognition(backgroundRecognition)
        let hidden = try await store.toggleDuplicatedPages(made)
        #expect(hidden.isDeleted)
        #expect(try await store.pages(of: item.id).map(\.id) == [source.id])
        let restored = try await store.toggleDuplicatedPages(hidden)
        #expect(!restored.isDeleted)
        #expect(try await store.recognition(for: copy.id) == backgroundRecognition)
        #expect(try await store.pages(of: item.id).map(\.id) == [source.id, copy.id])
        let foreign = PageObject(pageID: copy.id, zKey: "V", payload: .text(.init(frame: .zero, text: "Other window")), modifiedAt: Date())
        try await store.saveObject(foreign)
        await #expect(throws: StoreError.self) { try await store.toggleDuplicatedPages(restored) }
        #expect(try await store.objects(on: copy.id) == [foreign])
        #expect(try await store.page(copy.id) != nil)
    }

    @Test func batchUsesSourceOrderAndFullyUndoneMovementDoesNotInvalidateHistory() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await store.createItem(kind: .document, name: "Batch", pages: [
            .init(sourceSize: CGSize(width: 100, height: 200), content: .template(.blank)),
            .init(sourceSize: CGSize(width: 100, height: 200), content: .template(.lined)),
            .init(sourceSize: CGSize(width: 100, height: 200), content: .template(.grid))
        ], assets: [])
        let original = try await store.pages(of: item.id)
        let change = try await store.duplicatePages([original[2].id, original[0].id], in: item.id, after: original[1].id)
        #expect(change.pages.map(\.content) == [.template(.blank), .template(.grid)])
        #expect(try await store.pages(of: item.id).map(\.id) == [original[0].id, original[1].id] + change.pages.map(\.id) + [original[2].id])
        let copied = change.pages[0]
        try await store.movePage(copied.id, toIndex: 0)
        await #expect(throws: StoreError.self) { try await store.toggleDuplicatedPages(change) }
        try await store.movePage(copied.id, toIndex: 2)
        _ = try await store.toggleDuplicatedPages(change)
        #expect(try await store.pages(of: item.id).map(\.id) == original.map(\.id))
    }

    @Test func invalidBatchAndMissingPlacedAssetRollBackAllCopies() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await store.createItem(kind: .document, name: "Source", pages: [
            .init(sourceSize: CGSize(width: 100, height: 200), content: .template(.blank)),
            .init(sourceSize: CGSize(width: 100, height: 200), content: .template(.lined))
        ], assets: [])
        let before = try await store.pages(of: item.id)
        await #expect(throws: StoreError.self) { try await store.duplicatePages([before[0].id, before[0].id], in: item.id, after: nil) }
        await #expect(throws: StoreError.self) { try await store.duplicatePages([PageID.make()], in: item.id, after: nil) }
        let missing = PageObject(pageID: before[1].id, zKey: "V", payload: .image(.init(assetID: .init(sha256: "missing"), frame: .zero)), modifiedAt: Date())
        try await store.saveObject(missing)
        let changed = try await store.pages(of: item.id)
        await #expect(throws: (any Error).self) { try await store.duplicatePages(before.map(\.id), in: item.id, after: before[1].id) }
        #expect(try await store.pages(of: item.id) == changed)
    }
}

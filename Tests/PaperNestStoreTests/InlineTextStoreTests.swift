import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

@Suite struct InlineTextStoreTests {
    @Test func styleAndWhitespaceSurviveReopenAndLegacyUpdatesPreserveTraits() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let asset = try store.assets.store(Data("synthetic".utf8), kind: .pdf, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Text", pages: samplePages(asset, count: 1), assets: [asset])
        let page = try await store.pages(of: item.id)[0]
        let frame = CGRect(x: 15, y: 35, width: 260, height: 130)
        let (_, object) = try await store.placeText("  First\nSecond\n", on: page.id, frame: frame,
            fontSize: 21, color: .black, alignment: .trailing, fontFamily: .monospaced,
            isBold: true, isItalic: true, preserveWhitespace: true)
        let reopened = try LibraryStore(directory: dir.url)
        let persisted = try #require(try await reopened.objects(on: page.id).first)
        guard case .text(let box) = persisted.payload else { Issue.record("not text"); return }
        #expect(box.text == "  First\nSecond\n")
        #expect(box.fontFamily == .monospaced && box.isBold && box.isItalic)
        #expect(box.fontSize == 21 && box.alignment == .trailing && box.frame == frame)
        let (_, edited) = try await store.updateText(object, text: "  Legacy edit  ", frame: frame,
            fontSize: 24, color: .black, alignment: .center)
        guard case .text(let updated) = edited.payload else { Issue.record("not text"); return }
        #expect(updated.text == "Legacy edit")
        #expect(updated.fontFamily == .monospaced && updated.isBold && updated.isItalic)
        await #expect(throws: StoreError.pageObjectsChanged) {
            try await store.updateText(object, text: "Stale", frame: frame, fontSize: 12, color: .black,
                alignment: .leading, fontFamily: .sans, isBold: false, isItalic: false, preserveWhitespace: true)
        }
        #expect(try await store.objects(on: page.id) == [edited])
        await #expect(throws: StoreError.invalidPlacement) {
            try await store.placeText(" \n ", on: page.id, frame: frame, fontSize: 12,
                color: .black, alignment: .leading, preserveWhitespace: true)
        }
    }
}

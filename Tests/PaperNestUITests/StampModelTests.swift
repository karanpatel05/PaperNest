import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestRender
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestUI

/// The Text Stamp sheet's model and the document's placing: a preset placed
/// in its corner and undone, one's own words kept and chosen again, the date
/// in the reader's way, a long stamp kept on the page, and an edited stamp
/// measured again.
@MainActor @Suite(.serialized) struct StampModelTests {
    private func document() async throws -> (URL, LibraryStore, DocumentModel) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestStamp-\(UUID())")
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let store = try #require(session.environment?.store)
        let asset = try store.assets.store(SyntheticDocuments.textPDF(pages: ["Invoice 1042"]), kind: .pdf, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Invoice", pages: [
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: 0)),
        ], assets: [asset])
        let document = DocumentModel(itemID: item.id, session: session)
        await document.load()
        return (root, store, document)
    }

    private func texts(_ store: LibraryStore, _ page: Page) async throws -> [TextBox] {
        try await store.objects(on: page.id).compactMap { if case .text(let box) = $0.payload { box } else { nil } }
    }

    @Test func anApprovedStampGoesTopRightAsAStampedTextBoxAndUndoTakesItAway() async throws {
        let (root, store, document) = try await document()
        defer { try? FileManager.default.removeItem(at: root) }
        let page = try #require(document.selectedPage)
        let model = StampModel(document: document, page: page)
        let preview = try #require(model.previewBox)
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()

        #expect(try await model.place(undoManager: undo))
        undo.endUndoGrouping()

        let placed = try await texts(store, page)
        #expect(placed.count == 1)
        let stamp = try #require(placed.first)
        #expect(stamp.stamp == .outlined && stamp.text == L10n.exportWatermarkWordApproved && stamp.isBold)
        #expect(stamp.color == StampPreset.approved.color)
        #expect(stamp.frame == preview.frame, "placed where the preview showed")
        #expect(abs(stamp.frame.maxX - (612 - 30.6)) < 0.01 && abs(stamp.frame.minY - 30.6) < 0.01, "top right")

        undo.undo()
        for _ in 0..<100 where try await !texts(store, page).isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(try await texts(store, page).isEmpty)
        undo.redo()
        for _ in 0..<100 where try await texts(store, page).isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(try await texts(store, page).first?.stamp == .outlined)
    }

    @Test func ownWordsKeptAreSavedAndChoosingThemAgainBringsTheirDate() async throws {
        let (root, store, document) = try await document()
        defer { try? FileManager.default.removeItem(at: root) }
        let page = try #require(document.selectedPage)
        let model = StampModel(document: document, page: page)
        model.choose(.custom)
        model.customText = "Checked by Ana"
        model.customStyle = .filled
        model.customColor = .red
        model.includesDate = true
        model.keepsCustom = true

        #expect(try await model.place(undoManager: nil))

        let saved = try await store.savedStamps()
        #expect(saved.map(\.design) == [StampDesign(text: "Checked by Ana", style: .filled,
                                                    color: StampColor.red.rgba, includesDate: true)])
        let placed = try #require(try await texts(store, page).first)
        #expect(placed.text.hasPrefix("Checked by Ana\n") && placed.stamp == .filled)

        let again = StampModel(document: document, page: page)
        await again.loadSaved()
        #expect(!again.includesDate)
        again.choose(.saved(try #require(saved.first).id))
        #expect(again.includesDate, "a saved stamp brings its date setting")
        #expect(again.design?.text == "Checked by Ana" && again.design?.style == .filled)

        await again.deleteSaved(try #require(again.saved.first))
        #expect(try await store.savedStamps().isEmpty)
        #expect(again.choice == .preset(.approved))
        #expect(try await texts(store, page).count == 1, "the placed stamp stays")
    }

    /// One's own words not kept are placed and not saved.
    @Test func ownWordsNotKeptAreNotSaved() async throws {
        let (root, store, document) = try await document()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = StampModel(document: document, page: try #require(document.selectedPage))
        model.choose(.custom)
        model.customText = "Filed"
        #expect(try await model.place(undoManager: nil))
        #expect(try await store.savedStamps().isEmpty)
    }

    @Test func thereIsNothingToPlaceWithoutWords() async throws {
        let (root, store, document) = try await document()
        defer { try? FileManager.default.removeItem(at: root) }
        let page = try #require(document.selectedPage)
        let model = StampModel(document: document, page: page)
        model.choose(.custom)
        model.customText = " \n "

        #expect(model.design == nil && model.previewBox == nil)
        #expect(try await !model.place(undoManager: nil))
        #expect(try await texts(store, page).isEmpty)
    }

    @Test func theDateIsWrittenInTheReadersWay() async throws {
        let (root, _, document) = try await document()
        defer { try? FileManager.default.removeItem(at: root) }
        let page = try #require(document.selectedPage)
        let design = StampDesign(text: "APPROUVÉ", style: .outlined, color: StampPreset.approved.color, includesDate: true)
        let day = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 12)))

        let french = DocumentModel.stampBox(design, size: .medium, placement: .topRight, on: page, date: day,
                                            locale: Locale(identifier: "fr_FR"))
        let american = DocumentModel.stampBox(design, size: .medium, placement: .topRight, on: page, date: day,
                                              locale: Locale(identifier: "en_US"))

        #expect(french.text == "APPROUVÉ\n17 nov. 2026")
        #expect(american.text == "APPROUVÉ\nNov 17, 2026")
    }

    /// Forty wide letters at the large size would run off the page: the type
    /// gets smaller instead, and the stamp stays inside the page as shown.
    @Test func aLongStampGetsSmallerTypeToStayOnThePage() async throws {
        let (root, _, document) = try await document()
        defer { try? FileManager.default.removeItem(at: root) }
        let page = try #require(document.selectedPage)
        let design = StampDesign(text: String(repeating: "W", count: 40), style: .outlined, color: .black)

        let box = DocumentModel.stampBox(design, size: .large, placement: .center, on: page, date: .now)

        #expect(box.fontSize < StampSize.large.fontSize(on: page.geometry.pageSize))
        #expect(box.frame.width <= 612 * 0.9 + 1)
        #expect(CGRect(x: 0, y: 0, width: 612, height: 792).contains(box.frame))
        let mids = PageRenderer.textSelectionRects(box).map(\.midY)
        #expect((mids.max() ?? 0) - (mids.min() ?? 0) < box.fontSize * 0.5, "still one line")
    }

    /// Changed through the text box editor, a stamp is measured again so its
    /// border fits its new words, and it stays where it was.
    @Test func editingAStampsWordsMeasuresItAgain() async throws {
        let (root, store, document) = try await document()
        defer { try? FileManager.default.removeItem(at: root) }
        let page = try #require(document.selectedPage)
        #expect(try await StampModel(document: document, page: page).place(undoManager: nil))
        let object = try #require(try await store.objects(on: page.id).first)
        guard case .text(let before) = object.payload else { Issue.record("not a text box"); return }
        let current = try #require(document.pages.first { $0.id == page.id })

        try await document.editTextBox(object, on: current, text: "APPROVED BY THE BOARD", fontSize: before.fontSize,
                                       color: before.color, alignment: .center, undoManager: nil)

        let after = try #require(try await texts(store, page).first)
        #expect(after.stamp == .outlined)
        #expect(after.frame.origin == before.frame.origin)
        #expect(after.frame.width > before.frame.width + 50)
        #expect(after.frame.size == PageRenderer.stampSize(for: after))
    }
}

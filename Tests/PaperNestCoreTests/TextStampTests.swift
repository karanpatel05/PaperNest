import CoreGraphics
import Foundation
import Testing
@testable import PaperNestCore

/// Text stamps: an ordinary text box with a stamp style, the presets, the
/// wording kept to one line, and where a stamp lands on the page as shown.
@Suite struct TextStampTests {
    // MARK: - Stored form

    /// A box with no stamp is stored exactly as before: no new key, so
    /// nothing that reads the stored form sees a difference.
    @Test func anOrdinaryTextBoxIsStoredWithoutAStampKey() throws {
        let box = TextBox(frame: CGRect(x: 1, y: 2, width: 30, height: 10), text: "Note")
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(box)) as? [String: Any])
        #expect(Set(json.keys) == ["frame", "text", "fontSize", "color", "alignment", "fontFamily", "isBold", "isItalic"])
    }

    @Test func aStampSurvivesARoundTripAndAnOldBoxReadsAsPlain() throws {
        let stamp = TextBox(frame: CGRect(x: 1, y: 2, width: 90, height: 30), text: "PAID", fontSize: 20,
                            alignment: .center, isBold: true, stamp: .outlined)
        #expect(try JSONDecoder().decode(TextBox.self, from: JSONEncoder().encode(stamp)) == stamp)

        let old = #"{"frame":[[1,2],[30,10]],"text":"Note","fontSize":14,"color":{"red":0,"green":0,"blue":0,"alpha":1},"alignment":"leading"}"#
        #expect(try JSONDecoder().decode(TextBox.self, from: Data(old.utf8)).stamp == nil)
    }

    /// A style a later build adds is read as plain text, not as a page that
    /// fails to open.
    @Test func anUnknownStampStyleReadsAsPlainText() throws {
        let later = #"{"frame":[[1,2],[30,10]],"text":"OK","fontSize":14,"color":{"red":0,"green":0,"blue":0,"alpha":1},"alignment":"center","stamp":"seal"}"#
        let box = try JSONDecoder().decode(TextBox.self, from: Data(later.utf8))
        #expect(box.stamp == nil)
        #expect(box.text == "OK")
    }

    // MARK: - Design

    @Test func theWordingIsOneTidyLineOfAtMostFortyCharacters() {
        let design = StampDesign(text: "  Checked\nby   Ana \t ", style: .outlined, color: .black)
        #expect(design.text == "Checked by Ana")
        #expect(StampDesign(text: String(repeating: "é", count: 60), style: .filled, color: .black).text.count == 40)
        #expect(StampDesign(text: " \n ", style: .filled, color: .black).isEmpty)
    }

    @Test func theDateIsTheSecondLineAndTheBoxIsABoldCentredStamp() {
        let design = StampDesign(text: "APPROVED", style: .outlined, color: StampPreset.approved.color, includesDate: true)
        let box = design.textBox(dateLine: "17 Nov 2026", fontSize: 20)
        #expect(box.text == "APPROVED\n17 Nov 2026")
        #expect(box.stamp == .outlined && box.isBold && box.alignment == .center && box.fontFamily == .sans)
        #expect(box.color == StampPreset.approved.color)
        #expect(design.textBox(dateLine: nil, fontSize: 20).text == "APPROVED")
        #expect(design.textBox(dateLine: " \n", fontSize: 20).text == "APPROVED", "an empty date line is none")
    }

    @Test func aSavedDesignReadsBackTidied() throws {
        let design = StampDesign(text: "Checked by Ana", style: .filled, color: StampPreset.reviewed.color, includesDate: true)
        #expect(try JSONDecoder().decode(StampDesign.self, from: JSONEncoder().encode(design)) == design)
        let untidy = #"{"text":"Two\nlines","style":"outlined","color":{"red":0,"green":0,"blue":0,"alpha":1}}"#
        let read = try JSONDecoder().decode(StampDesign.self, from: Data(untidy.utf8))
        #expect(read.text == "Two lines" && !read.includesDate)
    }

    @Test func draftIsALabelAndEveryOtherPresetARubberStamp() {
        #expect(StampPreset.allCases.filter { $0.style == .filled } == [.draft])
        #expect(StampPreset.approved.color == StampPreset.paid.color)
        #expect(StampPreset.rejected.color == StampPreset.confidential.color)
        #expect(Set(StampPreset.allCases.map(\.color)).count == 4)
    }

    /// The words sit inside the border and the padding, which grow with the type.
    @Test func theContentSitsInsideTheBorderAndPadding() {
        var box = TextBox(frame: CGRect(x: 100, y: 100, width: 200, height: 60), text: "PAID", fontSize: 20, stamp: .outlined)
        let line = box.stampLineWidth, pad = box.stampPadding
        #expect(box.stampContentRect == CGRect(x: pad.width + line, y: pad.height + line,
                                               width: 200 - 2 * (pad.width + line), height: 60 - 2 * (pad.height + line)))
        box.stamp = .filled
        #expect(box.stampPadding.width > pad.width, "its ends are round")
        #expect(box.stampContentRect.minX == box.stampPadding.width, "a filled stamp has no border to clear")
        #expect(box.stampCornerRadius == 30, "fully rounded")
    }

    @Test func sizesGrowWithThePage() {
        let letter = CGSize(width: 612, height: 792)
        let sizes = StampSize.allCases.map { $0.fontSize(on: letter) }
        #expect(sizes == sizes.sorted() && Set(sizes).count == 3)
        #expect(abs(StampSize.medium.fontSize(on: letter) - 19.584) < 0.001)
        #expect(StampSize.medium.fontSize(on: CGSize(width: 1224, height: 1584)) == 2 * StampSize.medium.fontSize(on: letter))
    }

    // MARK: - Placement

    private let size = CGSize(width: 120, height: 40)

    @Test func aStampGoesInTheCornerOfAnUprightPage() {
        let geometry = PageGeometry(sourceSize: CGSize(width: 600, height: 800))
        let margin: CGFloat = 30
        #expect(StampPlacement.topRight.frame(size: size, on: geometry) == CGRect(x: 600 - margin - 120, y: margin, width: 120, height: 40))
        #expect(StampPlacement.bottomRight.frame(size: size, on: geometry)
                == CGRect(x: 600 - margin - 120, y: 800 - margin - 40, width: 120, height: 40))
        #expect(StampPlacement.center.frame(size: size, on: geometry) == CGRect(x: 240, y: 380, width: 120, height: 40))
    }

    /// On a cropped page the corner is the corner of what is shown.
    @Test func aStampGoesInTheCornerOfWhatACroppedPageShows() {
        let geometry = PageGeometry(sourceSize: CGSize(width: 600, height: 800),
                                    crop: NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5))
        let frame = StampPlacement.topRight.frame(size: size, on: geometry)
        let shown = geometry.cropRect
        #expect(shown.contains(frame))
        #expect(abs(frame.maxX - (shown.maxX - 15)) < 0.001 && abs(frame.minY - (shown.minY + 15)) < 0.001)
    }

    /// On a turned page, the stamp lands in the corner the reader sees.
    @Test func aStampGoesInTheShownCornerOfATurnedPage() {
        let geometry = PageGeometry(sourceSize: CGSize(width: 600, height: 800), rotation: .clockwise90)
        let frame = StampPlacement.topRight.frame(size: size, on: geometry)
        #expect(frame.size == size)
        let onPage = frame.applying(geometry.sourceToPage)
        let page = geometry.pageSize
        #expect(abs(onPage.maxX - (page.width - 30)) < 0.001, "against the right as shown")
        #expect(abs(onPage.minY - 30) < 0.001, "against the top as shown")
        #expect(CGRect(origin: .zero, size: geometry.sourceSize).contains(frame))
    }

    @Test func aStampWiderThanTheRoomStartsAtTheEdge() {
        let geometry = PageGeometry(sourceSize: CGSize(width: 100, height: 100))
        let frame = StampPlacement.topRight.frame(size: CGSize(width: 150, height: 20), on: geometry)
        #expect(frame.minX == 0)
    }
}

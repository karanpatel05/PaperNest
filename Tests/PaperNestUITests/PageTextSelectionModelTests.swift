import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestUI

/// Selecting text as a finger or a pointer does it: press, drag, let go.
@MainActor @Suite struct PageTextSelectionModelTests {
    private typealias Fragment = PageTextLayout.Fragment

    private func characters(_ text: String, y: Double) -> PageTextLayout.Line {
        var fragments: [Fragment] = []
        var column = 0
        for character in text {
            if character == " " {
                if !fragments.isEmpty { fragments[fragments.count - 1].spaceAfter = true }
            } else {
                fragments.append(Fragment(text: String(character),
                                          box: .exact(x: 0.1 + Double(column) * 0.02, y: y, width: 0.02, height: 0.03)))
            }
            column += 1
        }
        return PageTextLayout.Line(fragments: fragments, origin: .embedded)
    }

    private var page: PageTextLayout {
        PageTextLayout(lines: [characters("cat hat", y: 0.10), characters("big dog", y: 0.20)])
    }

    private func point(column: Int, y: Double) -> CGPoint {
        CGPoint(x: 0.1 + Double(column) * 0.02 + 0.01, y: y + 0.015)
    }

    private func model() -> PageTextSelectionModel {
        let model = PageTextSelectionModel()
        model.show(page, on: PageID(rawValue: "p1"))
        return model
    }

    @Test func aFingerStartsWithTheWordUnderIt() {
        let selection = model()

        #expect(selection.begin(at: point(column: 5, y: 0.10), grain: .word, reach: 0.05))

        #expect(selection.text == "hat")
        #expect(selection.isDragging)
        #expect(selection.boxes.count == 1)
    }

    @Test func aPointerStartsWithTheLetterUnderIt() {
        let selection = model()

        selection.begin(at: point(column: 5, y: 0.10), grain: .character, reach: 0.05)

        #expect(selection.text == "a")
    }

    @Test func draggingOnExtendsTheSelectionAcrossLines() {
        let selection = model()
        selection.begin(at: point(column: 5, y: 0.10), grain: .word, reach: 0.05)

        selection.extend(to: point(column: 2, y: 0.20))
        selection.end()

        #expect(selection.text == "hat\nbig")
        #expect(selection.boxes.count == 2)
        #expect(!selection.isDragging)
        #expect(selection.hasSelection)
    }

    /// Dragging back past where the press began turns the selection round;
    /// the word it began on stays in it.
    @Test func draggingBackwardsKeepsTheWordItBeganOn() {
        let selection = model()
        selection.begin(at: point(column: 1, y: 0.20), grain: .word, reach: 0.05)

        selection.extend(to: point(column: 1, y: 0.10))

        #expect(selection.text == "at hat\nbig")
    }

    @Test func aPressAwayFromAnyTextSelectsNothingAndClearsWhatWasSelected() {
        let selection = model()
        selection.selectWord(at: point(column: 0, y: 0.10), reach: 0.05)
        #expect(selection.text == "cat")

        #expect(!selection.begin(at: CGPoint(x: 0.5, y: 0.8), grain: .word, reach: 0.05))

        #expect(!selection.hasSelection)
        #expect(selection.text.isEmpty)
        #expect(!selection.isDragging)
    }

    @Test func selectAllTakesTheWholePage() {
        let selection = model()

        selection.selectAll()

        #expect(selection.text == "cat hat\nbig dog")
    }

    /// The range is positions in one page's words. On another page — or the
    /// same page once its words changed — it would point at other text.
    @Test func aSelectionDoesNotSurviveADifferentPageOrDifferentWords() {
        let selection = model()
        selection.selectAll()

        selection.show(page, on: PageID(rawValue: "p1"))
        #expect(selection.hasSelection, "showing the same page again dropped the selection")

        selection.show(page, on: PageID(rawValue: "p2"))
        #expect(!selection.hasSelection)

        selection.selectAll()
        selection.show(PageTextLayout(lines: [characters("new words", y: 0.1)]), on: PageID(rawValue: "p2"))
        #expect(!selection.hasSelection)
    }

    /// A typed text box is edited in its own way and is not page text.
    @Test func typedTextBoxesCannotBeSelected() {
        let selection = PageTextSelectionModel()
        selection.show(PageTextLayout(lines: [
            characters("cat", y: 0.10),
            PageTextLayout.Line(fragments: [Fragment(text: "a note", box: .exact(x: 0.1, y: 0.5, width: 0.3, height: 0.1))],
                                origin: .typed),
        ]), on: PageID(rawValue: "p1"))

        #expect(!selection.begin(at: CGPoint(x: 0.2, y: 0.55), grain: .word, reach: 0.05))
        selection.selectAll()
        #expect(selection.text == "cat")
    }
}

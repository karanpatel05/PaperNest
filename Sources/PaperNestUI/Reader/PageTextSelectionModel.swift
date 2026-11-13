import CoreGraphics
import Foundation
import Observation
import PaperNestCore

/// The text selected on the page being read.
///
/// It holds the page's selectable words — the file's own and recognised
/// ones, not typed text boxes, which are edited in their own way — and a
/// range of them. Points come in normalized to the upright source, the space
/// the words' boxes are in; the overlay does that mapping, so nothing here
/// knows about zoom, crop or rotation.
@MainActor @Observable
final class PageTextSelectionModel {
    /// How much the first touch takes.
    enum Grain {
        /// A pointer: the selection starts at the letter under it.
        case character
        /// A finger: the selection starts as the word under it.
        case word
    }

    private(set) var pageID: PageID?
    private(set) var layout = PageTextLayout.empty
    private(set) var range: ClosedRange<Int>?
    /// True from the first touch until the finger or the button comes up.
    /// The actions wait for that, so they are not chased around the page.
    private(set) var isDragging = false
    /// What the drag began on. The selection always contains it, so dragging
    /// back past the start turns the selection round instead of losing it.
    private var anchor: ClosedRange<Int>?

    var hasSelection: Bool { range != nil }
    var text: String { range.map { layout.text(in: $0) } ?? "" }
    var boxes: [NormalizedRect] { range.map { layout.boxes(in: $0) } ?? [] }

    /// Gives the model the words of the page now on screen. A different page,
    /// or the same page with different words, drops the selection: its range
    /// would point at other text.
    func show(_ layout: PageTextLayout, on pageID: PageID) {
        let selectable = layout.excluding(.typed)
        guard pageID != self.pageID || selectable != self.layout else { return }
        self.pageID = pageID
        self.layout = selectable
        clear()
    }

    /// Starts a selection at `point`. False, and nothing selected, when there
    /// is no text within `reach` of it — a press on an empty margin is not
    /// asking for the nearest word half a page away.
    @discardableResult
    func begin(at point: CGPoint, grain: Grain, reach: Double) -> Bool {
        guard let index = layout.fragmentIndex(nearest: point, within: reach) else {
            clear()
            return false
        }
        let start = grain == .word ? layout.wordRange(around: index) : index...index
        anchor = start
        range = start
        isDragging = true
        return true
    }

    /// Stretches the selection from where it began to `point`.
    func extend(to point: CGPoint) {
        guard let anchor, let index = layout.fragmentIndex(nearest: point) else { return }
        range = min(anchor.lowerBound, index)...max(anchor.upperBound, index)
    }

    func end() {
        isDragging = false
    }

    /// The word at `point`, as a double click or double tap asks for.
    @discardableResult
    func selectWord(at point: CGPoint, reach: Double) -> Bool {
        guard begin(at: point, grain: .word, reach: reach) else { return false }
        end()
        return true
    }

    func selectAll() {
        let count = layout.fragmentCount
        guard count > 0 else { return }
        anchor = 0...(count - 1)
        range = anchor
        isDragging = false
    }

    func clear() {
        range = nil
        anchor = nil
        isDragging = false
    }
}

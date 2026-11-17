import CoreGraphics
import Testing
@testable import PaperNestCore

/// Where each paper's lines and headings go.
@Suite struct PageTemplateLayoutTests {
    private let a4 = CGSize(width: 595.28, height: 841.89)

    /// Lined paper keeps exactly the rules it always had: every 24 points
    /// from 72 down, edge to edge. Existing notebooks, their exports and
    /// their redactions must draw the same.
    @Test func linedPaperIsUnchanged() {
        let layout = PageTemplateLayout.layout(for: .lined, size: a4)
        #expect(layout.segments.count == 33)
        #expect(layout.segments.first == .init(CGPoint(x: 0, y: 72), CGPoint(x: a4.width, y: 72)))
        #expect(layout.segments.last == .init(CGPoint(x: 0, y: 840), CGPoint(x: a4.width, y: 840)))
        #expect(layout.segments.allSatisfy { $0.from.y == $0.to.y })
        #expect(layout.dots.isEmpty && layout.boxes.isEmpty && layout.headings.isEmpty)
    }

    /// Grid paper too: every 18 points across and down, edge to edge.
    @Test func gridPaperIsUnchanged() {
        let layout = PageTemplateLayout.layout(for: .grid, size: a4)
        let rows = layout.segments.filter { $0.from.y == $0.to.y }
        let columns = layout.segments.filter { $0.from.x == $0.to.x }
        #expect(rows.count == 46 && columns.count == 33)
        #expect(rows.first?.from.y == 18 && rows.last?.from.y == 828)
        #expect(columns.first?.from.x == 18 && columns.last?.from.x == 594)
        #expect(rows.allSatisfy { $0.from.x == 0 && $0.to.x == a4.width })
    }

    @Test func blankPaperHasNothing() {
        #expect(PageTemplateLayout.layout(for: .blank, size: a4).isEmpty)
    }

    @Test func dottedPaperIsADotAtEveryGridCrossing() {
        let layout = PageTemplateLayout.layout(for: .dotted, size: a4)
        #expect(layout.dots.count == 33 * 46)
        #expect(layout.segments.isEmpty)
    }

    /// Every paper but blank prints something, and all of it is on the page.
    @Test(arguments: PageTemplate.allCases)
    func everyPaperStaysOnThePage(_ template: PageTemplate) {
        let layout = PageTemplateLayout.layout(for: template, size: a4)
        #expect(layout.isEmpty == (template == .blank))
        // A rule may end on the page's edge, which `contains` leaves out.
        let page = CGRect(origin: .zero, size: a4).insetBy(dx: -0.01, dy: -0.01)
        for segment in layout.segments {
            #expect(page.contains(segment.from) && page.contains(segment.to), "\(template): \(segment)")
        }
        #expect(layout.dots.allSatisfy { page.contains($0) })
        #expect(layout.boxes.allSatisfy { page.contains($0) })
        #expect(layout.headings.allSatisfy { page.contains($0.frame) })
    }

    @Test func aMeetingPageHasItsHeadingsInOrderAndApart() {
        let headings = PageTemplateLayout.layout(for: .meeting, size: a4).headings
        #expect(headings.map(\.role) == [.meetingTitle, .date, .attendees, .notes, .actionItems])
        #expect(headings[0].isBold && headings[0].fontSize > headings[1].fontSize, "the title is the largest")
        for (i, a) in headings.enumerated() {
            for b in headings[(i + 1)...] { #expect(!a.frame.intersects(b.frame), "\(a.role) overlaps \(b.role)") }
        }
    }

    @Test func aPlannerHasAWeekOfDaysAndNotes() {
        let layout = PageTemplateLayout.layout(for: .planner, size: a4)
        #expect(layout.headings.map(\.role) == [.weekOf] + (0..<7).map { .day($0) } + [.plannerNotes])
        #expect(layout.boxes.count == 8)
        for (i, a) in layout.boxes.enumerated() {
            for b in layout.boxes[(i + 1)...] { #expect(!a.intersects(b)) }
        }
        // Each day's heading is inside its own box.
        for (index, heading) in layout.headings.dropFirst().enumerated() {
            #expect(layout.boxes[index].contains(heading.frame))
        }
    }

    /// Papers without words have no headings: nothing to translate.
    @Test(arguments: [PageTemplate.blank, .lined, .grid, .dotted, .cornell, .checklist, .form])
    func papersWithoutWordsHaveNoHeadings(_ template: PageTemplate) {
        #expect(PageTemplateLayout.layout(for: template, size: a4).headings.isEmpty)
    }

    @Test func aChecklistRowIsABoxAndARule() {
        let layout = PageTemplateLayout.layout(for: .checklist, size: a4)
        #expect(!layout.boxes.isEmpty)
        #expect(layout.segments.count == layout.boxes.count + 1, "a title rule, and one rule per box")
    }

    @Test func aTinyPageGetsNothingRatherThanLinesOffIt() {
        #expect(PageTemplateLayout.layout(for: .meeting, size: CGSize(width: 50, height: 50)).isEmpty)
    }
}

import CoreGraphics
import Foundation

/// Where a paper's printed lines go: rules, dots, boxes, and the places its
/// headings are written. In the page's source space (points, top-left
/// origin, y down), for any page size; notebook pages are A4.
///
/// The one source of a paper's geometry: the renderer draws these lines on
/// screen and into every export, and a new page's headings are placed in
/// these frames. Lined and grid paper keep exactly the lines they always had,
/// so existing notebooks, their exports and their redactions draw the same.
///
/// **Headings are not drawn here.** They are words, so they are written onto
/// a new page as ordinary text boxes in the reader's language (see
/// `Heading`), which can be edited, moved or deleted like anything typed.
public struct PageTemplateLayout: Equatable, Sendable {
    public struct Segment: Equatable, Sendable {
        public var from: CGPoint
        public var to: CGPoint

        public init(_ from: CGPoint, _ to: CGPoint) {
            self.from = from
            self.to = to
        }
    }

    /// What a heading says, so the caller can write it in the reader's language.
    public enum HeadingRole: Hashable, Sendable {
        case meetingTitle, date, attendees, notes, actionItems
        case weekOf
        /// The day in that position of the week (0 is the week's first day,
        /// which depends on the reader's calendar).
        case day(Int)
        case plannerNotes
    }

    public struct Heading: Equatable, Sendable {
        public var role: HeadingRole
        public var frame: CGRect
        public var fontSize: Double
        public var isBold: Bool
    }

    public var segments: [Segment] = []
    public var dots: [CGPoint] = []
    /// Outlined rectangles: checkboxes, a planner's days.
    public var boxes: [CGRect] = []
    public var headings: [Heading] = []

    public static let margin: CGFloat = 40
    public static let dotRadius: CGFloat = 0.9
    /// Grey, like printed labels: a heading is a guide, not the page's text.
    public static let headingGray = 0.45

    public var isEmpty: Bool { segments.isEmpty && dots.isEmpty && boxes.isEmpty }

    public static func layout(for template: PageTemplate, size: CGSize) -> PageTemplateLayout {
        var layout = PageTemplateLayout()
        let w = size.width, h = size.height, m = margin
        guard w > 2 * m, h > 2 * m else { return layout }
        func rule(_ y: CGFloat, _ x0: CGFloat = 0, _ x1: CGFloat? = nil) {
            layout.segments.append(Segment(CGPoint(x: x0, y: y), CGPoint(x: x1 ?? w, y: y)))
        }
        func heading(_ role: HeadingRole, _ frame: CGRect, size: Double = 10, bold: Bool = false) {
            layout.headings.append(Heading(role: role, frame: frame, fontSize: size, isBold: bold))
        }
        func checkRow(_ y: CGFloat, box side: CGFloat) {
            layout.boxes.append(CGRect(x: m, y: y - side, width: side, height: side))
            rule(y, m + side + 8, w - m)
        }

        switch template {
        case .blank:
            break
        case .lined:
            for y in stride(from: CGFloat(72), to: h, by: 24) { rule(y) }
        case .grid:
            for y in stride(from: CGFloat(18), to: h, by: 18) { rule(y) }
            for x in stride(from: CGFloat(18), to: w, by: 18) {
                layout.segments.append(Segment(CGPoint(x: x, y: 0), CGPoint(x: x, y: h)))
            }
        case .dotted:
            for y in stride(from: CGFloat(18), to: h, by: 18) {
                for x in stride(from: CGFloat(18), to: w, by: 18) { layout.dots.append(CGPoint(x: x, y: y)) }
            }
        case .cornell:
            // A title band, a cue column of about 30%, and a summary across
            // the last fifth, ruled throughout.
            let cue = (w * 0.3).rounded(), summary = (h * 0.8).rounded()
            rule(96)
            layout.segments.append(Segment(CGPoint(x: cue, y: 96), CGPoint(x: cue, y: summary)))
            for y in stride(from: CGFloat(120), to: summary - 4, by: 24) { rule(y) }
            rule(summary)
            for y in stride(from: summary + 24, to: h - 20, by: 24) { rule(y) }
        case .checklist:
            rule(72, m, w - m)
            for y in stride(from: CGFloat(112), through: h - 40, by: 30) { checkRow(y, box: 12) }
        case .meeting:
            heading(.meetingTitle, CGRect(x: m, y: 34, width: w - 2 * m, height: 18), size: 13, bold: true)
            rule(76, m, w - m)
            let split = m + 170
            heading(.date, CGRect(x: m, y: 88, width: 150, height: 14))
            heading(.attendees, CGRect(x: split, y: 88, width: w - m - split, height: 14))
            rule(118, m, m + 150)
            rule(118, split, w - m)
            let actions = h - 230
            heading(.notes, CGRect(x: m, y: 134, width: w - 2 * m, height: 14))
            for y in stride(from: CGFloat(172), to: actions - 8, by: 24) { rule(y, m, w - m) }
            heading(.actionItems, CGRect(x: m, y: actions, width: w - 2 * m, height: 14))
            for y in stride(from: actions + 36, through: h - 30, by: 28) { checkRow(y, box: 11) }
        case .planner:
            heading(.weekOf, CGRect(x: m, y: 34, width: w - 2 * m, height: 14))
            rule(66, m, w - m)
            // Two columns of four: the seven days in reading order, then notes.
            let top: CGFloat = 84, bottom = h - 36, gap: CGFloat = 10
            let cellWidth = (w - 2 * m - gap) / 2, cellHeight = (bottom - top - 3 * gap) / 4
            for index in 0..<8 {
                let cell = CGRect(x: m + CGFloat(index % 2) * (cellWidth + gap),
                                  y: top + CGFloat(index / 2) * (cellHeight + gap),
                                  width: cellWidth, height: cellHeight)
                layout.boxes.append(cell)
                heading(index < 7 ? .day(index) : .plannerNotes,
                        CGRect(x: cell.minX + 8, y: cell.minY + 6, width: cell.width - 16, height: 14), bold: true)
                for y in stride(from: cell.minY + 42, to: cell.maxY - 8, by: 22) { rule(y, cell.minX + 8, cell.maxX - 8) }
            }
        case .form:
            // A title, then rows of a short label rule and a long answer rule.
            rule(72, m, w - m)
            for y in stride(from: CGFloat(120), through: h - 60, by: 40) {
                rule(y, m, m + 150)
                rule(y, m + 166, w - m)
            }
        }
        return layout
    }
}

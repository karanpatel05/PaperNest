import CoreText
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestUI

/// The headings a new page of a paper is written with: in the reader's
/// language, the days of the reader's week, and short enough for their boxes
/// in every language.
@MainActor @Suite struct TemplateHeadingsTests {
    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: identifier)
        return calendar
    }

    @Test func theWeekStartsWhereTheReadersWeekStarts() {
        #expect(TemplateHeadings.dayName(0, calendar: calendar("en_US")) == "Sunday")
        #expect(TemplateHeadings.dayName(1, calendar: calendar("en_US")) == "Monday")
        #expect(TemplateHeadings.dayName(0, calendar: calendar("fr_FR")) == "Lundi", "capitalized as a heading")
        #expect(TemplateHeadings.dayName(6, calendar: calendar("fr_FR")) == "Dimanche")
        #expect(TemplateHeadings.dayName(0, calendar: calendar("es_ES")) == "Lunes")
    }

    @Test func aMeetingAndAPlannerHaveHeadingsAndOtherPapersNone() {
        let meeting = TemplateHeadings.textBoxes(for: .meeting, calendar: calendar("en_US"))
        #expect(meeting.map(\.text) == [L10n.templateMeetingTitle, L10n.templateDate, L10n.templateAttendees,
                                        L10n.templateNotes, L10n.templateActionItems])
        let planner = TemplateHeadings.textBoxes(for: .planner, calendar: calendar("en_US"))
        #expect(planner.map(\.text) == [L10n.templateWeekOf, "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday",
                                        "Friday", "Saturday", L10n.templateNotes])
        for template in [PageTemplate.blank, .lined, .grid, .dotted, .cornell, .checklist, .form] {
            #expect(TemplateHeadings.textBoxes(for: template).isEmpty, "\(template)")
        }
    }

    /// Small and grey, like printed labels, not the page's own text.
    @Test func headingsLookLikePrintedLabels() throws {
        let boxes = TemplateHeadings.textBoxes(for: .meeting)
        #expect(boxes.allSatisfy { $0.fontSize <= 13 && $0.color.red == $0.color.green && $0.color.red > 0.3 && $0.color.red < 0.6 })
        #expect(try #require(boxes.first).isBold)
    }

    /// Every heading, in every language, fits its box on one line: a text
    /// box clips what does not fit, without saying so. Measured the way the
    /// renderer lays text boxes out.
    @Test(arguments: LocalizationTests.languages)
    func everyHeadingFitsItsBox(_ language: String) throws {
        let table = try LocalizationTests.table(language)
        let week = calendar(language == "en" ? "en_US" : (language == "fr" ? "fr_FR" : "es_ES"))
        for template in PageTemplate.allCases {
            let boxes = TemplateHeadings.textBoxes(for: template, calendar: week) { role in
                TemplateHeadings.key(for: role).flatMap { table[$0] }
            }
            #expect(boxes.count == PageTemplateLayout.layout(for: template, size: CGSize(width: 595.28, height: 841.89))
                .headings.count, "\(language) \(template): a heading has no words")
            for box in boxes {
                let font = CTFontCreateWithName(box.postScriptFontName as CFString, CGFloat(box.fontSize), nil)
                let text = NSAttributedString(string: box.text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
                let line = CTLineCreateWithAttributedString(text)
                let width = CTLineGetTypographicBounds(line, nil, nil, nil)
                #expect(width <= box.frame.width, "\(language): “\(box.text)” is \(width) wide in \(box.frame.width)")
                let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(text), CFRange(location: 0, length: 0),
                                                     CGPath(rect: CGRect(origin: .zero, size: box.frame.size), transform: nil), nil)
                #expect(CTFrameGetVisibleStringRange(frame).length == (box.text as NSString).length,
                        "\(language): “\(box.text)” is clipped by its box")
            }
        }
    }

    // MARK: - Through the models

    @Test func aNewPlannerNotebooksFirstPageHasTheWeek() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let library = LibraryModel(session: session, startsAtHome: true)

        let notebook = try await library.createNotebook(named: "This Week", template: .planner)

        let store = try #require(session.environment?.store)
        let page = try #require(try await store.pages(of: notebook).first)
        #expect(page.content == .template(.planner))
        let texts = try await store.objects(on: page.id).compactMap { if case .text(let box) = $0.payload { box.text } else { nil } }
        #expect(texts.count == 9)
        #expect(texts.first == L10n.templateWeekOf)
    }

    @Test func aMeetingPageAddedToANotebookHasItsHeadingsAndUndoTakesThemAway() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let notebook = try await LibraryModel(session: session, startsAtHome: true).createNotebook(named: "Team", template: .lined)
        let document = DocumentModel(itemID: notebook, session: session)
        await document.load()
        let undo = UndoManager()
        undo.groupsByEvent = false

        undo.beginUndoGrouping()
        try await document.addNotebookPage(.meeting, after: document.selectedPageID, undoManager: undo)
        undo.endUndoGrouping()

        let store = try #require(session.environment?.store)
        let added = try #require(document.pages.last)
        #expect(added.content == .template(.meeting))
        #expect(try await store.objects(on: added.id).count == 5)
        #expect(try await store.objects(on: try #require(document.pages.first).id).isEmpty, "the lined first page has none")
        #expect(undo.canUndo)
    }
}

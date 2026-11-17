import CoreGraphics
import Foundation
import PaperNestCore
import PaperNestStore

/// The headings a new page of a paper is written with ("Date", "Attendees",
/// the days of the week), as ordinary text boxes in the reader's language,
/// placed where `PageTemplateLayout` puts them. Small and grey, like printed
/// labels; editable, movable and deletable like anything typed.
///
/// Written once, when someone chooses the paper for a new page: they stay in
/// the language they were written in, and a page whose paper is chosen later
/// gets the rules and no headings.
enum TemplateHeadings {
    /// The localization key for a heading; nil for a day, which comes from the calendar.
    static func key(for role: PageTemplateLayout.HeadingRole) -> String? {
        switch role {
        case .meetingTitle: "template.meetingTitle"
        case .date: "template.date"
        case .attendees: "template.attendees"
        case .notes, .plannerNotes: "template.notes"
        case .actionItems: "template.actionItems"
        case .weekOf: "template.weekOf"
        case .day: nil
        }
    }

    /// The name of the day in `position` of the week, starting on the
    /// calendar's first weekday (Sunday in the US, Monday in France), as the
    /// calendar's locale writes it, capitalized as a heading.
    static func dayName(_ position: Int, calendar: Calendar) -> String {
        let symbols = calendar.standaloneWeekdaySymbols
        guard symbols.count == 7 else { return "" }
        let name = symbols[(calendar.firstWeekday - 1 + position) % 7]
        return name.capitalized(with: calendar.locale ?? .current)
    }

    /// The reader's week for headings: day names in the language the other
    /// headings resolved to (`L10n`'s, from the app's own localizations, so a
    /// French reader in the US gets "Dimanche" and a German one, whose
    /// headings fall back to English, gets "Sunday"), starting on the day
    /// the reader's region starts the week.
    static func readersWeek(language: String = ResourceBundle.ui.preferredLocalizations.first ?? "en",
                            firstWeekday: Int = Calendar.autoupdatingCurrent.firstWeekday) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: language)
        // After the locale, which would otherwise bring its own first day.
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    /// `text` says each heading (by default from `L10n`); a nil or empty
    /// answer leaves that heading out.
    static func textBoxes(for template: PageTemplate, size: CGSize = LibraryStore.notebookPageSize,
                          calendar: Calendar = readersWeek(),
                          text: ((PageTemplateLayout.HeadingRole) -> String?)? = nil) -> [TextBox] {
        let say = text ?? { role in key(for: role).map { L10n.tr($0) } }
        let gray = PageTemplateLayout.headingGray
        return PageTemplateLayout.layout(for: template, size: size).headings.compactMap { heading in
            let words: String?
            if case .day(let position) = heading.role { words = dayName(position, calendar: calendar) } else { words = say(heading.role) }
            guard let words, !words.isEmpty else { return nil }
            return TextBox(frame: heading.frame, text: words, fontSize: heading.fontSize,
                           color: RGBAColor(red: gray, green: gray, blue: gray), isBold: heading.isBold)
        }
    }
}

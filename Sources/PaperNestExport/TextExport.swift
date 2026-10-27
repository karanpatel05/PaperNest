import Foundation
import PaperNestCore

extension Exporter {
    /// The conventional ASCII page break. Deliberately not a worded separator
    /// such as "Page 2", which would need a localized string and would turn a
    /// machine-readable file into one in a particular language.
    static let textPageSeparator = "\u{0C}"

    /// Writes `pages` as plain text, one section per page.
    ///
    /// A page's text is the best it actually has: current completed
    /// recognition first, because those lines come with positions, then the
    /// text a digital PDF already carries, read from the page's own file so it
    /// keeps its lines. Nothing is invented for a page that has neither — it
    /// keeps its place between the separators so page order stays readable.
    ///
    /// Only text that is current for the page can appear: `recognizedLines`
    /// refuses a result from an older revision, and a page's own text is read
    /// from the asset `page.content` names, so a rescanned page cannot export
    /// words describing paper it no longer shows.
    ///
    /// Throws `ExportError.noTextToExport` when no page has any text, rather
    /// than writing a file of nothing but separators and calling it an export.
    func writeText(_ pages: [Page], to url: URL,
                   progress: @Sendable (ExportProgress) -> Void) async throws -> URL {
        progress(ExportProgress(completedPages: 0, totalPages: pages.count))
        var sections: [String] = []
        var foundAnyText = false
        let sources = try await sourceDocuments(for: pages)

        for (index, page) in pages.enumerated() {
            try Task.checkCancellation()
            let recognized = try await renderer.recognizedLines(for: page)
            let text: String
            if !recognized.isEmpty {
                text = recognized.map(\.text).joined(separator: "\n")
            } else {
                text = Self.textLines(of: page, in: sources).joined(separator: "\n")
            }
            if !text.isEmpty { foundAnyText = true }
            sections.append(text)
            progress(ExportProgress(completedPages: index + 1, totalPages: pages.count))
        }

        guard foundAnyText else { throw ExportError.noTextToExport }
        let joined = sections.joined(separator: Self.textPageSeparator)
        guard let data = joined.data(using: .utf8) else { throw ExportError.writeFailed }
        try data.write(to: url)
        return url
    }
}

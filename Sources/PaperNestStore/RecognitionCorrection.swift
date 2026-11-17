import Foundation
import PaperNestCore

/// Correcting what was read off a page, by hand.
///
/// Recognition gets words wrong, and the roadmap asks for a way to put them
/// right. A correction replaces the text of a page's current result line by
/// line and keeps each line's place on the page, so search, find, selection,
/// read aloud, text and Word export and the searchable PDF all use the
/// corrected words from then on.
extension LibraryStore {
    /// One correction, as a compare-and-swap token: `after` is written only
    /// while the page still holds `before`. Only this store can make one, and
    /// its `inverse` is the undo.
    public struct RecognitionCorrection: Sendable {
        public let pageID: PageID
        public let before: PageRecognition
        public let after: PageRecognition
        public var inverse: Self { .init(pageID: pageID, before: after, after: before) }

        fileprivate init(pageID: PageID, before: PageRecognition, after: PageRecognition) {
            self.pageID = pageID
            self.before = before
            self.after = after
        }
    }

    /// Corrects the text of the page's current result, one entry per line
    /// of `expected`, in order.
    ///
    /// Each entry is the line's new text. Ends are trimmed and line breaks
    /// become spaces, because a recognized line is one line on the paper; an
    /// entry left empty removes the line, which is how a line of noise read
    /// off a smudge is got rid of. A changed line keeps its box and becomes
    /// certain (confidence 1), since a person wrote it; it keeps its words'
    /// boxes only when it still has as many words as were boxed, and
    /// otherwise falls back to the whole line, as readers already do for
    /// lines Vision could not box word by word.
    ///
    /// - Returns: the change, for undo; nil when nothing changed, in which
    ///   case nothing is written.
    /// - Throws: `StoreError.recognitionChanged` when the page no longer holds
    ///   `expected` as its current result — recognized again, or new paper,
    ///   while the editor was open — rather than overwrite what replaced it;
    ///   `StoreError.invalidOrder` when the entries do not match its lines.
    @discardableResult
    public func correctRecognition(on pageID: PageID, expected: PageRecognition,
                                   texts: [String]) throws -> RecognitionCorrection? {
        try db.transaction {
            guard expected.pageID == pageID, texts.count == expected.lines.count else {
                throw StoreError.invalidOrder
            }
            // Before anything else, so an editor opened on something that is
            // no longer there hears so even when it changed nothing.
            _ = try currentPage(holding: expected)
            var lines: [RecognizedLine] = []
            for (line, typed) in zip(expected.lines, texts) {
                let text = Self.correctedText(typed)
                guard !text.isEmpty else { continue }
                lines.append(text == line.text ? line : Self.line(line, correctedTo: text))
            }
            guard lines != expected.lines else { return nil }
            var after = expected
            after.lines = lines
            after.correctedAt = now()
            let change = RecognitionCorrection(pageID: pageID, before: expected, after: after)
            try applyRecognitionCorrection(change)
            return change
        }
    }

    /// Writes `change.after` if the page still holds `change.before`, and
    /// returns the page as it is afterwards.
    ///
    /// "Still holds" ignores the revision the result is pinned to: drawing on
    /// the page carries a current result forward without changing a word, and
    /// an undo after some ink must still work. It does not ignore anything
    /// else, and the result must be current — a page recognized again, or
    /// given new paper, refuses with `recognitionChanged`.
    ///
    /// **The page's revision moves**, as for any edit of what the page shows:
    /// find and text selection re-read a page only when its revision changes,
    /// and without this they would go on finding the uncorrected words. A
    /// revision-only change of a page is not a synced edit, so nothing about
    /// this leaves the device; the document's modified date does change, so
    /// it moves up in Recent, as for any edit.
    @discardableResult
    public func applyRecognitionCorrection(_ change: RecognitionCorrection) throws -> Page {
        try db.transaction {
            let page = try currentPage(holding: change.before)
            try bumpRevision(page)
            guard let moved = try self.page(change.pageID) else { throw StoreError.pageNotFound }
            var after = change.after
            after.sourceRevision = moved.revision
            try upsertRecognitionRow(after)
            try db.run("DELETE FROM search_index WHERE page_id = ? AND field = 'ocr'", [.text(moved.id.rawValue)])
            let text = after.text
            if !text.isEmpty {
                try db.run("INSERT INTO search_index (item_id, page_id, field, content) VALUES (?, ?, 'ocr', ?)",
                           [.text(moved.itemID.rawValue), .text(moved.id.rawValue), .text(text)])
            }
            return moved
        }
    }

    /// The page, if its current, finished result is `expected` (whatever
    /// revision that was pinned to); otherwise `recognitionChanged`.
    private func currentPage(holding expected: PageRecognition) throws -> Page {
        guard let page = try page(expected.pageID), let parent = try item(page.itemID), !parent.isDeleted else {
            throw StoreError.pageNotFound
        }
        guard let current = try recognition(for: page.id), current.status == .completed,
              current.sourceRevision == page.revision, current.isSameResult(as: expected) else {
            throw StoreError.recognitionChanged
        }
        return page
    }

    /// What a typed line becomes: one line, no space at either end.
    static func correctedText(_ typed: String) -> String {
        let oneLine = typed.split(whereSeparator: \.isNewline).joined(separator: " ")
        return oneLine.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `line` with `text` in place of what was read.
    static func line(_ line: RecognizedLine, correctedTo text: String) -> RecognizedLine {
        let read = line.text.split(whereSeparator: \.isWhitespace).map(String.init)
        let typed = text.split(whereSeparator: \.isWhitespace).map(String.init)
        // Boxes stay only where they are trustworthy: every word was boxed,
        // and there are as many words now. A typo put right in one word keeps
        // the line's highlights word by word; anything else lights the line.
        let words = line.words.map(\.text) == read && typed.count == read.count
            ? zip(line.words, typed).map { RecognizedWord(text: $1, box: $0.box) }
            : []
        return RecognizedLine(text: text, box: line.box, confidence: 1, words: words)
    }
}

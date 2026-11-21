import CoreGraphics
import Foundation

/// What was read off a page's handwriting, and the ink it was read from.
///
/// Derived, like OCR: made on each device from the page's ink and never
/// synced. It describes the page only while `inkGeneration` is the page's
/// current count of ink changes; any change to the ink makes it stale.
public struct HandwritingRecognitionResult: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        /// Read; `lines` may be empty when nothing in the ink was readable.
        case completed
        /// Recognition could not run. Kept so the page is not retried on
        /// every pass; a change to the ink or a new engine retries it.
        case failed
    }

    /// A line as read, with how sure Vision was and where it lies (source points).
    public struct Line: Codable, Equatable, Sendable {
        /// A word of the line and where it lies (source points), where Vision
        /// boxed it.
        public struct Word: Codable, Equatable, Sendable {
            public var text: String
            public var bounds: CGRect

            public init(text: String, bounds: CGRect) {
                self.text = text
                self.bounds = bounds
            }
        }

        public var text: String
        public var confidence: Double
        public var bounds: CGRect
        /// Empty for a reading made before words were kept
        /// (`vision.handwriting.1`): a reader falls back to the line's box.
        public var words: [Word]

        public init(text: String, confidence: Double, bounds: CGRect, words: [Word] = []) {
            self.text = text
            self.confidence = confidence
            self.bounds = bounds
            self.words = words
        }

        private enum CodingKeys: String, CodingKey { case text, confidence, bounds, words }

        /// Readings stored before words were kept have no `words`; they must
        /// still decode, or one old row would stop library search working.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            text = try container.decode(String.self, forKey: .text)
            confidence = try container.decode(Double.self, forKey: .confidence)
            bounds = try container.decode(CGRect.self, forKey: .bounds)
            words = try container.decodeIfPresent([Word].self, forKey: .words) ?? []
        }
    }

    public var pageID: PageID
    public var inkGeneration: Int
    public var engineVersion: String
    public var status: Status
    public var languages: [String]
    public var lines: [Line]

    public init(pageID: PageID, inkGeneration: Int, engineVersion: String, status: Status,
                languages: [String], lines: [Line]) {
        self.pageID = pageID
        self.inkGeneration = inkGeneration
        self.engineVersion = engineVersion
        self.status = status
        self.languages = languages
        self.lines = lines
    }

    /// The lines sure enough to answer a search. Vision's confidence comes in
    /// steps (1.0, or 0.5 when unsure, in what was measured on 2026-11-20),
    /// and anything below the step it calls unsure is noise.
    public static let searchableConfidence = 0.5

    public var searchableLines: [Line] {
        guard status == .completed else { return [] }
        return lines.filter { $0.confidence >= Self.searchableConfidence }
    }

    /// The words a search can find, one line each.
    public var searchableText: String { searchableLines.map(\.text).joined(separator: "\n") }

    /// Whether any searchable line was read without full confidence, which a
    /// result says out loud rather than as a percentage it does not have.
    public var mayBeMisread: Bool { searchableLines.contains { $0.confidence < 1 } }
}

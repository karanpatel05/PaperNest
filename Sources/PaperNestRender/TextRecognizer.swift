import CoreGraphics
import Foundation
import PaperNestCore
import Vision

/// Reads printed text off a page image with Vision, on device.
///
/// Results are returned in the page's **upright, uncropped source space with
/// a top-left origin**, the one space `PageGeometry` maps from. Vision reports
/// normalized boxes with a bottom-left origin, so the y axis is flipped here
/// and nowhere else.
public struct TextRecognizer: Sendable {
    /// Stored with each result, so a later engine change can invalidate
    /// results that were produced by an older one.
    public static let engineVersion = "vision.accurate.1"

    /// Every language this device's Vision can read at `.accurate`.
    ///
    /// Asked rather than assumed: the set differs by OS version, so a choice
    /// made on one machine may be half impossible on another.
    public static func availableLanguages() -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        return (try? request.supportedRecognitionLanguages()) ?? []
    }

    /// Checked against Vision rather than assumed: claiming a language we
    /// cannot read would be a lie.
    public static func supportedLanguages(from wanted: [String]) -> [String] {
        let available = Set(availableLanguages())
        return wanted.filter(available.contains)
    }

    public static let preferredLanguages = ["en-US", "fr-FR", "es-ES"]

    /// What recognition will read in, and what it was asked for and cannot.
    public struct LanguageChoice: Equatable, Sendable {
        /// The list handed to Vision, in the order it will weight them.
        public let using: [String]
        /// Languages the reader asked for that this device cannot read. Kept
        /// so a screen can say so, instead of quietly reading in something
        /// else.
        public let unavailable: [String]
    }

    /// Works out which languages to recognise in.
    ///
    /// A reader's choice **replaces** the defaults rather than adding to
    /// them: someone who says German does not want English guesses mixed in,
    /// and every extra language costs accuracy on the others, because Vision
    /// weights the list it is given.
    ///
    /// A choice this device cannot honour at all falls back to the defaults
    /// rather than leaving recognition with an empty list, which would read
    /// nothing — but `unavailable` still carries the whole choice, so what
    /// happened can be said out loud. Nothing readable at all comes back
    /// empty rather than as a guess: reading a page with a language nobody
    /// asked for produces confident nonsense, and `recognize` refuses an
    /// empty list outright.
    public static func resolve(override: [String], fallback: [String] = preferredLanguages,
                               available: [String]) -> LanguageChoice {
        let readable = Set(available)
        func keep(_ wanted: [String]) -> [String] {
            var seen = Set<String>()
            return wanted.filter { readable.contains($0) && seen.insert($0).inserted }
        }
        guard !override.isEmpty else { return LanguageChoice(using: keep(fallback), unavailable: []) }
        let chosen = keep(override)
        let impossible = override.filter { !readable.contains($0) }
        return LanguageChoice(using: chosen.isEmpty ? keep(fallback) : chosen, unavailable: impossible)
    }

    public let languages: [String]
    public let minimumConfidence: Float

    public init(languages: [String] = TextRecognizer.preferredLanguages, minimumConfidence: Float = 0.3) {
        self.languages = languages
        self.minimumConfidence = minimumConfidence
    }

    public enum RecognitionError: Error, Equatable {
        case noSupportedLanguage
    }

    /// Recognition, run on a thread of its own.
    ///
    /// Vision's task queue dispatches **synchronously** while preserving its
    /// own capacity, so `recognize(_:)` parks the thread it was called on until
    /// Vision has room. Called from a task or an actor, that thread is one of
    /// Swift concurrency's cooperative threads — roughly one per core — and
    /// enough concurrent recognitions park every one of them, including the
    /// threads Vision needs to finish the work the others are waiting for.
    /// That is a deadlock, not a slow run: it was reproduced with sixteen
    /// concurrent passes on an eight-core machine, every one stuck in
    /// `semaphore_wait_trap` under `VNControlledCapacityTasksQueue`.
    ///
    /// Anything calling this from an actor or a `Task` must use this rather
    /// than `recognize(_:)`. The queue is serial and shared, so it also keeps
    /// Vision's own capacity from being oversubscribed.
    public func recognizeOnADedicatedThread(_ image: CGImage) async throws -> [RecognizedLine] {
        try await withCheckedThrowingContinuation { continuation in
            Self.blockingQueue.async {
                continuation.resume(with: Result { try self.recognize(image) })
            }
        }
    }

    /// Off the cooperative pool, so a blocking Vision call cannot starve it.
    private static let blockingQueue = DispatchQueue(label: "papernest.text-recognition", qos: .utility)

    /// Recognizes `image`, which must be the page's upright, uncropped source.
    public func recognize(_ image: CGImage) throws -> [RecognizedLine] {
        let usable = Self.supportedLanguages(from: languages)
        guard !usable.isEmpty else { throw RecognitionError.noSupportedLanguage }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = usable
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first,
                  candidate.confidence >= minimumConfidence else { return nil }
            let box = observation.boundingBox
            return RecognizedLine(
                text: candidate.string,
                // Vision's origin is bottom-left; ours is top-left.
                box: .exact(x: Double(box.minX), y: Double(1 - box.maxY),
                            width: Double(box.width), height: Double(box.height)),
                confidence: Double(candidate.confidence),
                words: Self.words(of: candidate)
            )
        }
        // Reading order: top to bottom, then left to right.
        .sorted { ($0.box.y, $0.box.x) < ($1.box.y, $1.box.x) }
    }

    /// Each whitespace-separated word of a recognised line, with the box
    /// Vision places it in.
    ///
    /// A word Vision will not box is **dropped rather than given one**: the
    /// only box available to invent from is the line's, and a highlight drawn
    /// there would cover text the user did not select. So this can return
    /// fewer words than the line contains, which a caller must expect.
    static func words(of candidate: VNRecognizedText) -> [RecognizedWord] {
        let text = candidate.string
        var words: [RecognizedWord] = []
        var start = text.startIndex
        while start < text.endIndex {
            guard let wordStart = text[start...].firstIndex(where: { !$0.isWhitespace }) else { break }
            let wordEnd = text[wordStart...].firstIndex(where: \.isWhitespace) ?? text.endIndex
            if let observed = try? candidate.boundingBox(for: wordStart..<wordEnd)?.boundingBox {
                words.append(RecognizedWord(
                    text: String(text[wordStart..<wordEnd]),
                    // Same flip the line's box gets: Vision is bottom-left.
                    box: .exact(x: Double(observed.minX), y: Double(1 - observed.maxY),
                                width: Double(observed.width), height: Double(observed.height))))
            }
            start = wordEnd
        }
        return words
    }
}

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

    /// Checked against Vision rather than assumed: the supported set differs
    /// by OS version, and claiming a language we cannot read would be a lie.
    public static func supportedLanguages(from wanted: [String]) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let available = (try? request.supportedRecognitionLanguages()) ?? []
        return wanted.filter(available.contains)
    }

    public static let preferredLanguages = ["en-US", "fr-FR", "es-ES"]

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

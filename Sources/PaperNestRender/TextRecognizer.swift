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
                confidence: Double(candidate.confidence)
            )
        }
        // Reading order: top to bottom, then left to right.
        .sorted { ($0.box.y, $0.box.x) < ($1.box.y, $1.box.x) }
    }
}

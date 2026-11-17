import Foundation
import PaperNestCore
import PaperNestStore

/// The text details are read from: the page's current recognized text, with
/// recognition's confidence, or the PDF's own text, at full confidence.
/// Typed text boxes are someone's marks, not the page's, and are left out.
/// Nothing is recognized here: a scan nobody has read has no lines, and the
/// review says to recognize its text first.
extension PageRenderer {
    public func captureLines(for page: Page) async throws -> [CaptureLine] {
        let recognized = try await recognizedLines(for: page)
        if !recognized.isEmpty {
            return recognized.map { CaptureLine(text: $0.text, box: $0.box, confidence: $0.confidence) }
        }
        return try await textLayout(for: page).lines.compactMap { line -> CaptureLine? in
            guard line.origin == .embedded, let first = line.fragments.first(where: { $0.box.width > 0 }) else { return nil }
            var text = ""
            var box = first.box
            for (index, fragment) in line.fragments.enumerated() {
                text += fragment.text
                if fragment.spaceAfter, index < line.fragments.count - 1 { text += " " }
                if fragment.box.width > 0, fragment.box.height > 0 { box = box.union(fragment.box) }
            }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : CaptureLine(text: trimmed, box: box, confidence: 1)
        }
    }
}

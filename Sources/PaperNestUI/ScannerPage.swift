#if os(iOS)
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import PaperNestCore
import PaperNestRender

/// A transient capture draft; immutable source data remains available for Reset.
/// Library import still owns the first durable write and all persistent metadata.
struct ScannerPage: Identifiable, Sendable {
    let id = UUID()
    let original: Data
    var quarterTurns = 0
    /// The preset and the Cleanup amounts. They are drawn into the picture
    /// each time it is rendered and never into `original`.
    var appearance = ScanAppearance.original
    var corners = ScannerPage.wholeFrame

    static let wholeFrame = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]

    /// Core Image's context is costly to make and safe to share.
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// A second page of the same capture with the same edits.
    func copy() -> ScannerPage {
        ScannerPage(original: original, quarterTurns: quarterTurns, appearance: appearance, corners: corners)
    }

    /// Back to the capture as it was taken: no turn, no look, the whole frame.
    mutating func reset() {
        quarterTurns = 0
        appearance = .original
        corners = Self.wholeFrame
    }

    /// Changes whenever the picture would, so views know when to redraw.
    var drawKey: String { "\(id)-\(quarterTurns)-\(appearance)-\(corners)" }

    /// The page as it will be saved, or a smaller copy that looks the same.
    func rendered(maxDimension: CGFloat? = nil) -> UIImage? {
        guard let cropped = cropped(maxDimension: maxDimension) else { return nil }
        var ci = ScanImageProcessor.apply(appearance, to: cropped)
        for _ in 0..<quarterTurns { ci = ci.oriented(.right) }
        guard let output = Self.context.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: output)
    }

    /// The page cropped to its corners, with no look and no turn: what the
    /// Cleanup sheet draws its before and after from, so moving a slider does
    /// not decode the capture again.
    func base(maxDimension: CGFloat) -> CGImage? {
        guard let cropped = cropped(maxDimension: maxDimension) else { return nil }
        return Self.context.createCGImage(cropped, from: cropped.extent)
    }

    /// `base` with a look and the page's turn, for showing only.
    static func preview(of base: CGImage, appearance: ScanAppearance, quarterTurns: Int) -> UIImage? {
        ScanImageProcessor.apply(appearance, to: base).map { turned($0, quarterTurns: quarterTurns) }
    }

    /// A drawn picture, turned clockwise as the page is. For showing only.
    static func turned(_ image: CGImage, quarterTurns: Int) -> UIImage {
        let turns: [UIImage.Orientation] = [.up, .right, .down, .left]
        return UIImage(cgImage: image, scale: 1, orientation: turns[((quarterTurns % 4) + 4) % 4])
    }

    /// Geometry only: the user's four corners, then the size asked for. The
    /// look comes after, sized to the page, so a preview matches the saved page.
    private func cropped(maxDimension: CGFloat?) -> CIImage? {
        guard corners.count == 4, corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        guard let image = UIImage(data: original) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let normalized = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
        guard let cg = normalized.cgImage else { return nil }
        let source = CIImage(cgImage: cg)
        let correction = CIFilter.perspectiveCorrection()
        correction.inputImage = source
        func vector(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x * source.extent.width, y: (1 - point.y) * source.extent.height)
        }
        correction.topLeft = vector(corners[0])
        correction.topRight = vector(corners[1])
        correction.bottomRight = vector(corners[2])
        correction.bottomLeft = vector(corners[3])
        guard var ci = correction.outputImage else { return nil }
        if let maxDimension {
            let scale = min(1, maxDimension / max(ci.extent.width, ci.extent.height))
            ci = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        return ci
    }

    /// Detection only: preserve raw still bytes so crop/reset can recover edges.
    /// The whole frame when nothing the mode accepts is found; nil only for
    /// bytes that are not a picture.
    static func detectedCorners(_ data: Data, detection: ScanDetection) -> [CGPoint]? {
        guard let source = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }
        return ScanEdgeDetector.detect(detection, in: source)?.corners ?? wholeFrame
    }
}
#endif

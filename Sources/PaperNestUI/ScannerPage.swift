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
    /// What the camera was pointed at, which decides what its quality check
    /// may say (`ScanQualityReport.issues(in:)`). A page brought in from
    /// Photos or Files is taken for a document, as the scanner's pages are.
    var mode = ScanCaptureMode.document
    /// Where a book capture folds, a share across its straightened spread:
    /// set only when it was taken in Book mode and its outline is wider than
    /// tall (`spreadGutter(_:corners:)`). Kept, it becomes two pages
    /// (`spreadPages()`); until then it is shown whole, its fold marked.
    var spreadGutter: Double?

    static let wholeFrame = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]

    /// Core Image's context is costly to make and safe to share.
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// A second page of the same capture with the same edits.
    func copy() -> ScannerPage {
        ScannerPage(original: original, quarterTurns: quarterTurns, appearance: appearance, corners: corners, mode: mode,
                    spreadGutter: spreadGutter)
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

    /// A book capture's two pages, left then right: the same photo, each
    /// cropped to its half of the outline. Any other page is itself.
    func spreadPages() -> [ScannerPage] {
        guard let spreadGutter else { return [self] }
        return ScanSpread.halves(of: corners, at: spreadGutter).map {
            ScannerPage(original: original, appearance: appearance, corners: $0, mode: mode)
        }
    }

    /// Where a capture taken in Book mode folds, or nil when it is to stay
    /// one page: its outline was not found (the whole frame) or is not
    /// plainly wider than tall. Cutting one page in half is the costly
    /// mistake; keeping a spread whole costs a retake.
    static func spreadGutter(_ data: Data, corners: [CGPoint]) -> Double? {
        guard corners != wholeFrame, let size = ScanQualityAnalyzer.photoSize(of: data),
              ScanSpread.isSpread(corners, photoSize: size) else { return nil }
        guard let spread = ScannerPage(original: data, corners: corners).base(maxDimension: 1200) else { return 0.5 }
        return ScanGutter.find(in: spread)
    }

    /// The capture as shown before it is kept: a book's spread with its fold
    /// marked, so the two pages it will become can be seen.
    func reviewPicture(maxDimension: CGFloat) -> UIImage? {
        guard let picture = rendered(maxDimension: maxDimension) else { return nil }
        guard let spreadGutter else { return picture }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: picture.size, format: format).image { context in
            picture.draw(at: .zero)
            let x = picture.size.width * spreadGutter, line = max(2, picture.size.width / 300)
            UIColor.white.setFill()
            context.fill(CGRect(x: x - line * 1.5, y: 0, width: line * 3, height: picture.size.height))
            UIColor(red: 0.455, green: 0.220, blue: 0.961, alpha: 1).setFill()
            context.fill(CGRect(x: x - line / 2, y: 0, width: line, height: picture.size.height))
        }
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

#if os(iOS)
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// A transient capture draft; immutable source data remains available for Reset.
/// Library import still owns the first durable write and all persistent metadata.
struct ScannerPage: Identifiable, Sendable {
    let id = UUID()
    let original: Data
    var quarterTurns = 0
    var filter = 0
    var enhanced = false
    var corners = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]

    func rendered(maxDimension: CGFloat? = nil) -> UIImage? {
        guard corners.count == 4, corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        guard let image = UIImage(data: original) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let normalized = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
        guard let cg = normalized.cgImage else { return nil }
        var ci = CIImage(cgImage: cg)
        let correction = CIFilter.perspectiveCorrection()
        correction.inputImage = ci
        func vector(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x * ci.extent.width, y: (1 - point.y) * ci.extent.height)
        }
        correction.topLeft = vector(corners[0])
        correction.topRight = vector(corners[1])
        correction.bottomRight = vector(corners[2])
        correction.bottomLeft = vector(corners[3])
        guard let cropped = correction.outputImage else { return nil }
        ci = cropped
        if enhanced {
            // Automatic tonal/color adjustment only. Geometry remains entirely
            // controlled by the user's four corners and quarter-turn rotation.
            let adjustments = ci.autoAdjustmentFilters(options: [.enhance: true, .redEye: false, .crop: false, .level: false])
            for adjustment in adjustments {
                adjustment.setValue(ci, forKey: kCIInputImageKey)
                if let output = adjustment.outputImage { ci = output.cropped(to: cropped.extent) }
            }
        }
        if filter > 0 {
            let adjustment = CIFilter.colorControls()
            adjustment.inputImage = ci
            adjustment.saturation = 0
            adjustment.contrast = filter == 2 ? 2 : 1
            ci = adjustment.outputImage ?? ci
        }
        for _ in 0..<quarterTurns { ci = ci.oriented(.right) }
        if let maxDimension {
            let scale = min(1, maxDimension / max(ci.extent.width, ci.extent.height))
            ci = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        guard let output = CIContext().createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: output)
    }

    /// Detection only: preserve raw still bytes so crop/reset can recover edges.
    static func detectedCorners(_ data: Data) -> [CGPoint]? {
        guard let source = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 1
        request.minimumConfidence = 0.7
        request.minimumSize = 0.2
        try? VNImageRequestHandler(ciImage: source, orientation: .up).perform([request])
        guard let rectangle = request.results?.first else { return ScannerPage(original: data).corners }
        return [rectangle.topLeft, rectangle.topRight, rectangle.bottomRight, rectangle.bottomLeft].map { CGPoint(x: $0.x, y: 1 - $0.y) }
    }
}
#endif

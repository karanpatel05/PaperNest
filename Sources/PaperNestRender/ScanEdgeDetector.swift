import CoreGraphics
import CoreImage
import PaperNestCore
import Vision

/// Finds the paper, board or card in a picture, as the scan mode asks.
///
/// The mode's `ScanDetection` says what to ask the rectangle detector for
/// and which of its answers to take; this is the asking. The live preview
/// and a taken still both come through here, so the outline shown before
/// the shutter and the crop made after it follow the same rule.
///
/// Vision parks the thread it is called on. Call this from a queue or a
/// thread of its own, one request at a time, never from many tasks at once.
public enum ScanEdgeDetector {
    /// A rectangle request set up for the mode.
    public static func request(for detection: ScanDetection) -> VNDetectRectanglesRequest {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = detection.candidates
        request.minimumConfidence = VNConfidence(detection.minimumConfidence)
        request.minimumSize = Float(detection.minimumSize)
        if let range = detection.aspectRatios {
            request.minimumAspectRatio = VNAspectRatio(range.lowerBound)
            request.maximumAspectRatio = VNAspectRatio(range.upperBound)
        }
        if let tolerance = detection.quadratureTolerance {
            request.quadratureTolerance = VNDegrees(tolerance)
        }
        return request
    }

    /// The quad the mode takes from what a performed request found, or nil.
    /// `imageAspect` is the picture's width over its height, as the request saw it.
    public static func chosen(from request: VNDetectRectanglesRequest, for detection: ScanDetection, imageAspect: Double) -> ScanQuad? {
        // Vision measures up from the bottom-left; a page's crop measures down from the top-left.
        func flipped(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: 1 - point.y) }
        let found = (request.results ?? []).map {
            ScanQuad(topLeft: flipped($0.topLeft), topRight: flipped($0.topRight), bottomRight: flipped($0.bottomRight),
                     bottomLeft: flipped($0.bottomLeft), confidence: Double($0.confidence))
        }
        return detection.best(of: found, imageAspect: imageAspect)
    }

    public static func detect(_ detection: ScanDetection, in image: CGImage) -> ScanQuad? {
        guard image.width > 0, image.height > 0 else { return nil }
        let request = request(for: detection)
        try? VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        return chosen(from: request, for: detection, imageAspect: Double(image.width) / Double(image.height))
    }

    /// For a still read with its orientation already applied.
    public static func detect(_ detection: ScanDetection, in image: CIImage) -> ScanQuad? {
        let extent = image.extent
        guard !extent.isInfinite, extent.width > 0, extent.height > 0 else { return nil }
        let request = request(for: detection)
        try? VNImageRequestHandler(ciImage: image, orientation: .up).perform([request])
        return chosen(from: request, for: detection, imageAspect: Double(extent.width / extent.height))
    }
}

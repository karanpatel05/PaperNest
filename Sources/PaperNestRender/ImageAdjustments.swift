import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import PaperNestCore

/// Applies a page's filter and brightness/contrast to a raster image.
public enum ImageAdjustments {
    /// CIContext is documented as thread-safe and expensive to create, so one
    /// is shared.
    static let context = CIContext(options: [.cacheIntermediates: false])

    public static func apply(_ transform: PageTransform, to image: CGImage) -> CGImage {
        guard transform.needsPixelProcessing else { return image }
        var output = CIImage(cgImage: image)

        let controls = CIFilter.colorControls()
        controls.inputImage = output
        controls.brightness = Float(transform.brightness)
        controls.contrast = Float(transform.contrast)
        controls.saturation = transform.filter == .original ? 1 : 0
        output = controls.outputImage ?? output

        if transform.filter == .blackAndWhite {
            // Otsu picks a global threshold from the histogram, which suits
            // evenly lit documents. Uneven lighting would need an adaptive
            // threshold (tracked in docs/IMPLEMENTATION_PLAN.md).
            let threshold = CIFilter.colorThresholdOtsu()
            threshold.inputImage = output
            output = threshold.outputImage ?? output
        }

        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        return context.createCGImage(output.cropped(to: extent), from: extent, format: .RGBA8,
                                     colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) ?? image
    }
}

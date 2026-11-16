import Accelerate
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import PaperNestCore

/// Draws a scanned page's look: its preset and its Cleanup amounts.
///
/// The picture given is never changed; the result is a new one. Every size
/// used here is a share of the page, so a small preview and the full capture
/// come out looking the same.
///
/// **Remove shadows and Black & White both need to know how well lit the
/// paper is at each point.** That is read from a small copy of the page with
/// everything narrower than about a thirtieth of its longer side closed over,
/// which takes text and ruled lines out, and then from the paper alone: see
/// `Lighting` for how paper is told from a heading bar or a picture, and for
/// what it cannot tell apart. A page with almost no paper in it, a
/// photograph, is left as it is by Remove shadows and Whiten background.
public enum ScanImageProcessor {
    /// The look applied to a picture in Core Image's default working space.
    /// The result covers exactly the picture's extent.
    public static func apply(_ appearance: ScanAppearance, to image: CIImage) -> CIImage {
        let extent = image.extent
        guard !appearance.isOriginal, !extent.isInfinite, extent.width >= 1, extent.height >= 1 else { return image }
        let cleanup = appearance.cleanup
        let bilevel = appearance.preset == .blackAndWhite

        // Tones are worked on as the eye sees them, not in linear light, so
        // half a slider is about half the visible change.
        var page = toneEncoded(image)
        if bilevel || cleanup.removeShadows > 0 || cleanup.whitenBackground > 0,
           let gain = lightingGain(for: image, shadows: bilevel ? 0 : cleanup.removeShadows,
                                   whiten: bilevel ? 0 : cleanup.whitenBackground, flatten: bilevel) {
            let multiply = CIFilter.multiplyCompositing()
            multiply.inputImage = gain
            multiply.backgroundImage = page
            page = clamped(multiply.outputImage ?? page).cropped(to: extent)
        }

        switch appearance.preset {
        case .original:
            break
        case .auto, .enhanced:
            page = toneEncoded(automaticallyAdjusted(linear(page), extent: extent))
            if appearance.preset == .enhanced { page = controls(page, saturation: 1.15, contrast: 1.2) }
        case .grayscale:
            page = controls(page, saturation: 0, contrast: 1)
        case .highContrast:
            page = controls(page, saturation: 1.1, contrast: 1.6)
        case .blackAndWhite:
            // The page is now a share of the paper around each point: paper
            // is 1 and ink well below it, whatever the lighting was.
            page = threshold(controls(page, saturation: 0, contrast: 1), at: 0.72, steepness: 10)
        }

        let sharpening = cleanup.sharpenText + (appearance.preset == .enhanced ? 0.3 : 0)
        if sharpening > 0 {
            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = page.clampedToExtent()
            sharpen.sharpness = Float(sharpening * 1.5)
            sharpen.radius = Float(max(0.8, max(extent.width, extent.height) * 0.0006))
            page = sharpen.outputImage?.cropped(to: extent) ?? page
        }
        return linear(clamped(page)).cropped(to: extent)
    }

    /// The same for a bitmap, in sRGB. Nil only when Core Image cannot draw.
    public static func apply(_ appearance: ScanAppearance, to image: CGImage) -> CGImage? {
        guard !appearance.isOriginal else { return image }
        let output = apply(appearance, to: CIImage(cgImage: image))
        return ImageAdjustments.context.createCGImage(output, from: output.extent, format: .RGBA8,
                                                      colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    // MARK: - Lighting

    /// The longer side of the small copy the lighting is read from.
    private static let lightingSide: CGFloat = 256

    /// What each point of the page is multiplied by to even out its lighting
    /// and bring the paper to white: a small picture stretched over `image`.
    ///
    /// - `shadows`: 0...1, how far darker paper is lifted to the best-lit paper.
    /// - `whiten`: 0...1, how far the paper's own colour is taken to white.
    /// - `flatten`: divide by the paper outright, so paper is 1 everywhere.
    private static func lightingGain(for image: CIImage, shadows: Double, whiten: Double, flatten: Bool) -> CIImage? {
        let extent = image.extent
        let scale = min(1, lightingSide / max(extent.width, extent.height))
        let width = max(1, Int((extent.width * scale).rounded())), height = max(1, Int((extent.height * scale).rounded()))
        let small = CGRect(x: 0, y: 0, width: width, height: height)

        // Shrunk by averaging. A sharper resampling filter rings: it leaves a
        // rim lighter than the paper beside every dark stroke, and the paper
        // would then be read as brighter wherever there is text.
        var source = toneEncoded(image).clampedToExtent()
        if scale < 0.8 {
            let average = CIFilter.gaussianBlur()
            average.inputImage = source
            average.radius = Float(0.4 / scale)
            source = average.outputImage ?? source
        }
        let shrink = CGAffineTransform(scaleX: CGFloat(width) / extent.width, y: CGFloat(height) / extent.height)
            .translatedBy(x: -extent.minX, y: -extent.minY)
        var closed = source.transformed(by: shrink).cropped(to: small).clampedToExtent()

        // Closing: grow the light over anything narrow and dark, then shrink
        // it back so the edge of a real shadow stays where it is. Text and
        // ruled lines go; paper, and anything filled and wide, stays.
        let side = Double(max(width, height))
        let reach = Float(side * 0.016)
        if reach >= 0.5 {
            let grow = CIFilter.morphologyMaximum()
            grow.inputImage = closed
            grow.radius = reach
            let settle = CIFilter.morphologyMinimum()
            settle.inputImage = grow.outputImage
            settle.radius = reach
            closed = settle.outputImage ?? closed
        }
        var pixels = [Float](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            ImageAdjustments.context.render(closed, toBitmap: buffer.baseAddress!, rowBytes: width * 16, bounds: small,
                                            format: .RGBAf, colorSpace: nil)
        }
        guard let lighting = Lighting(pixels: pixels, width: width, height: height) else { return nil }

        let count = width * height
        var gain = [Float](repeating: 1, count: count * 4)
        var lifted = [Float](repeating: 1, count: count), paper = [Float](repeating: 0, count: count)
        for channel in 0..<3 {
            let lit = lighting.lit[channel]
            lighting.light[channel].withUnsafeBufferPointer { light in
                for index in 0..<count {
                    if flatten {
                        lifted[index] = 1 / max(light[index], lit * 0.25)
                    } else if shadows > 0 {
                        // Never more than three times: past that it is not a
                        // shadow, and lifting it would only show noise.
                        let even = min(max(lit / max(light[index], 0.001), 0.7), 3)
                        lifted[index] = 1 + Float(shadows) * (even - 1)
                    }
                    paper[index] = light[index] * lifted[index]
                }
            }
            // The paper's colour after that lift, taken to white. The white
            // point sits a little under the paper so its grain and faint
            // show-through go to white with it.
            var white: Float = 1
            if whiten > 0 {
                let level = Lighting.level(of: paper, weights: lighting.paper, share: 0.8)
                white = max(0.05, 1 + Float(whiten) * (min(level, 1) * 0.92 - 1))
            }
            gain.withUnsafeMutableBufferPointer { gain in
                for index in 0..<count { gain[index * 4 + channel] = lifted[index] / white }
            }
        }
        let map = gain.withUnsafeBytes { buffer in
            CIImage(bitmapData: Data(buffer), bytesPerRow: width * 16, size: small.size, format: .RGBAf, colorSpace: nil)
        }
        let stretch = CGAffineTransform(translationX: extent.minX, y: extent.minY)
            .scaledBy(x: extent.width / CGFloat(width), y: extent.height / CGFloat(height))
        return map.clampedToExtent().transformed(by: stretch).cropped(to: extent)
    }

    /// How brightly each point of a small page is lit, in each channel, read
    /// from its paper alone.
    ///
    /// A point counts as paper when it has the paper's colour, however dim,
    /// and is not darker than any shadow would make it. A shadow dims paper
    /// without changing its colour much; a heading bar, a highlighted box or
    /// a picture has a colour of its own. Light is measured where there is
    /// paper and carried across everything else from the paper around it, so
    /// a filled block is lit like its surroundings instead of being taken for
    /// a deep shadow and bleached.
    ///
    /// What this cannot tell apart: a filled area in a gray close to the
    /// paper's own colour. That reads as paper in shadow and is lightened.
    ///
    /// The arithmetic is Accelerate's, because this runs for every thumbnail
    /// and every move of a Cleanup slider, in debug builds too.
    struct Lighting {
        /// Three planes, row after row.
        var light: [[Float]]
        /// The level of the best-lit paper in each channel.
        var lit: [Float]
        /// 1 where the point was read as bare paper, 0 elsewhere.
        var paper: [Float]

        /// `pixels` is RGBA, row after row, with text already closed over.
        init?(pixels: [Float], width: Int, height: Int) {
            let count = width * height
            guard count > 0, pixels.count >= count * 4 else { return nil }
            let length = vDSP_Length(count)
            var planes = [[Float]](repeating: [Float](repeating: 0, count: count), count: 3)
            var luma = [Float](repeating: 0, count: count)
            pixels.withUnsafeBufferPointer { source in
                var one: Float = 1
                for channel in 0..<3 { vDSP_vsmul(source.baseAddress! + channel, 4, &one, &planes[channel], 1, length) }
            }
            var weights: [Float] = [0.2126, 0.7152, 0.0722]
            vDSP_vsmul(planes[0], 1, &weights[0], &luma, 1, length)
            vDSP_vsma(planes[1], 1, &weights[1], luma, 1, &luma, 1, length)
            vDSP_vsma(planes[2], 1, &weights[2], luma, 1, &luma, 1, length)
            // Not the single brightest point: a glare spot would otherwise
            // set the level for the whole page.
            let brightest = Self.level(of: luma, weights: nil, share: 0.9)
            guard brightest.isFinite, brightest > 0.02 else { return nil }

            // The paper's colour, as each channel's share of the brightness,
            // taken from the brighter quarter of the page.
            let bright = Self.level(of: luma, weights: nil, share: 0.75)
            var isBright = [Float](repeating: 0, count: count), safeLuma = luma
            var floor: Float = 0.0001, ceiling = Float.greatestFiniteMagnitude
            vDSP_vclip(luma, 1, &floor, &ceiling, &safeLuma, 1, length)
            for index in 0..<count where luma[index] >= bright { isBright[index] = 1 }
            var shares = [[Float]](repeating: [Float](repeating: 0, count: count), count: 3)
            var tone: [Float] = []
            for channel in 0..<3 {
                vDSP_vdiv(safeLuma, 1, planes[channel], 1, &shares[channel], 1, length)
                tone.append(Self.level(of: shares[channel], weights: isBright, share: 0.5))
            }
            var paper = [Float](repeating: 0, count: count)
            var found = 0
            let darkest = brightest * 0.3
            for index in 0..<count where luma[index] >= darkest
                && abs(shares[0][index] - tone[0]) < 0.18 && abs(shares[1][index] - tone[1]) < 0.18
                && abs(shares[2][index] - tone[2]) < 0.18 {
                paper[index] = 1
                found += 1
            }
            // Too little paper to read the light from: a photograph, say.
            guard found * 20 >= count else { return nil }
            // A block's edge is a blend of block and paper. Step back from it.
            let side = Double(max(width, height))
            let inner = Self.averaged(paper, width: width, height: height, radius: max(1, Int((side * 0.008).rounded())))
                .map { $0 > 0.999 ? Float(1) : 0 }
            if inner.contains(1) { paper = inner }

            // Carry the paper's light across what is not paper, then smooth
            // the whole so the join does not show.
            let carry = max(1, side * 0.08), smooth = max(0.5, side * 0.012)
            let spread = Self.blurred(paper, width: width, height: height, sigma: carry)
            var light: [[Float]] = [], lit: [Float] = []
            var masked = [Float](repeating: 0, count: count)
            for plane in planes {
                let level = Self.level(of: plane, weights: paper, share: 0.9)
                vDSP_vmul(plane, 1, paper, 1, &masked, 1, length)
                var joined = Self.blurred(masked, width: width, height: height, sigma: carry)
                for index in 0..<count {
                    if paper[index] > 0 { joined[index] = plane[index] }
                    // Too far from any paper to know: assume full light.
                    else { joined[index] = spread[index] > 0.0001 ? joined[index] / spread[index] : level }
                }
                light.append(Self.blurred(joined, width: width, height: height, sigma: smooth, extendingEdges: true))
                lit.append(level)
            }
            self.light = light
            self.lit = lit
            self.paper = paper
        }

        /// A Gaussian blur. Beyond the edge counts as nothing unless the edge
        /// is extended, so divide by a blurred plane of weights to get an average.
        static func blurred(_ plane: [Float], width: Int, height: Int, sigma: Double, extendingEdges: Bool = false) -> [Float] {
            func kernel(_ limit: Int) -> [Float] {
                let radius = max(0, min(Int((sigma * 3).rounded(.up)), limit - 1))
                let weights = (-radius...radius).map { Float(exp(-Double($0 * $0) / (2 * sigma * sigma))) }
                let sum = weights.reduce(0, +)
                return weights.map { $0 / sum }
            }
            return convolved(plane, width: width, height: height, across: kernel(width), down: kernel(height),
                             extendingEdges: extendingEdges)
        }

        /// The mean of the square reaching `radius` each way, edges extended.
        static func averaged(_ plane: [Float], width: Int, height: Int, radius: Int) -> [Float] {
            func kernel(_ limit: Int) -> [Float] {
                let reach = max(0, min(radius, limit - 1))
                return [Float](repeating: 1 / Float(2 * reach + 1), count: 2 * reach + 1)
            }
            return convolved(plane, width: width, height: height, across: kernel(width), down: kernel(height), extendingEdges: true)
        }

        private static func convolved(_ plane: [Float], width: Int, height: Int, across: [Float], down: [Float],
                                      extendingEdges: Bool) -> [Float] {
            var source = plane, result = [Float](repeating: 0, count: plane.count)
            let flags = vImage_Flags(extendingEdges ? kvImageEdgeExtend : kvImageBackgroundColorFill)
            source.withUnsafeMutableBufferPointer { from in
                result.withUnsafeMutableBufferPointer { to in
                    var input = vImage_Buffer(data: from.baseAddress, height: vImagePixelCount(height),
                                              width: vImagePixelCount(width), rowBytes: width * 4)
                    var output = vImage_Buffer(data: to.baseAddress, height: vImagePixelCount(height),
                                               width: vImagePixelCount(width), rowBytes: width * 4)
                    _ = vImageSepConvolve_PlanarF(&input, &output, nil, 0, 0, across, UInt32(across.count),
                                                  down, UInt32(down.count), 0, 0, flags)
                }
            }
            return result
        }

        /// The value that `share` of the weight lies at or below, to about a
        /// two-thousandth. Counted, not sorted: sorting was most of the cost.
        static func level(of values: [Float], weights: [Float]?, share: Double) -> Float {
            let bins = 4096, top: Float = 2
            var histogram = [Float](repeating: 0, count: bins)
            var total: Float = 0
            values.withUnsafeBufferPointer { values in
                for index in 0..<values.count {
                    let weight = weights?[index] ?? 1
                    guard weight > 0, values[index].isFinite else { continue }
                    let bin = min(bins - 1, max(0, Int(values[index] / top * Float(bins))))
                    histogram[bin] += weight
                    total += weight
                }
            }
            guard total > 0 else { return 0 }
            var reached: Float = 0
            for bin in 0..<bins {
                reached += histogram[bin]
                if Double(reached) >= Double(total) * share { return (Float(bin) + 0.5) * top / Float(bins) }
            }
            return top
        }
    }

    // MARK: - Tone

    /// The same automatic correction the scanner's Enhance has always used:
    /// tone and colour only, never a crop or a straighten.
    ///
    /// **The empty `features` list is what keeps this from hanging the app.**
    /// Without it Core Image looks for faces first, through Vision, and
    /// Vision parks the calling thread until it has room. Pages are drawn on
    /// Swift concurrency's threads, several at once (every thumbnail after
    /// "apply to all pages"), and once each of those threads is parked there
    /// is none left for Vision to finish on: 48 calls at once never returned,
    /// where with the list given they take 26 ms together. A page of text has
    /// no faces to balance, so nothing is lost. See `TextRecognizer`'s
    /// `recognizeOnADedicatedThread` for the same trap met the other way.
    private static func automaticallyAdjusted(_ image: CIImage, extent: CGRect) -> CIImage {
        var output = image
        let options: [CIImageAutoAdjustmentOption: Any] = [.enhance: true, .redEye: false, .crop: false, .level: false,
                                                           .features: [CIFeature]()]
        for filter in image.autoAdjustmentFilters(options: options) {
            filter.setValue(output, forKey: kCIInputImageKey)
            if let adjusted = filter.outputImage { output = adjusted.cropped(to: extent) }
        }
        return output
    }

    private static func controls(_ image: CIImage, saturation: Float, contrast: Float) -> CIImage {
        let filter = CIFilter.colorControls()
        filter.inputImage = image
        filter.saturation = saturation
        filter.contrast = contrast
        return filter.outputImage ?? image
    }

    /// Everything above `level` toward white and everything below toward
    /// black, over a short ramp so edges stay smooth instead of jagged.
    private static func threshold(_ image: CIImage, at level: CGFloat, steepness: CGFloat) -> CIImage {
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = CIVector(x: steepness, y: 0, z: 0, w: 0)
        filter.gVector = CIVector(x: 0, y: steepness, z: 0, w: 0)
        filter.bVector = CIVector(x: 0, y: 0, z: steepness, w: 0)
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        let bias = 0.5 - level * steepness
        filter.biasVector = CIVector(x: bias, y: bias, z: bias, w: 0)
        return filter.outputImage ?? image
    }

    private static func clamped(_ image: CIImage) -> CIImage {
        let filter = CIFilter.colorClamp()
        filter.inputImage = image
        filter.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        filter.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        return filter.outputImage ?? image
    }

    private static func toneEncoded(_ image: CIImage) -> CIImage {
        let filter = CIFilter.linearToSRGBToneCurve()
        filter.inputImage = image
        return filter.outputImage ?? image
    }

    private static func linear(_ image: CIImage) -> CIImage {
        let filter = CIFilter.sRGBToneCurveToLinear()
        filter.inputImage = image
        return filter.outputImage ?? image
    }
}

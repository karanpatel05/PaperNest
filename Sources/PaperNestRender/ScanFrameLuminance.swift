import CoreVideo
import Foundation

/// How bright a camera frame is, for the scanner's "Improve lighting".
///
/// The camera's video output is used with its default pixel format, which is
/// not promised, so the format is read from the buffer: the two biplanar YUV
/// formats (their first plane is brightness) and BGRA are understood, and
/// anything else gives nil — unknown, which never holds a capture back.
///
/// A grid of samples, not every pixel: this runs on every look the scanner
/// takes, and the average brightness of a frame does not need millions of
/// reads to be known.
public enum ScanFrameLuminance {
    /// 0 black to 1 white, or nil for a format this does not read.
    public static func mean(of buffer: CVPixelBuffer, samplesPerSide: Int = 24) -> Double? {
        let format = CVPixelBufferGetPixelFormatType(buffer)
        let samples = max(1, samplesPerSide)
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        switch format {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            guard CVPixelBufferGetPlaneCount(buffer) >= 1,
                  let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
            let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
            let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
            let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            guard let average = sampled(width: width, height: height, samples: samples, read: { x, y in
                Double(base.load(fromByteOffset: y * stride + x, as: UInt8.self))
            }) else { return nil }
            // Video range puts black at 16 and white at 235.
            let video = format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            return min(1, max(0, video ? (average - 16) / 219 : average / 255))
        case kCVPixelFormatType_32BGRA:
            guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
            let width = CVPixelBufferGetWidth(buffer)
            let height = CVPixelBufferGetHeight(buffer)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            guard let average = sampled(width: width, height: height, samples: samples, read: { x, y in
                let offset = y * stride + x * 4
                let blue = Double(base.load(fromByteOffset: offset, as: UInt8.self))
                let green = Double(base.load(fromByteOffset: offset + 1, as: UInt8.self))
                let red = Double(base.load(fromByteOffset: offset + 2, as: UInt8.self))
                // Rec. 709 weights: what the eye calls bright.
                return 0.2126 * red + 0.7152 * green + 0.0722 * blue
            }) else { return nil }
            return min(1, max(0, average / 255))
        default:
            return nil
        }
    }

    /// The mean of `read` over a `samples` by `samples` grid, each sample at
    /// the centre of its cell. Only pixels inside `width` by `height` are
    /// read, so a row's padding never counts.
    private static func sampled(width: Int, height: Int, samples: Int,
                                read: (Int, Int) -> Double) -> Double? {
        guard width > 0, height > 0 else { return nil }
        var total = 0.0
        for row in 0..<samples {
            let y = min(height - 1, (2 * row + 1) * height / (2 * samples))
            for column in 0..<samples {
                let x = min(width - 1, (2 * column + 1) * width / (2 * samples))
                total += read(x, y)
            }
        }
        return total / Double(samples * samples)
    }
}

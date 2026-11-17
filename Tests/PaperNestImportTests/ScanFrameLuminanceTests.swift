import CoreVideo
import Foundation
import Testing
@testable import PaperNestRender

/// How bright a camera frame is, read from buffers built here in each format
/// the camera may hand over. The camera's format is not set, so it is read.
@Suite struct ScanFrameLuminanceTests {
    /// A buffer `width` by `height` whose brightness plane (or BGRA pixels)
    /// is filled by `value(x, y)`; every byte of row padding is set to 255,
    /// so reading padding would show as brightness where there is none.
    func buffer(_ format: OSType, width: Int, height: Int, value: (Int, Int) -> (UInt8, UInt8, UInt8)) throws -> CVPixelBuffer {
        var made: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, nil, &made)
        let pixels = try #require(made, "CVPixelBufferCreate \(status)")
        CVPixelBufferLockBaseAddress(pixels, [])
        defer { CVPixelBufferUnlockBaseAddress(pixels, []) }
        if format == kCVPixelFormatType_32BGRA {
            let base = try #require(CVPixelBufferGetBaseAddress(pixels))
            let stride = CVPixelBufferGetBytesPerRow(pixels)
            memset(base, 255, stride * height)
            for y in 0..<height {
                for x in 0..<width {
                    let (red, green, blue) = value(x, y)
                    base.storeBytes(of: blue, toByteOffset: y * stride + x * 4, as: UInt8.self)
                    base.storeBytes(of: green, toByteOffset: y * stride + x * 4 + 1, as: UInt8.self)
                    base.storeBytes(of: red, toByteOffset: y * stride + x * 4 + 2, as: UInt8.self)
                    base.storeBytes(of: 255, toByteOffset: y * stride + x * 4 + 3, as: UInt8.self)
                }
            }
        } else {
            let base = try #require(CVPixelBufferGetBaseAddressOfPlane(pixels, 0))
            let stride = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)
            memset(base, 255, stride * height)
            for y in 0..<height {
                for x in 0..<width { base.storeBytes(of: value(x, y).0, toByteOffset: y * stride + x, as: UInt8.self) }
            }
        }
        return pixels
    }

    func gray(_ level: UInt8) -> (Int, Int) -> (UInt8, UInt8, UInt8) { { _, _ in (level, level, level) } }

    @Test func videoRangeBrightnessRunsFrom16To235() throws {
        let format = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        #expect(ScanFrameLuminance.mean(of: try buffer(format, width: 100, height: 60, value: gray(16))) == 0)
        #expect(ScanFrameLuminance.mean(of: try buffer(format, width: 100, height: 60, value: gray(235))) == 1)
        let middle = try #require(ScanFrameLuminance.mean(of: try buffer(format, width: 100, height: 60, value: gray(126))))
        #expect(abs(middle - 110.0 / 219) < 1e-9)
    }

    @Test func fullRangeBrightnessRunsFrom0To255() throws {
        let format = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        #expect(ScanFrameLuminance.mean(of: try buffer(format, width: 100, height: 60, value: gray(0))) == 0)
        #expect(ScanFrameLuminance.mean(of: try buffer(format, width: 100, height: 60, value: gray(255))) == 1)
    }

    @Test func bgraBrightnessWeighsGreenMost() throws {
        let format = kCVPixelFormatType_32BGRA
        #expect(ScanFrameLuminance.mean(of: try buffer(format, width: 50, height: 40, value: gray(0))) == 0)
        // The weights sum to 1 only up to rounding.
        let white = try #require(ScanFrameLuminance.mean(of: try buffer(format, width: 50, height: 40, value: gray(255))))
        #expect(abs(white - 1) < 1e-9)
        let green = try #require(ScanFrameLuminance.mean(of: try buffer(format, width: 50, height: 40) { _, _ in (0, 255, 0) }))
        #expect(abs(green - 0.7152) < 1e-9)
    }

    /// Rows padded to the buffer's alignment: a black frame is black, though
    /// every padding byte is white.
    @Test func rowPaddingIsNeverRead() throws {
        for format in [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_32BGRA] {
            // 97 pixels wide: not a multiple of any row alignment, so rows are padded.
            let black = try buffer(format, width: 97, height: 33, value: gray(0))
            let stride = format == kCVPixelFormatType_32BGRA
                ? CVPixelBufferGetBytesPerRow(black) : CVPixelBufferGetBytesPerRowOfPlane(black, 0)
            #expect(stride > (format == kCVPixelFormatType_32BGRA ? 97 * 4 : 97), "the test needs padded rows")
            #expect(ScanFrameLuminance.mean(of: black) == 0, "\(format)")
        }
    }

    @Test func halfBlackHalfWhiteIsHalfBright() throws {
        let format = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        let split = try buffer(format, width: 120, height: 80) { x, _ in x < 60 ? (0, 0, 0) : (255, 255, 255) }
        let mean = try #require(ScanFrameLuminance.mean(of: split))
        #expect(abs(mean - 0.5) < 0.01)
    }

    @Test func aFormatItDoesNotReadIsUnknown() throws {
        var made: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32ARGB, nil, &made)
        #expect(ScanFrameLuminance.mean(of: try #require(made)) == nil)
    }
}

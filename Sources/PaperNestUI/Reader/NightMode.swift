import CoreGraphics
import Foundation
import SwiftUI

/// Night mode: the page shown light on dark, for reading in a dim room.
///
/// It is a way of *showing* a page and nothing else. The switch lives in
/// preferences, not in the library; the page's picture is recoloured on its
/// way to the screen; what is stored, cached, exported and printed is the
/// page as it always was.
///
/// Two things do the work, and they are meant to be read together:
///
/// - `NightPalette` recolours the page's own picture pixel by pixel. That is
///   where paper, print, saved ink and saved highlights get their night
///   colours, and it is exact.
/// - `nightFilter` is laid over the whole page — the picture and everything
///   drawn live on top of it: the stroke under the pen, text being typed, a
///   selection. Those are other views, some of them UIKit's, and a filter
///   over the lot is the one way to turn all of them at once and keep a live
///   stroke the colour it will be once saved.
///
/// The filter is a plain "turn the lightness over, keep the hue", which is
/// right for ink and wrong for a highlight (see `NightPalette`). So the
/// picture is put through the same filter once *before* it goes under it:
/// the filter is its own opposite, twice is back where it started, and the
/// picture arrives on screen in the palette's colours.
enum NightMode {
    /// Where the switch is kept. One setting for the app, like the tools.
    static let storageKey = "reader.nightMode"

    /// What surrounds the page at night: the app's own dark canvas.
    static let canvas = Color(.sRGB, red: 0x11 / 255, green: 0x10 / 255, blue: 0x1A / 255)

    /// A launch pointed at a throwaway library — every UI test, every dev
    /// run — starts by day, whatever an earlier launch left on.
    @MainActor static func resetForThrowawayLibrary(_ defaults: UserDefaults = .standard) {
        guard EditorToolSettingsStore.standardStorage(defaults) == nil else { return }
        defaults.removeObject(forKey: storageKey)
    }
}

extension EnvironmentValues {
    /// Whether the page being read is shown in night mode.
    @Entry var pageNightMode = false
}

extension View {
    /// Lightness turned over, hue kept: black ink reads white and red stays
    /// red. Applied twice it gives back what it was given.
    func nightFilter(_ isOn: Bool) -> some View {
        modifier(NightFilter(isOn: isOn))
    }
}

/// Nothing at all is applied by day, on purpose: a filter that does nothing
/// is still a filter the page — and the ink canvas on it — would be drawn
/// through on every frame.
///
/// **The compositing group is load-bearing.** Without it SwiftUI hands the
/// filter down to each view underneath and blends them afterwards, which is
/// the same thing for plain layers and a different thing for anything that
/// multiplies: a highlight multiplied onto paper, turned as a whole, is a
/// band; turned piece by piece and then multiplied onto black paper, it is
/// nothing. Measured, not assumed — the unit test for find's hits failed
/// exactly that way before this line was here.
private struct NightFilter: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.compositingGroup().colorInvert().hueRotation(.degrees(180))
        } else {
            content
        }
    }
}

// MARK: - The page's picture

/// A page's colours as night mode shows them.
///
/// The rule, per pixel: keep the colour's hue and strength, turn its
/// lightness over — white paper to black, black print to white, dark blue
/// ink to light blue. Then one correction. A highlight is paper-pale, so it
/// turns paper-dark; and a dark yellow needs *less blue than none*, which no
/// screen has, so a plain turn-over clips it to black and the highlight is
/// gone. Where that would happen the colour is lifted just far enough to fit,
/// and the highlight stays a dim band of its own colour under white words.
enum NightPalette {
    struct RGB: Equatable, Sendable {
        var red, green, blue: Double
    }

    /// Lightness as weights out of 256, so a grey is weighed as exactly itself.
    private static let weights = (red: 77, green: 150, blue: 29)

    /// One colour, components 0...1 as stored (sRGB, not linear light).
    static func night(_ color: RGB) -> RGB {
        let lightness = (color.red * Double(weights.red) + color.green * Double(weights.green)
                         + color.blue * Double(weights.blue)) / 256
        var shift = 1 - 2 * lightness
        let lowest = min(color.red, color.green, color.blue) + shift
        if lowest < 0 { shift -= lowest }
        return RGB(red: min(max(color.red + shift, 0), 1), green: min(max(color.green + shift, 0), 1),
                   blue: min(max(color.blue + shift, 0), 1))
    }

    /// The same rule on one 8-bit pixel, in whole numbers scaled by 256.
    @inline(__always)
    private static func night(_ pixel: UnsafeMutablePointer<UInt8>) {
        let red = Int(pixel[0]), green = Int(pixel[1]), blue = Int(pixel[2])
        var shift = 255 * 256 - 2 * (red * weights.red + green * weights.green + blue * weights.blue)
        let lowest = min(red, green, blue) * 256 + shift
        if lowest < 0 { shift -= lowest }
        pixel[0] = UInt8(min(max((red * 256 + shift + 128) >> 8, 0), 255))
        pixel[1] = UInt8(min(max((green * 256 + shift + 128) >> 8, 0), 255))
        pixel[2] = UInt8(min(max((blue * 256 + shift + 128) >> 8, 0), 255))
    }

    /// A page's picture in its night colours, or nil if it could not be
    /// drawn. A new picture: the one passed in is never changed.
    static func image(_ source: CGImage) -> CGImage? {
        if let known = cache.image(for: source) { return known }
        let width = source.width, height = source.height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let data = context.data else { return nil }
        // Paper under anything see-through, as the page view has it by day.
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = Pixels(base: data.assumingMemoryBound(to: UInt8.self), bytesPerRow: context.bytesPerRow)
        // Rows in bands, each on its own core: a page at full zoom is some
        // thirteen million pixels.
        let bands = max(1, min(height, ProcessInfo.processInfo.activeProcessorCount))
        DispatchQueue.concurrentPerform(iterations: bands) { band in
            for row in (band * height / bands)..<((band + 1) * height / bands) {
                var pixel = pixels.base + row * pixels.bytesPerRow
                for _ in 0..<width {
                    night(pixel)
                    pixel += 4
                }
            }
        }
        guard let image = context.makeImage() else { return nil }
        cache.store(image, for: source)
        return image
    }

    /// The night picture already made from this one, if it is still held.
    static func cached(_ source: CGImage) -> CGImage? { cache.image(for: source) }

    private struct Pixels: @unchecked Sendable {
        let base: UnsafeMutablePointer<UInt8>
        let bytesPerRow: Int
    }

    private static let cache = NightImageCache()
}

/// The last few night pictures, so turning back to a page does not show it
/// blank while it is recoloured. Small on purpose: these are full-size page
/// pictures, and the day ones are already held by `ThumbnailCache`.
private final class NightImageCache: @unchecked Sendable {
    private struct Entry {
        /// Held so the identity it is found by cannot be handed to another picture.
        let source: CGImage
        let night: CGImage
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private let pixelBudget = 24_000_000

    func image(for source: CGImage) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        guard let index = entries.firstIndex(where: { $0.source === source }) else { return nil }
        let entry = entries.remove(at: index)
        entries.append(entry)
        return entry.night
    }

    func store(_ night: CGImage, for source: CGImage) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll { $0.source === source }
        entries.append(Entry(source: source, night: night))
        var held = entries.reduce(0) { $0 + $1.night.width * $1.night.height }
        while held > pixelBudget, entries.count > 1 {
            let dropped = entries.removeFirst()
            held -= dropped.night.width * dropped.night.height
        }
    }
}

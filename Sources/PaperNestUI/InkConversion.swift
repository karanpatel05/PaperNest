import CoreGraphics
import Foundation
import PaperNestCore
import PencilKit
#if canImport(UIKit)
import UIKit
typealias InkPlatformColor = UIColor
#else
import AppKit
typealias InkPlatformColor = NSColor
#endif

/// Converts between PencilKit strokes, in the canvas's view points, and
/// stored `InkStroke`s, in source points. `sourceToView` is the page's
/// `PageGeometry.sourceToPage` followed by the scale it is displayed at, so
/// ink follows crop and rotation like everything else on the page.
struct InkConversion {
    let sourceToView: CGAffineTransform

    var viewToSource: CGAffineTransform { sourceToView.inverted() }

    /// View points per source point. Rotations by quarter turns keep lengths,
    /// so the determinant gives the uniform scale.
    var scale: CGFloat { Self.uniformScale(sourceToView) }

    /// Spacing of the points sampled along a PencilKit stroke, in view points.
    static let sampleSpacing: CGFloat = 1.5

    /// One stored stroke per visible part of the PencilKit stroke: a stroke
    /// split by the pixel eraser becomes several. Fully erased: none.
    func inkStrokes(from stroke: PKStroke) -> [InkStroke] {
        let tool: InkStroke.Tool = stroke.ink.inkType == .marker ? .highlighter : .pen
        let color = Self.rgba(stroke.ink.color)
        let toSource = stroke.transform.concatenating(viewToSource)
        let widthToSource = Self.uniformScale(stroke.transform) / scale
        return stroke.maskedPathRanges.compactMap { range in
            let samples = Array(stroke.path.interpolatedPoints(in: range, by: .distance(Self.sampleSpacing)))
            guard !samples.isEmpty else { return nil }
            let widths = samples.map { Double(max($0.size.width, 0.1) * widthToSource) }
            let nominal = widths.max() ?? 1
            let points = zip(samples, widths).map { sample, width in
                let at = sample.location.applying(toSource)
                return InkPoint(x: at.x, y: at.y, widthScale: width / nominal, time: sample.timeOffset)
            }
            return InkStroke(tool: tool, color: color, width: nominal, points: points)
        }
    }

    /// A PencilKit stroke showing `ink`, tagged with `seed` so the canvas can
    /// recognize it later (`PKStroke.id` needs iOS 27).
    func pkStroke(from ink: InkStroke, seed: UInt32) -> PKStroke {
        let points = ink.points.map { point in
            let width = CGFloat(ink.width(at: point)) * scale
            return PKStrokePoint(location: CGPoint(x: point.x, y: point.y).applying(sourceToView), timeOffset: point.time,
                                 size: CGSize(width: width, height: width), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let type: PKInk.InkType = ink.tool == .highlighter ? .marker : .pen
        return PKStroke(ink: PKInk(type, color: Self.color(ink.color)), path: PKStrokePath(controlPoints: points, creationDate: Date()),
                        randomSeed: seed)
    }

    static func uniformScale(_ t: CGAffineTransform) -> CGFloat {
        sqrt(abs(t.a * t.d - t.b * t.c))
    }

    static func rgba(_ color: InkPlatformColor) -> RGBAColor {
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let converted = color.cgColor.converted(to: sRGB, intent: .defaultIntent, options: nil),
              let c = converted.components, c.count >= 4 else { return .black }
        return RGBAColor(red: Double(c[0]), green: Double(c[1]), blue: Double(c[2]), alpha: Double(c[3]))
    }

    static func color(_ rgba: RGBAColor) -> InkPlatformColor {
        let cg = CGColor(srgbRed: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
        #if canImport(UIKit)
        return UIColor(cgColor: cg)
        #else
        return NSColor(cgColor: cg) ?? .black
        #endif
    }
}

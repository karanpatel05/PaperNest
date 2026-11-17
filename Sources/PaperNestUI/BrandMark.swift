import CoreGraphics
import PaperNestExport
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The app's own mark, as the icon draws it.
///
/// `scripts/make-app-icon.py` generates both this asset and the Home-screen
/// icon from the same brand art, so the two cannot drift. Everywhere the app
/// shows its own identity goes through here rather than reaching for an SF
/// Symbol that merely resembles it: `leaf.circle` is Apple's glyph, close
/// enough to pass at a glance and wrong beside the real icon.
///
/// The asset is a **template** image — white pixels carrying only the mark's
/// alpha — so the drawing view supplies the colour and it follows light and
/// dark mode instead of being frozen to one appearance.
enum BrandMark {
    static let assetName = "BrandMark"
    static var bundle: Bundle { .module }

    /// The mark as a template `Image`, for a view that sizes and tints it.
    static var templateImage: Image { Image(assetName, bundle: bundle) }

    /// The mark as a watermark logo, from the largest picture the asset holds
    /// (144 pixels, the @3x rendition; a thinned iPad build may hold only
    /// 96). That is ample for the small free-export mark; the large branded
    /// preset draws it about 85 points across, so at print resolution its
    /// edges are soft. Nil only if the asset is missing.
    static let watermarkLogo: WatermarkLogo? = {
        #if canImport(UIKit)
        let cgImage = UIImage(named: assetName, in: Bundle.module,
                              compatibleWith: UITraitCollection(displayScale: 3))?.cgImage
        #else
        // The largest representation as it is, not one scaled up to a size asked for.
        let rep = Bundle.module.image(forResource: assetName)?.representations.max { $0.pixelsWide < $1.pixelsWide }
        var natural = CGRect(x: 0, y: 0, width: rep?.pixelsWide ?? 0, height: rep?.pixelsHigh ?? 0)
        let cgImage = rep?.cgImage(forProposedRect: &natural, context: nil, hints: nil)
        #endif
        return cgImage.flatMap { WatermarkLogo(name: assetName, template: $0) }
    }()

    /// The mark at a given point size, tinted by whatever `foregroundStyle`
    /// the caller has in force. Hidden from accessibility: every place that
    /// draws it already has the app's name in text beside it.
    static func image(size: CGFloat) -> some View {
        Image(assetName, bundle: bundle)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

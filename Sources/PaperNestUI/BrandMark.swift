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

    /// The mark at its own size in the brand art (558 pixels), for the
    /// watermark: `scripts/make-app-icon.py` writes it from the same art as
    /// the icon, one universal image that no device thins away.
    static let largeAssetName = "BrandMarkLarge"

    /// The mark as a watermark logo. The large branded preset draws it about
    /// 85 points across, which printed at 300 dpi takes about 354 pixels, so
    /// it comes from the large rendition rather than the 144-pixel icon one,
    /// which printed soft. Falls back to the icon rendition, and is nil only
    /// if both are missing.
    static let watermarkLogo: WatermarkLogo? = {
        for name in [largeAssetName, assetName] {
            if let cgImage = largestPicture(named: name) { return WatermarkLogo(name: assetName, template: cgImage) }
        }
        return nil
    }()

    /// The largest picture an asset holds, as it is — never one scaled up to
    /// a size asked for.
    private static func largestPicture(named name: String) -> CGImage? {
        #if canImport(UIKit)
        UIImage(named: name, in: Bundle.module, compatibleWith: UITraitCollection(displayScale: 3))?.cgImage
        #else
        let rep = Bundle.module.image(forResource: name)?.representations.max { $0.pixelsWide < $1.pixelsWide }
        var natural = CGRect(x: 0, y: 0, width: rep?.pixelsWide ?? 0, height: rep?.pixelsHigh ?? 0)
        return rep?.cgImage(forProposedRect: &natural, context: nil, hints: nil)
        #endif
    }

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

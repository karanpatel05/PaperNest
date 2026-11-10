import SwiftUI

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

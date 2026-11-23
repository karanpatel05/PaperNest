import CoreText
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Plus Jakarta Sans, the app's typeface since the owner chose it on
/// 2026-11-22 ("Whole app"). The variable font ships in the module's
/// resources under the SIL Open Font License (`PlusJakartaSans-OFL.txt`).
///
/// Every font in the app comes from `Font.app(_:)`, which keeps Dynamic Type:
/// each size is relative to a system text style and grows with it.
enum AppFont {
    static let family = "Plus Jakarta Sans"
    static let resourceName = "PlusJakartaSans-Variable"

    /// The face is about 6% wider and taller than SF at the same size
    /// (measured on "Recently Deleted" and its French and Spanish names), so
    /// on iPhone and iPad sizes are scaled down to keep every existing
    /// layout's line lengths. The Mac's sizes are already small and its
    /// windows have room, so there legibility wins and nothing is scaled.
    #if os(iOS)
    static let opticalScale: CGFloat = 0.95
    #else
    static let opticalScale: CGFloat = 1
    #endif

    /// Registers the bundled face for this process, once. False only if the
    /// resource is missing, in which case `Font.app` falls back to SF.
    static let isAvailable: Bool = {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "ttf") else { return false }
        var error: Unmanaged<CFError>?
        // A second registration fails with "already registered", which still
        // leaves the family usable, so the outcome is read from the family.
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        return familyIsInstalled
    }()

    private static var familyIsInstalled: Bool {
        #if os(iOS)
        UIFont.fontNames(forFamilyName: family).isEmpty == false
        #else
        NSFontManager.shared.availableMembers(ofFontFamily: family)?.isEmpty == false
        #endif
    }

    /// The platform's default size for a text style at the standard content size.
    static func baseSize(for style: Font.TextStyle) -> CGFloat {
        #if os(iOS)
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
        #else
        switch style {
        // SF's Mac sizes, with nothing under 11 points: 10-point Plus Jakarta
        // Sans read as smudge in the first renders.
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline, .body: 13
        case .callout, .subheadline: 12
        case .footnote, .caption, .caption2: 11
        @unknown default: 13
        }
        #endif
    }

    static func size(for style: Font.TextStyle) -> CGFloat {
        (baseSize(for: style) * opticalScale).rounded(toPlaces: 1)
    }

    /// Hierarchy comes from size and colour: titles and headlines are
    /// semibold at most (owner, 2026-11-22), on every platform.
    static var headlineWeight: Font.Weight { .semibold }

    #if os(iOS)
    /// A UIKit font of the family at a weight, scaled with Dynamic Type for
    /// the places SwiftUI does not reach (navigation bar titles).
    static func uiFont(_ style: UIFont.TextStyle, size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: family,
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        let base = UIFont(descriptor: descriptor, size: (size * opticalScale).rounded(toPlaces: 1))
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }

    /// Navigation bar titles are UIKit's; SwiftUI's `.font` does not reach them.
    @MainActor static func styleNavigationBars() {
        guard isAvailable else { return }
        let bar = UINavigationBar.appearance()
        bar.titleTextAttributes = [.font: uiFont(.headline, size: 17, weight: .semibold)]
        bar.largeTitleTextAttributes = [.font: uiFont(.largeTitle, size: 34, weight: .semibold)]
    }
    #endif

    /// Called before the first window is built, so UIKit bars pick the face up.
    @MainActor static func prepare() {
        _ = isAvailable
        #if os(iOS)
        styleNavigationBars()
        #endif
    }
}

extension Font {
    /// The app's face for a text style. Use instead of `.headline`, `.body` and so on.
    static func app(_ style: Font.TextStyle = .body) -> Font {
        guard AppFont.isAvailable else { return .system(style) }
        let font = Font.custom(AppFont.family, size: AppFont.size(for: style), relativeTo: style)
        return style == .headline ? font.weight(AppFont.headlineWeight) : font
    }

    /// A fixed point size of the app's face that still grows with Dynamic
    /// Type relative to `style`. Use instead of `.system(size:)`.
    static func app(size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        guard AppFont.isAvailable else { return .system(size: size, weight: weight) }
        return Font.custom(AppFont.family, size: (size * AppFont.opticalScale).rounded(toPlaces: 1), relativeTo: style)
            .weight(weight)
    }
}

/// The app's typeface as every view's default. Applied outermost on each
/// window's root, so sheets presented from anywhere beneath inherit it.
struct AppTypography: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.app())
    }
}

private extension CGFloat {
    func rounded(toPlaces places: Int) -> CGFloat {
        let factor = pow(10, CGFloat(places))
        return (self * factor).rounded() / factor
    }
}

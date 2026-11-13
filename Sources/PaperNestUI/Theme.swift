import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Reference palette with explicit dark counterparts; document paper stays white.
enum Theme {
    static let accent = adaptive(0x7545F8, 0xC5AEFF)
    static let violet = adaptive(0xB9A5FF, 0xB9A5FF)
    static let libraryBackground = adaptive(0xFAF9FF, 0x171522)
    static let sidebar = adaptive(0xF4EFFF, 0x211C30)
    static let canvas = adaptive(0xFAF9FF, 0x11101A)
    static let surface = adaptive(0xFFFFFF, 0x25293C)
    static let preview = adaptive(0xEEF0FA, 0x1C2031)
    static let paperShadow = Color.black.opacity(0.12)
    static let separator = adaptive(0xEAE6F2, 0x494256)
    static let selection = adaptive(0xE4DAFF, 0x443361)
    static let primaryText = adaptive(0x17172B, 0xF6F2FF)
    static let secondaryText = adaptive(0x77768C, 0xBAB6CB)
    static let radius: CGFloat = 18
    // Filled actions retain contrast with their existing white labels in both appearances.
    static let gradient = LinearGradient(colors: [adaptive(0x7545F8, 0x6839D8), adaptive(0x6737DA, 0x7545F8)], startPoint: .leading, endPoint: .trailing)
    static let headerGradient = LinearGradient(colors: [Color(red: 0.12, green: 0.21, blue: 0.38), Color(red: 0.39, green: 0.30, blue: 0.48)], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        func components(_ hex: UInt32) -> (CGFloat, CGFloat, CGFloat) {
            (CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255)
        }
        let l = components(light), d = components(dark)
        #if os(iOS)
        return Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? d : l
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #else
        return Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? d : l
            return NSColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #endif
    }
}

struct PremiumCard: ViewModifier {
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content
            .background(Theme.surface.opacity(reduceTransparency ? 1 : 0.92), in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay { RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.separator.opacity(0.65), lineWidth: 0.5) }
            .shadow(color: .black.opacity(hovered ? 0.07 : 0.035), radius: hovered ? 16 : 12, y: 4)
            .offset(y: hovered && !reduceMotion ? -2 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hovered)
            .onHover { hovered = $0 }
    }
}

struct PremiumButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

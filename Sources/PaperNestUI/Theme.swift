import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Reference palette with explicit dark counterparts; document paper stays white.
enum Theme {
    static let accent = adaptive(0x5264FF, 0xA5B0FF)
    static let violet = adaptive(0x9667FF, 0xBF9CFF)
    static let libraryBackground = adaptive(0xF8F9FF, 0x141623)
    static let sidebar = adaptive(0xF0F2FF, 0x1B1E30)
    static let canvas = adaptive(0xEDF0FA, 0x11131D)
    static let surface = adaptive(0xFFFFFF, 0x25293C)
    static let preview = adaptive(0xEEF0FA, 0x1C2031)
    static let paperShadow = Color.black.opacity(0.12)
    static let separator = adaptive(0xDDE1F3, 0x41465E)
    static let radius: CGFloat = 18
    static let gradient = LinearGradient(colors: [Color(red: 0.32, green: 0.39, blue: 1), Color(red: 0.59, green: 0.40, blue: 1)], startPoint: .leading, endPoint: .trailing)
    static let headerGradient = LinearGradient(colors: [Color(red: 0.12, green: 0.21, blue: 0.38), Color(red: 0.39, green: 0.30, blue: 0.48)], startPoint: .topLeading, endPoint: .bottomTrailing)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
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

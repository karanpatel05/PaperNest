import SwiftUI

/// Native semantic colors keep the light, paper-focused workspace readable
/// in Dark Mode and with increased contrast, too.
enum Theme {
    static let accent = Color.blue
    static let paperShadow = Color.black.opacity(0.12)
    static let separator = Color.primary.opacity(0.08)

    #if os(iOS)
    /// The library is white (black in Dark Mode) so gray preview tiles
    /// stand out, as in the mockups; the editor keeps the gray canvas.
    static let libraryBackground = Color(uiColor: .systemBackground)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let preview = Color(uiColor: .secondarySystemBackground)
    #else
    static let libraryBackground = Color(nsColor: .textBackgroundColor)
    static let canvas = Color(nsColor: .underPageBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let preview = Color(nsColor: .windowBackgroundColor)
    #endif
}

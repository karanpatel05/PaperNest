import PaperNestUI
import SwiftUI

/// iPhone and iPad app. Status: implemented, not yet compiled; the first
/// build needs full Xcode with the iOS SDK (see docs/SESSION_HANDOFF.md).
@main
struct PaperNestPhoneApp: App {
    @State private var session = LibrarySession()

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
        }
        .commands {
            // Hardware-keyboard shortcuts on iPad.
            PaperNestCommands()
        }
    }
}

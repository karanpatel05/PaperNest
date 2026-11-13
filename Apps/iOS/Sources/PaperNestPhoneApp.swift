import PaperNestUI
import SwiftUI

/// iPhone and iPad app. Status: implemented, not yet compiled; the first
/// build needs full Xcode with the iOS SDK (see docs/SESSION_HANDOFF.md).
@main
struct PaperNestPhoneApp: App {
    @State private var session = LibrarySession()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
        }
        // Coming to the front is when another device's work is most likely
        // to be waiting in iCloud.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await session.appBecameActive() } }
        }
        .commands {
            // Hardware-keyboard shortcuts on iPad.
            PaperNestCommands()
        }
    }
}

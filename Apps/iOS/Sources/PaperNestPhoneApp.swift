import PaperNestUI
import SwiftUI

/// iPhone and iPad app. Status: implemented, not yet compiled; the first
/// build needs full Xcode with the iOS SDK (see docs/SESSION_HANDOFF.md).
@main
struct PaperNestPhoneApp: App {
    @State private var session = LibrarySession()
    /// Settings → Privacy. Read before the first frame, so a locked library
    /// never shows, even for a moment.
    @State private var appLock = AppLock()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
                .appLocked(appLock)
        }
        // Coming to the front is when another device's work is most likely
        // to be waiting in iCloud.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await session.appBecameActive() } }
        }
        // From the first phase on: a launch is often already active, and a
        // plain onChange would never hear it.
        .onChange(of: scenePhase, initial: true) { _, phase in
            appLock.scenePhaseChanged(phase)
        }
        .commands {
            // Hardware-keyboard shortcuts on iPad.
            PaperNestCommands(isLocked: appLock.hidesLibrary)
        }
    }
}

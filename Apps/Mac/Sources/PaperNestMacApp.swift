import AppKit
import PaperNestCore
import PaperNestUI
import SwiftUI

/// Native macOS app. Built by the Xcode project (project.yml) for release,
/// and by `scripts/build-mac-app.sh` with Command Line Tools for development.
@main
struct PaperNestMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = LibrarySession()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup(Brand.displayName) {
            RootView(session: session)
                .frame(minWidth: 760, minHeight: 520)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await session.appBecameActive() } }
        }
        .commands {
            PaperNestCommands()
        }

        // PaperNest > Settings… (⌘,)
        Settings {
            SettingsView(session: session)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`); harmless
        // inside an app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            sender.reply(toApplicationShouldTerminate: await PaperNestPendingEdits.finishAll())
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

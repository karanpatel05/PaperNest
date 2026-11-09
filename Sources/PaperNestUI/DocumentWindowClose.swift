import Foundation
#if os(macOS)
import AppKit
#endif

extension DocumentTabs {
    /// Unlike ordinary navigation, destroying the window releases every tab's
    /// transient tool drafts. Ask once, then flush text from all retained tabs.
    /// Do not clear drafts: another window may subsequently cancel app quit.
    func prepareWindowClose(confirmDiscard: () -> Bool) async -> Bool {
        guard !isChanging, !entries.contains(where: { $0.isToolBusy }) else { return false }
        let closingEntries = entries
        if closingEntries.contains(where: { $0.hasUnsavedToolDrafts }), !confirmDiscard() { return false }
        for entry in closingEntries {
            guard !entry.isToolBusy, await entry.textSession.finish(undoManager: entry.undoManager) else { return false }
        }
        // A tab added during an async text flush has not been checked yet.
        guard entries.map(\.id) == closingEntries.map(\.id),
              !entries.contains(where: { $0.isToolBusy }) else { return false }
        return true
    }

    #if os(macOS)
    func confirmWindowClose() async -> Bool {
        await prepareWindowClose {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.closeDraftTitle
            alert.informativeText = L10n.closeDraftMessage
            // Keep Open is the default keyboard action; discard is explicit.
            alert.addButton(withTitle: L10n.keepDocumentOpen)
            alert.addButton(withTitle: L10n.inlineDiscardDraft)
            return alert.runModal() == .alertSecondButtonReturn
        }
    }
    #endif
}

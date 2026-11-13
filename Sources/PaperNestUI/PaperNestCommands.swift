import SwiftUI

/// Menu bar commands (Mac) and hardware-keyboard shortcuts (iPad).
public struct PaperNestCommands: Commands {
    @FocusedValue(\.libraryModel) private var library
    @FocusedValue(\.documentCommands) private var document
    @FocusedValue(\.documentPrinter) private var printer
    @FocusedValue(\.readerBookmarks) private var bookmarks

    public init() {}

    public var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(L10n.importFiles) {
                Task { @MainActor in
                    guard await document?.beforeAction?() ?? true else { return }
                    library?.isShowingFileImporter = true
                }
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(library == nil)

            Button(L10n.addPages) { document?.showAddPages() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(document == nil)

            Button(L10n.export) { document?.showExport() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(document?.model.pages.isEmpty ?? true)
        }

        // File > Print…, where every Mac app keeps it, and ⌘P on an iPad's
        // keyboard. SwiftUI puts nothing there by itself.
        CommandGroup(replacing: .printItem) {
            Button(L10n.printMenu) {
                let printer = printer
                run { printer?.print($0.model.itemID, in: $0.model.session.environment) }
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(printer == nil || (document?.model.pages.isEmpty ?? true))
        }

        CommandMenu(L10n.menuPage) {
            // Contents is document-level rather than page-level, but this is
            // the menu that already carries the document's structure — moving
            // and deleting pages — and jumping to a section belongs with
            // those. Deliberately without a keyboard shortcut: this project
            // has been bitten by clashes with system ones, and the simulator
            // that logs them cannot run here today.
            Button(L10n.outline) { document?.showOutline() }
                .disabled(document?.model.pages.isEmpty ?? true)
            // Find has ⌘F, but on the editor's own button: the system keeps
            // a Find submenu under Edit with the same key, and two menu
            // items sharing one is the clash this project has met before.
            Button(L10n.findMenu) { document?.showFind() }
                .disabled(document?.model.pages.isEmpty ?? true)
            Button(L10n.goToPage) { document?.showGoToPage() }
                .disabled((document?.model.pages.count ?? 0) < 2)
            // ⌘D, as in Preview and Safari. Marks the page being read, or
            // takes its mark away.
            Button(bookmarks?.isBookmarked(document?.model.selectedPageID) == true
                   ? L10n.bookmarkRemove : L10n.bookmarkAdd) {
                let bookmarks = bookmarks
                run { await bookmarks?.toggle(on: $0.model.selectedPageID) }
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(bookmarks == nil || document?.model.selectedPage == nil)
            Button(L10n.bookmarkList) {
                let bookmarks = bookmarks
                run { _ in bookmarks?.isShowingList = true }
            }
            .disabled(bookmarks == nil || (document?.model.pages.isEmpty ?? true))
            Button(L10n.textBox) { document?.showTextBox() }
                .disabled(document?.model.selectedPage == nil)
            Button(L10n.insertImage) { document?.showInsertImage() }
                .disabled(document?.model.selectedPage == nil)
            Divider()
            Button(L10n.rotateLeft) { run { await $0.model.rotate(clockwise: false, undoManager: $0.undoManager) } }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(document?.model.selectedPage == nil)
            Button(L10n.rotateRight) { run { await $0.model.rotate(clockwise: true, undoManager: $0.undoManager) } }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(document?.model.selectedPage == nil)
            Button(L10n.replacePageWithFile) { document?.showReplacePage() }
                .disabled(document?.model.selectedPage == nil)
            Button(L10n.cropMenuItem) { document?.showCrop() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(document?.model.selectedPage == nil)
            Divider()
            Button(L10n.movePageUp) { run { await $0.model.moveSelected(by: -1, undoManager: $0.undoManager) } }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled((document?.model.selectedIndex ?? 0) == 0)
            Button(L10n.movePageDown) { run { await $0.model.moveSelected(by: 1, undoManager: $0.undoManager) } }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(document.map { ($0.model.selectedIndex ?? Int.max) >= $0.model.pages.count - 1 } ?? true)
            Divider()
            Button(L10n.revertToOriginal) { run { await $0.model.revertToOriginal(undoManager: $0.undoManager) } }
                .disabled(document?.model.selectedPage?.transform == .identity || document?.model.selectedPage == nil)
            Button(L10n.deletePage) { run { await $0.model.deleteSelectedPage(undoManager: $0.undoManager) } }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(document?.model.selectedPage == nil)
        }
    }

    private func run(_ action: @escaping @MainActor (DocumentCommandContext) async -> Void) {
        guard let document else { return }
        Task { @MainActor in
            guard await document.beforeAction?() ?? true else { return }
            await action(document)
        }
    }
}

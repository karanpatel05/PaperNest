import SwiftUI

/// Menu bar commands (Mac) and hardware-keyboard shortcuts (iPad).
public struct PaperNestCommands: Commands {
    @FocusedValue(\.libraryModel) private var library
    @FocusedValue(\.documentCommands) private var document

    public init() {}

    public var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(L10n.importFiles) {
                library?.isShowingFileImporter = true
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

        CommandMenu(L10n.menuPage) {
            Button(L10n.rotateLeft) { run { await $0.model.rotate(clockwise: false, undoManager: $0.undoManager) } }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(document?.model.selectedPage == nil)
            Button(L10n.rotateRight) { run { await $0.model.rotate(clockwise: true, undoManager: $0.undoManager) } }
                .keyboardShortcut("r", modifiers: .command)
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
        Task { @MainActor in await action(document) }
    }
}

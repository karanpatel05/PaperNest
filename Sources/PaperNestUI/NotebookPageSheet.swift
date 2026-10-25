import Combine
import PaperNestCore
import SwiftUI

struct NotebookPageRequest: Identifiable {
    let id = UUID()
    let after: PageID?
    let template: PageTemplate
}

struct NotebookPageSheet: View {
    let model: DocumentModel
    let request: NotebookPageRequest
    let undoManager: UndoManager?
    @Environment(\.dismiss) private var dismiss
    @State private var template: PageTemplate
    @State private var saving = false
    @State private var failed = false

    init(model: DocumentModel, request: NotebookPageRequest, undoManager: UndoManager?) {
        self.model = model
        self.request = request
        self.undoManager = undoManager
        _template = State(initialValue: request.template)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(PageTemplate.allCases, id: \.self) { paper in
                        Button { template = paper } label: {
                            HStack {
                                Text(paper.notebookTitle)
                                Spacer()
                                Image(systemName: template == paper ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(Theme.accent)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("add-page-paper-\(paper.rawValue)")
                        .accessibilityValue(template == paper ? L10n.selectionOn : L10n.selectionOff)
                    }
                } header: { Text(L10n.notebookPaper) }
                  footer: { Text(L10n.notebookPageFooter) }
            }
            .formStyle(.grouped)
            .disabled(saving || model.isChangingNotebookPage)
            .navigationTitle(L10n.notebookPageTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                        .disabled(saving)
                        .accessibilityIdentifier("add-page-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.createDocument) { Task { await create() } }
                        .disabled(saving || model.isChangingNotebookPage)
                        .accessibilityIdentifier("add-page-create")
                }
            }
            .interactiveDismissDisabled(saving)
            .alert(L10n.genericErrorTitle, isPresented: $failed) {
                Button(L10n.ok) {}
            } message: { Text(L10n.saveFailed) }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 340)
        #endif
    }

    private func create() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            try await model.addNotebookPage(template, after: request.after, undoManager: undoManager)
            dismiss()
        } catch { failed = true }
    }
}

/// Observe the native manager: its canUndo/canRedo properties are not observable
/// SwiftUI state. These actions also make notebook history accessible on phones.
struct NotebookHistoryActions: View {
    let undoManager: UndoManager?
    let busy: Bool
    @State private var revision = 0

    var body: some View {
        Group {
            Button { undoManager?.undo() } label: {
                Label(L10n.notebookUndo, systemImage: "arrow.uturn.backward")
            }
            .disabled(busy || undoManager?.canUndo != true)
            .accessibilityIdentifier("notebook-undo")
            Button { undoManager?.redo() } label: {
                Label(L10n.notebookRedo, systemImage: "arrow.uturn.forward")
            }
            .disabled(busy || undoManager?.canRedo != true)
            .accessibilityIdentifier("notebook-redo")
        }
        .id(revision)
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidCloseUndoGroup, object: undoManager)) { _ in revision &+= 1 }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange, object: undoManager)) { _ in revision &+= 1 }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange, object: undoManager)) { _ in revision &+= 1 }
    }
}

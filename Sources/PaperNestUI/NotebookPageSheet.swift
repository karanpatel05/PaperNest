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
                            HStack(spacing: 12) {
                                Image(systemName: paper == .blank ? "doc" : (paper == .grid ? "square.grid.3x3" : "doc.text"))
                                    .font(.title3)
                                    .foregroundStyle(EditorChrome.purple)
                                    .frame(width: 40, height: 44)
                                    .background(EditorChrome.surface, in: RoundedRectangle(cornerRadius: 8))
                                    .accessibilityHidden(true)
                                Text(paper.notebookTitle).font(.body.weight(.medium))
                                Spacer()
                                Image(systemName: template == paper ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(Theme.accent)
                            }
                            .padding(10)
                            .background(template == paper ? EditorChrome.lavender : EditorChrome.surface,
                                        in: RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(template == paper ? EditorChrome.purple.opacity(0.45) : EditorChrome.border, lineWidth: 1)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("add-page-paper-\(paper.rawValue)")
                        .accessibilityValue(template == paper ? L10n.selectionOn : L10n.selectionOff)
                    }
                } header: { Text(L10n.notebookPaper) }
                  footer: { Text(L10n.notebookPageFooter) }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(EditorChrome.secondaryBackground)
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
        .toolPanelAppearance()
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
///
/// The notifications cover an undo and a redo, but **not a registration made
/// from inside a `Task`**, which is how every ink edit registers. Without
/// `historyRevision` the row kept showing the state from before the stroke —
/// Undo greyed out on the mark just drawn, Redo lit with nothing to redo —
/// until something else happened to refresh it. The model supplies that
/// revision because only it knows when it has touched the stack.
struct NotebookHistoryActions: View {
    let undoManager: UndoManager?
    let busy: Bool
    /// `DocumentModel.historyRevision`, or 0 where there is no document.
    var historyRevision = 0
    var beforeAction: (() async -> Bool)? = nil
    @State private var revision = 0

    var body: some View {
        Group {
            Button { Task { if await beforeAction?() ?? true { undoManager?.undo() } } } label: {
                Label(L10n.notebookUndo, systemImage: "arrow.uturn.backward")
            }
            .disabled(busy || undoManager?.canUndo != true)
            .accessibilityIdentifier("notebook-undo")
            Button { Task { if await beforeAction?() ?? true { undoManager?.redo() } } } label: {
                Label(L10n.notebookRedo, systemImage: "arrow.uturn.forward")
            }
            .disabled(busy || undoManager?.canRedo != true)
            .accessibilityIdentifier("notebook-redo")
        }
        .id(revision &+ historyRevision)
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidCloseUndoGroup, object: undoManager)) { _ in revision &+= 1 }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange, object: undoManager)) { _ in revision &+= 1 }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange, object: undoManager)) { _ in revision &+= 1 }
    }
}

import PaperNestCore
import SwiftUI

struct NotebookCreationSheet: View {
    let model: LibraryModel
    let created: (ItemID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var template: PageTemplate = .blank
    @State private var saving = false
    @State private var failed = false
    @State private var showPro = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.documentName, text: $name)
                        .accessibilityIdentifier("notebook-name")
                }
                Section {
                    ForEach(PageTemplate.allCases, id: \.self) { paper in
                        Button {
                            template = paper
                        } label: {
                            HStack {
                                Text(paper.notebookTitle)
                                Spacer()
                                Image(systemName: template == paper ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(Theme.accent)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("notebook-paper-\(paper.rawValue)")
                        .accessibilityValue(template == paper ? L10n.selectionOn : L10n.selectionOff)
                    }
                } header: {
                    Text(L10n.notebookPaper)
                } footer: {
                    Text(L10n.notebookFooter)
                }
            }
            .formStyle(.grouped)
            .disabled(saving)
            .navigationTitle(L10n.newNotebook)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.createDocument) { Task { await save() } }
                        .accessibilityIdentifier("notebook-create")
                        .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert(L10n.genericErrorTitle, isPresented: $failed) {
                Button(L10n.ok) {}
            } message: { Text(L10n.saveFailed) }
            .interactiveDismissDisabled(saving)
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 350)
        #endif
        .sheet(isPresented: $showPro) { ProPaywallView(store: .shared) }
    }

    private func save() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            let id = try await model.createNotebook(named: name, template: template)
            created(id)
            dismiss()
        } catch is ProAccessError { showPro = true } catch { failed = true }
    }
}

extension PageTemplate {
    var notebookTitle: String {
        switch self {
        case .blank: L10n.notebookBlank
        case .lined: L10n.notebookLined
        case .grid: L10n.notebookGrid
        }
    }
}

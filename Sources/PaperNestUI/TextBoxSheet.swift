import CoreGraphics
import PaperNestCore
import PaperNestStore
import SwiftUI

/// Puts typed text on a page, or changes a box already on one.
///
/// Where a **new** box lands is decided by `DocumentModel.addTextBox` rather
/// than here, because nothing can place a box by hand yet: this collects what
/// to write, not where. Saying so plainly is better than a preview that
/// implies a position the caller cannot choose. An **existing** box keeps
/// where it is; only its height follows the type size.
struct TextBoxSheet: View {
    let model: DocumentModel
    let pageID: PageID
    let undoManager: UndoManager?
    /// The box being changed, or nil when a new one is being written.
    var editing: PageObject?

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var fontSize: Double = 18
    @State private var alignment: TextBox.Alignment = .leading
    @State private var color: RGBAColor = .init(red: 0, green: 0, blue: 0, alpha: 1)
    @State private var isSaving = false
    @State private var failed = false

    private var page: Page? { model.pages.first { $0.id == pageID } }
    private var canAdd: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving && page != nil
    }

    /// The box as it stands now, by id, rather than the copy this sheet was
    /// opened with: between opening and saving an undo may have put a
    /// different version of it back, and the guarded write compares values.
    private var current: PageObject? {
        guard let editing else { return nil }
        return model.selectedPageObjects.first { $0.id == editing.id }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.textBoxText) {
                    TextField(L10n.textBoxText, text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityIdentifier("text-box-text")
                }
                Section {
                    Stepper(value: $fontSize, in: 10...72, step: 2) {
                        LabeledContent(L10n.textBoxSize, value: "\(Int(fontSize))")
                    }
                    .accessibilityIdentifier("text-box-size")
                    // Segmented rather than a pop-up: French and Spanish
                    // values truncate in pop-up menus, and these three are
                    // short enough to sit side by side.
                    Picker(L10n.textBoxAlignment, selection: $alignment) {
                        Text(L10n.textBoxAlignLeft).tag(TextBox.Alignment.leading)
                        Text(L10n.textBoxAlignCenter).tag(TextBox.Alignment.center)
                        Text(L10n.textBoxAlignRight).tag(TextBox.Alignment.trailing)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("text-box-alignment")
                    MarkupColorPicker(color: $color)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(EditorChrome.secondaryBackground)
            .navigationTitle(editing == nil ? L10n.textBox : L10n.textBoxEdit)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                        .accessibilityIdentifier("text-box-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? L10n.textBoxAdd : L10n.textBoxSave) { Task { await save() } }
                        .disabled(!canAdd)
                        .accessibilityIdentifier("text-box-add")
                }
            }
            .onAppear { load() }
            .alert(L10n.genericErrorTitle, isPresented: $failed) {
                Button(L10n.ok) {}
            } message: {
                Text(L10n.saveFailed)
            }
        }
        .toolPanelAppearance()
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 360, idealHeight: 420)
        #endif
    }

    /// Fills the form from the box being changed, so the sheet opens showing
    /// what is on the page rather than the defaults.
    private func load() {
        guard case .text(let box)? = editing?.payload else { return }
        text = box.text
        fontSize = box.fontSize
        alignment = box.alignment
        color = box.color
    }

    private func save() async {
        guard let page else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            if let object = current {
                try await model.editTextBox(object, on: page, text: text, fontSize: fontSize,
                                            color: color, alignment: alignment,
                                            undoManager: undoManager)
            } else if editing == nil {
                try await model.addTextBox(to: page, text: text, fontSize: fontSize,
                                           color: color, alignment: alignment,
                                           undoManager: undoManager)
            } else {
                // The box went away while this was open — undone, or removed
                // from the markup manager. Writing it back would resurrect
                // something the user took off the page.
                failed = true
                return
            }
            dismiss()
        } catch { failed = true }
    }
}

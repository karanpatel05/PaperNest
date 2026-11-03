import CoreGraphics
import PaperNestCore
import PaperNestStore
import SwiftUI

/// Puts typed text on a page.
///
/// Where it lands is decided by `DocumentModel.addTextBox` rather than here,
/// because nothing can place a box by hand yet: this collects what to write,
/// not where. Saying so plainly is better than a preview that implies a
/// position the caller cannot choose.
struct TextBoxSheet: View {
    let model: DocumentModel
    let pageID: PageID
    let undoManager: UndoManager?

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
            .navigationTitle(L10n.textBox)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                        .accessibilityIdentifier("text-box-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.textBoxAdd) { Task { await add() } }
                        .disabled(!canAdd)
                        .accessibilityIdentifier("text-box-add")
                }
            }
            .alert(L10n.genericErrorTitle, isPresented: $failed) {
                Button(L10n.ok) {}
            } message: {
                Text(L10n.saveFailed)
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 360, idealHeight: 420)
        #endif
    }

    private func add() async {
        guard let page else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await model.addTextBox(to: page, text: text, fontSize: fontSize,
                                       color: color, alignment: alignment,
                                       undoManager: undoManager)
            dismiss()
        } catch { failed = true }
    }
}

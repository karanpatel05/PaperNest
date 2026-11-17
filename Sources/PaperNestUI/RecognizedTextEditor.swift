import PaperNestCore
import PaperNestStore
import SwiftUI

/// Corrects what recognition read on one page, line by line.
///
/// The page is shown above its lines with the line being edited outlined on
/// it, so a misread word can be checked against the paper. Each line keeps
/// its place on the page; clearing one removes it. Nothing is written until
/// Save, and Save writes only if the page still holds what the editor opened
/// with — a page recognized again meanwhile says so instead of being
/// overwritten. The correction is one step of the document's undo history.
struct RecognizedTextEditor: View {
    let model: DocumentModel
    let page: Page
    let pageNumber: Int
    let pageCount: Int
    let recognition: PageRecognition
    let undoManager: UndoManager?

    @Environment(\.dismiss) private var dismiss
    @State private var texts: [String]
    @FocusState private var focused: Int?
    /// The line outlined on the page: the one being edited, or the last one
    /// that was, so the outline stays put while the keyboard is down.
    @State private var outlined: Int?
    @State private var saving = false
    @State private var problem: String?
    @State private var confirmingDiscard = false

    init(model: DocumentModel, page: Page, pageNumber: Int, pageCount: Int,
         recognition: PageRecognition, undoManager: UndoManager?) {
        self.model = model
        self.page = page
        self.pageNumber = pageNumber
        self.pageCount = pageCount
        self.recognition = recognition
        self.undoManager = undoManager
        _texts = State(initialValue: recognition.lines.map(\.text))
    }

    private var changedCount: Int { zip(texts, recognition.lines).filter { $0 != $1.text }.count }
    private var hasChanges: Bool { changedCount > 0 }

    var body: some View {
        #if os(iOS)
        NavigationStack {
            content
                .navigationTitle(L10n.ocrCorrectTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.cancel) { cancel() }
                            .accessibilityIdentifier("ocr-correct-cancel")
                    }
                }
                // Save at the bottom, as in the other tool sheets, rather
                // than in a bar that can scroll away on some iPhones.
                .safeAreaInset(edge: .bottom) {
                    footer
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(EditorChrome.surface)
                }
        }
        .interactiveDismissDisabled(hasChanges || saving)
        .modifier(DiscardConfirmation(isPresented: $confirmingDiscard, discard: { dismiss() }))
        #else
        VStack(spacing: 0) {
            HStack {
                Text(L10n.ocrCorrectTitle).font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Button(L10n.cancel) { cancel() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("ocr-correct-cancel")
            }
            .padding(16)
            content
            footer.padding(16).background(EditorChrome.surface)
        }
        .frame(minWidth: 520, idealWidth: 640, minHeight: 520, idealHeight: 720)
        .modifier(DiscardConfirmation(isPresented: $confirmingDiscard, discard: { dismiss() }))
        #endif
    }

    private var content: some View {
        VStack(spacing: 0) {
            preview
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .containerRelativeFrame(.vertical) { length, _ in min(300, length * 0.36) }
                .background(EditorChrome.secondaryBackground)
            List {
                Section {
                    ForEach(texts.indices, id: \.self) { row($0) }
                } header: {
                    Text(L10n.pageLabel(pageNumber, of: pageCount))
                } footer: {
                    Text(L10n.ocrCorrectHelp)
                }
            }
            .accessibilityIdentifier("ocr-correct-lines")
        }
        .onChange(of: focused) { _, index in if let index { outlined = index } }
    }

    // MARK: - The page

    private var preview: some View {
        PageImageView(page: page, pixelSize: 1000)
            .overlay {
                GeometryReader { geometry in outline(in: geometry.size) }
                    .clipped()
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 16)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.pageLabel(pageNumber, of: pageCount))
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("ocr-correct-preview")
            // Which line is outlined, 1-based; empty for none.
            .accessibilityValue(outlined.map { String($0 + 1) } ?? "")
    }

    /// The outlined line, placed through `PageGeometry`: recognition boxes
    /// live in upright, uncropped source space and the picture shows the
    /// page cropped and turned, which is exactly what that mapping is for.
    @ViewBuilder private func outline(in size: CGSize) -> some View {
        if let index = outlined, recognition.lines.indices.contains(index) {
            let pageSize = page.geometry.pageSize
            let scale = size.width / max(pageSize.width, 1)
            let rect = page.geometry.pageRect(forNormalizedSourceRect: recognition.lines[index].box)
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.accent.opacity(0.16))
                .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.accent, lineWidth: 1.5) }
                .frame(width: rect.width * scale + 6, height: rect.height * scale + 6)
                .position(x: rect.midX * scale, y: rect.midY * scale)
        }
    }

    // MARK: - The lines

    private func row(_ index: Int) -> some View {
        let line = recognition.lines[index]
        let changed = texts[index] != line.text
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: "\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 22, alignment: .trailing)
                .accessibilityHidden(true)
            TextField(L10n.ocrCorrectLine(index + 1), text: $texts[index], axis: .vertical)
                .focused($focused, equals: index)
                .autocorrectionDisabled()
                .accessibilityLabel(L10n.ocrCorrectLine(index + 1))
                .accessibilityIdentifier("ocr-line-\(index)")
            if changed {
                Image(systemName: "pencil.circle.fill")
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel(L10n.ocrCorrectChanged)
                    .accessibilityIdentifier("ocr-line-\(index)-changed")
            } else if line.confidence < 0.5 {
                // Vision was unsure of it: the likeliest place for a misreading.
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(L10n.ocrCorrectUnsure)
                    .accessibilityIdentifier("ocr-line-\(index)-unsure")
            }
        }
    }

    // MARK: - Save

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let problem {
                Text(verbatim: problem)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ocr-correct-problem")
            }
            HStack(spacing: 12) {
                Text(L10n.ocrCorrectChangedCount(changedCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ocr-correct-count")
                    .accessibilityValue(String(changedCount))
                Spacer(minLength: 8)
                Button { save() } label: {
                    Text(L10n.ocrCorrectSave).frame(minWidth: 80, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!hasChanges || saving)
                .accessibilityIdentifier("ocr-correct-save")
            }
        }
    }

    private func cancel() {
        if hasChanges { confirmingDiscard = true } else { dismiss() }
    }

    private func save() {
        guard hasChanges, !saving else { return }
        saving = true
        problem = nil
        let typed = texts
        Task {
            defer { saving = false }
            do {
                // The model reloads only after the store has committed.
                try await model.correctRecognition(on: page.id, expected: recognition, texts: typed,
                                                   undoManager: undoManager)
                dismiss()
            } catch StoreError.recognitionChanged {
                problem = L10n.ocrCorrectionChanged
            } catch {
                problem = L10n.saveFailed
            }
        }
    }
}

/// Asks before throwing corrections away.
private struct DiscardConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    let discard: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(L10n.ocrCorrectDiscardTitle, isPresented: $isPresented, titleVisibility: .visible) {
            Button(L10n.ocrCorrectDiscard, role: .destructive) { discard() }
                .accessibilityIdentifier("ocr-correct-discard")
            Button(L10n.ocrCorrectKeepEditing, role: .cancel) {}
        }
    }
}

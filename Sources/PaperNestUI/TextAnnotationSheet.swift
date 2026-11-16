import PaperNestCore
import PaperNestStore
import SwiftUI

/// Selects full OCR lines, never approximated words. Marks remain editable
/// ink; a snapshot check at commit prevents marking a different capture.
struct TextAnnotationSheet: View {
    @Bindable var model: DocumentModel
    let pageID: PageID
    let undoManager: UndoManager?
    @Environment(\.dismiss) private var dismiss
    @State private var page: Page?
    @State private var recognition: PageRecognition?
    @State private var selection: Set<Int> = []
    @State private var style: TextMarkupStyle

    init(model: DocumentModel, pageID: PageID, undoManager: UndoManager?, initialStyle: TextMarkupStyle = .highlight) {
        self.model = model
        self.pageID = pageID
        self.undoManager = undoManager
        _style = State(initialValue: initialStyle)
    }
    @State private var chosenColor: RGBAColor?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var proFeature: ProFeature?

    private var busy: Bool { isLoading || isSaving || model.isRecognizing }

    var body: some View {
        NavigationStack {
            Form {
                if let page {
                    Section {
                        PageImageView(page: page, pixelSize: 480)
                            .frame(maxWidth: .infinity).frame(height: 160)
                            .padding(12)
                            .background(EditorChrome.surface, in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityHidden(true)
                    }
                }
                Section(L10n.annotationStyle) {
                    ForEach(TextMarkupStyle.allCases, id: \.self) { option in
                        Button { style = option } label: {
                            HStack {
                                Label(option.title, systemImage: option.symbol)
                                Spacer()
                                if style == option { Image(systemName: "checkmark") }
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(style == option ? EditorChrome.lavender : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("annotation-style-\(option.rawValue)")
                        .accessibilityValue(style == option ? L10n.selectionOn : L10n.selectionOff)
                    }
                }
                Section(L10n.markupColor) {
                    MarkupColorPicker(color: Binding(get: { chosenColor ?? style.defaultColor }, set: { chosenColor = $0 }))
                }
                Section {
                    if busy {
                        ProgressView().accessibilityIdentifier("annotation-progress")
                    } else if let recognition, !recognition.lines.isEmpty {
                        ForEach(Array(recognition.lines.enumerated()), id: \.offset) { index, line in
                            Button {
                                if !selection.insert(index).inserted { selection.remove(index) }
                            } label: {
                                HStack {
                                    Text(verbatim: line.text).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: selection.contains(index) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(Theme.accent)
                                }
                                .padding(10)
                                .frame(minHeight: 44)
                                .background(selection.contains(index) ? EditorChrome.lavender : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("annotation-line-\(index)")
                            .accessibilityValue(selection.contains(index) ? L10n.selectionOn : L10n.selectionOff)
                        }
                    } else {
                        Text(L10n.annotationNoText).foregroundStyle(.secondary)
                        Button(L10n.recognizeText) {
                            guard SubscriptionStore.shared.allows(.textRecognition) else { proFeature = .textRecognition; return }
                            Task {
                                await model.recognizeText(on: pageID)
                                await load()
                            }
                        }
                        .accessibilityIdentifier("annotation-recognize")
                    }
                } header: {
                    Text(L10n.annotationLines)
                } footer: {
                    Text(L10n.annotationHelp)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(EditorChrome.secondaryBackground)
            .disabled(busy)
            .navigationTitle(L10n.annotateText)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                        .disabled(isSaving || model.isRecognizing)
                        .accessibilityIdentifier("annotation-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.annotationApply) { Task { await apply() } }
                        .disabled(busy || selection.isEmpty)
                        .accessibilityIdentifier("annotation-apply")
                }
            }
            .interactiveDismissDisabled(isSaving || model.isRecognizing)
            .task { await load() }
            .proPaywall($proFeature)
            .alert(L10n.genericErrorTitle, isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button(L10n.ok) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .toolPanelAppearance()
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 520, minHeight: 480, idealHeight: 620)
        #endif
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        selection = []
        do {
            guard let store = model.session.environment?.store, let latest = try await store.page(pageID) else {
                throw StoreError.pageNotFound
            }
            page = latest
            let result = try await store.recognition(for: pageID)
            recognition = result?.status == .completed && result?.sourceRevision == latest.revision ? result : nil
        } catch { errorMessage = L10n.saveFailed }
    }

    private func apply() async {
        guard !busy, let recognition, !selection.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await model.addTextMarkup(recognition, lineIndices: selection, style: style, color: chosenColor, undoManager: undoManager)
            dismiss()
        } catch let error as ProAccessError {
            proFeature = error.feature
        } catch StoreError.recognitionChanged {
            await load()
            errorMessage = L10n.annotationChanged
        } catch { errorMessage = L10n.saveFailed }
    }
}

private extension TextMarkupStyle {
    var title: String {
        switch self {
        case .highlight: L10n.annotationHighlight
        case .underline: L10n.annotationUnderline
        case .strikethrough: L10n.annotationStrikethrough
        }
    }
    var symbol: String {
        switch self {
        case .highlight: "highlighter"
        case .underline: "underline"
        case .strikethrough: "strikethrough"
        }
    }
}

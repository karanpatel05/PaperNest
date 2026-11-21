import PaperNestCore
import PaperNestRender
import PaperNestStore
import SwiftUI

/// Handwriting someone asked to turn into text: the lasso's selection.
struct HandwritingRequest: Identifiable {
    let id = UUID()
    let objects: [PageObject]
}

/// Reads the selected handwriting on this device, shows the words to be
/// checked and corrected, and only then puts them on the page as a text box.
/// Nothing is written until Insert Text; Cancel leaves the page as it was.
///
/// Laid out as the owner's sample (`docs/FEATURE_UI_SAMPLES.md` §12): the
/// selected ink, the recognized text, Keep original ink or Replace selection,
/// and Cancel and Insert Text at the foot. The sample's Done at the top is
/// left out: beside Cancel and Insert Text it would only be a third way to
/// close, and it is not clear which of the other two it would mean.
struct HandwritingSheet: View {
    let model: DocumentModel
    let request: HandwritingRequest
    let undoManager: UndoManager?
    /// Called after the words are on the page, so the selection can go.
    let inserted: () -> Void
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case reading
        case read(DocumentModel.HandwritingReading)
        case nothing
        case failed
    }

    @State private var phase: Phase = .reading
    @State private var preview: CGImage?
    @State private var text = ""
    @State private var keepsInk = true
    @State private var isSaving = false
    @State private var failure: String?
    @State private var proFeature: ProFeature?

    private var canInsert: Bool {
        guard case .read = phase else { return false }
        return !isSaving && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                inkPreview
                content
            }
            .navigationTitle(L10n.handwritingTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        }
        .task { await read() }
        .proPaywall($proFeature)
        .alert(failure ?? "", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button(L10n.ok, role: .cancel) {}
        }
        .modifier(PageSizedSheet())
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 460)
        #endif
    }

    /// The selection's pen strokes as Vision is shown them, so the words can
    /// be checked against the writing they came from.
    @ViewBuilder private var inkPreview: some View {
        if let preview {
            Section {
                Image(preview, scale: 3, label: Text(L10n.handwritingPreview))
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 140)
                    .accessibilityIdentifier("handwriting-preview")
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .reading:
            HStack(spacing: 12) {
                ProgressView()
                Text(L10n.handwritingReading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("handwriting-reading")
        case .nothing:
            Text(L10n.handwritingNothing)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("handwriting-nothing")
        case .failed:
            Text(L10n.handwritingFailed)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("handwriting-failed")
        case .read(let reading):
            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 110)
                    .accessibilityLabel(L10n.handwritingRecognized)
                    .accessibilityValue(text)
                    .accessibilityIdentifier("handwriting-text")
            } header: {
                Text(L10n.handwritingRecognized)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.handwritingReview)
                    if !reading.unreadLanguages.isEmpty {
                        Text(L10n.handwritingUnread(ListFormatter.localizedString(
                            byJoining: reading.unreadLanguages.map(RecognitionLanguagePreference.name(of:)))))
                            .accessibilityIdentifier("handwriting-unread")
                    }
                }
            }
            Section {
                choice(L10n.handwritingKeep, isOn: keepsInk, id: "handwriting-keep") { keepsInk = true }
                choice(L10n.handwritingReplace, isOn: !keepsInk, id: "handwriting-replace") { keepsInk = false }
            } footer: {
                Text(keepsInk ? L10n.handwritingKeepOn : L10n.handwritingKeepOff)
                    .accessibilityIdentifier("handwriting-keep-note")
            }
        }
    }

    /// One of the two ways to insert, as an inline row: a pop-up menu would
    /// cut the French and Spanish wording short.
    private func choice(_ title: String, isOn: Bool, id: String, choose: @escaping () -> Void) -> some View {
        Button(action: choose) {
            HStack {
                Text(title).foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if isOn { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityValue(isOn ? L10n.selectionOn : L10n.selectionOff)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// Cancel and Insert Text at the foot, as in the sample; one above the
    /// other when the text is too large for them side by side.
    private var actions: some View {
        let cancel = Button(L10n.cancel) { dismiss() }
            .accessibilityIdentifier("handwriting-cancel")
        let insertButton = Button(L10n.handwritingInsert) { insert() }
            .buttonStyle(.borderedProminent)
            .disabled(!canInsert)
            .accessibilityIdentifier("handwriting-insert")
        return ViewThatFits(in: .horizontal) {
            HStack {
                cancel
                Spacer()
                insertButton
            }
            VStack(spacing: 10) {
                insertButton.frame(maxWidth: .infinity)
                cancel
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func read() async {
        guard phase == .reading else { return }
        let ink = DocumentModel.handwriting(in: request.objects).compactMap { object -> InkStroke? in
            if case .ink(let stroke) = object.payload { return stroke }
            return nil
        }
        preview = HandwritingRecognizer.picture(of: ink)?.image
        do {
            let reading = try await model.readHandwriting(request.objects)
            if reading.lines.isEmpty {
                phase = .nothing
            } else {
                text = reading.text
                phase = .read(reading)
            }
        } catch let error as ProAccessError {
            proFeature = error.feature
            phase = .failed
        } catch {
            phase = .failed
        }
    }

    private func insert() {
        guard case .read(let reading) = phase, canInsert else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await model.convertHandwriting(reading, to: text, keepingInk: keepsInk, undoManager: undoManager)
                inserted()
                dismiss()
            } catch StoreError.pageObjectsChanged {
                failure = L10n.markupChanged
            } catch {
                failure = L10n.handwritingFailed
            }
        }
    }
}

/// On an iPad the default form sheet was too short for the ink, the words and
/// both choices: Replace selection sat below its foot (2026-11-20). The page
/// size gives them room; before iOS 18 the sheet keeps its size and scrolls.
private struct PageSizedSheet: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.presentationSizing(.page)
        } else {
            content
        }
    }
}

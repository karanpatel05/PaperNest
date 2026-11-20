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
/// Nothing is written until Insert; Cancel leaves the page as it was.
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
            Form { content }
                .navigationTitle(L10n.handwritingTitle)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.cancel) { dismiss() }.accessibilityIdentifier("handwriting-cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.handwritingInsert) { insert() }
                            .disabled(!canInsert)
                            .accessibilityIdentifier("handwriting-insert")
                    }
                }
        }
        .task { await read() }
        .proPaywall($proFeature)
        .alert(failure ?? "", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button(L10n.ok, role: .cancel) {}
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 380)
        #endif
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
                    .frame(minHeight: 120)
                    .accessibilityLabel(L10n.handwritingTitle)
                    .accessibilityValue(text)
                    .accessibilityIdentifier("handwriting-text")
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
                Toggle(L10n.handwritingKeep, isOn: $keepsInk)
                    .accessibilityIdentifier("handwriting-keep")
            } footer: {
                Text(keepsInk ? L10n.handwritingKeepOn : L10n.handwritingKeepOff)
                    .accessibilityIdentifier("handwriting-keep-note")
            }
        }
    }

    private func read() async {
        guard phase == .reading else { return }
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

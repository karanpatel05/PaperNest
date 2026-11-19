#if os(iOS)
import SwiftUI
import PaperNestCore

/// Which page's speaker note is being written, and what it says now.
struct SpeakerNoteRequest: Identifiable {
    let id = UUID()
    let pageID: PageID
    let pageNumber: Int
    let pageCount: Int
    let text: String
}

/// Writing a page's speaker note: what the presenter sees under the page
/// while presenting, and no one else — never printed, exported or searched.
struct SpeakerNotesSheet: View {
    let request: SpeakerNoteRequest
    let save: (String) -> Void
    @State private var text: String
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    init(request: SpeakerNoteRequest, save: @escaping (String) -> Void) {
        self.request = request
        self.save = save
        _text = State(initialValue: request.text)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.pageLabel(request.pageNumber, of: request.pageCount))
                    .font(.subheadline).foregroundStyle(.secondary)
                TextEditor(text: $text)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text(L10n.speakerNotesPlaceholder).foregroundStyle(.secondary)
                                .padding(.horizontal, 13).padding(.vertical, 16).allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityLabel(L10n.speakerNotes)
                    .accessibilityIdentifier("speaker-notes-editor")
            }
            .padding()
            .navigationTitle(L10n.speakerNotes)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }.accessibilityIdentifier("speaker-notes-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.done) { save(text); dismiss() }.accessibilityIdentifier("speaker-notes-done")
                }
            }
        }
        .onAppear { focused = true }
    }
}
#endif

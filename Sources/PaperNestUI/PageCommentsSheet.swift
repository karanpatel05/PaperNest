import PaperNestCore
import PaperNestStore
import SwiftUI

struct PageCommentsSheet: View {
    let model: DocumentModel
    let pageID: PageID
    let undoManager: UndoManager?
    @Environment(\.dismiss) private var dismiss
    @State private var comments: [PageObject] = []
    @State private var draft: PageCommentDraft?
    @State private var failed = false
    @State private var available = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { draft = PageCommentDraft(model: model, pageID: pageID, original: nil, undoManager: undoManager) } label: {
                        Label(L10n.commentAdd, systemImage: "plus.bubble")
                    }
                    .accessibilityIdentifier("comment-add")
                    .disabled(!available || model.isChangingNotebookPage)
                    if comments.isEmpty {
                        Text(L10n.commentEmpty).foregroundStyle(.secondary)
                            .accessibilityIdentifier("comments-empty")
                    }
                    ForEach(comments) { comment in
                        Button { draft = PageCommentDraft(model: model, pageID: pageID, original: comment, undoManager: undoManager) } label: {
                            HStack {
                                Text(comment.commentText ?? "").lineLimit(3)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("comment-row-\(comment.id.rawValue)")
                        .disabled(!available || model.isChangingNotebookPage)
                    }
                } footer: { Text(L10n.commentPrivacy) }
            }
            .formStyle(.grouped)
            .navigationTitle(L10n.comments)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.done) { dismiss() }.accessibilityIdentifier("comments-done")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        NotebookHistoryActions(undoManager: undoManager, busy: model.isChangingNotebookPage)
                    } label: { Label(L10n.more, systemImage: "ellipsis.circle") }
                    .accessibilityIdentifier("comments-history")
                }
            }
            .task(id: model.session.changeToken) { await reload() }
            .sheet(item: $draft) { draft in
                CommentEditorSheet(draft: draft)
            }
            .alert(L10n.genericErrorTitle, isPresented: $failed) {
                Button(L10n.ok) {}
            } message: { Text(L10n.commentPageUnavailable) }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 360)
        #endif
    }

    private func reload() async {
        do {
            let loaded = try await model.comments(on: pageID)
            guard !Task.isCancelled else { return }
            comments = loaded
            available = true
        } catch {
            guard !Task.isCancelled else { return }
            available = false
            failed = true
        }
    }
}

private struct CommentEditorSheet: View {
    @Bindable var draft: PageCommentDraft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $draft.text)
                        .frame(minHeight: 180)
                        .accessibilityLabel(L10n.commentBody)
                        .accessibilityIdentifier("comment-text")
                } header: { Text(L10n.commentBody) }
                  footer: { Text(L10n.commentLimit) }
                Section {
                    if draft.original != nil {
                        Button(L10n.delete, role: .destructive) { Task { if await draft.save(deleting: true) { dismiss() } } }
                            .accessibilityIdentifier("comment-delete")
                    }
                } footer: { Text(L10n.commentPrivacy) }
            }
            .formStyle(.grouped)
            .disabled(draft.saving)
            .navigationTitle(L10n.commentBody)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }.disabled(draft.saving)
                        .accessibilityIdentifier("comment-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.commentSave) { Task { if await draft.save() { dismiss() } } }
                        .disabled(draft.saving || !draft.valid || draft.cleanText == draft.original?.commentText)
                        .accessibilityIdentifier("comment-save")
                }
            }
            .interactiveDismissDisabled(draft.saving)
            .alert(L10n.genericErrorTitle, isPresented: $draft.failed) {
                if draft.canSaveAsNew {
                    Button(L10n.commentSaveAsNew) { Task { if await draft.save(asNew: true) { dismiss() } } }
                        .accessibilityIdentifier("comment-save-as-new")
                }
                Button(L10n.ok, role: .cancel) {}
            } message: { Text(draft.errorMessage) }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 400)
        #endif
    }
}

import Foundation
import Observation
import PaperNestCore
import PaperNestStore

/// Owned by the comments sheet, so a failed save never replaces the draft.
/// A conflict can explicitly save a second comment without overwriting either.
@MainActor @Observable final class PageCommentDraft: Identifiable {
    let id = UUID()
    let original: PageObject?
    var text: String
    private(set) var saving = false
    private(set) var canSaveAsNew = false
    var failed = false
    private(set) var errorMessage = ""
    private let model: DocumentModel
    private let pageID: PageID
    private let undoManager: UndoManager?

    init(model: DocumentModel, pageID: PageID, original: PageObject?, undoManager: UndoManager?) {
        self.model = model
        self.pageID = pageID
        self.original = original
        self.undoManager = undoManager
        text = original?.commentText ?? ""
    }

    var cleanText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var valid: Bool { !cleanText.isEmpty && cleanText.count <= 10_000 }

    func save(asNew: Bool = false, deleting: Bool = false) async -> Bool {
        guard !saving, deleting || valid, !asNew || canSaveAsNew else { return false }
        saving = true
        defer { saving = false }
        do {
            try await model.setComment(on: pageID, replacing: asNew ? nil : original,
                                       text: deleting ? nil : cleanText, undoManager: undoManager)
            canSaveAsNew = false
            return true
        } catch {
            canSaveAsNew = false
            switch error {
            case StoreError.pageObjectsChanged:
                canSaveAsNew = true
                errorMessage = L10n.commentChanged
            case StoreError.pageNotFound: errorMessage = L10n.commentPageUnavailable
            case StoreError.invalidComment: errorMessage = L10n.commentLimit
            default: errorMessage = L10n.saveFailed
            }
            failed = true
            return false
        }
    }
}

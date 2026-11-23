import SwiftUI
import PaperNestCore
import PaperNestRender
import PaperNestStore

/// Blank and repeated pages in this document, offered for removal, and other
/// documents identical to it. Nothing is deleted until someone chooses pages,
/// reviews them and confirms; pages go as one step that Undo brings back.
@MainActor @Observable
final class CleanupModel {
    enum Phase: Equatable { case looking(Double), ready, failed }

    let document: DocumentModel
    private(set) var phase: Phase = .looking(0)
    private(set) var suggestions: [CleanupSuggestion] = []
    var selected: Set<Int> = []
    private(set) var copies: [PaperNestCore.LibraryItem] = []
    /// The page each suggestion was found on, and its revision then.
    private var foundOn: [(id: PageID, revision: Int)] = []
    /// The document changed after it was looked through, so it was looked through again.
    private(set) var lookedAgain = false
    @ObservationIgnored private var task: Task<Void, Never>?

    init(document: DocumentModel) {
        self.document = document
    }

    private var session: LibrarySession { document.session }

    func look() {
        task?.cancel()
        // Not ready again until this look is done: Review stays off meanwhile.
        phase = .looking(0)
        guard let store = session.environment?.store, let renderer = session.environment?.renderer else { phase = .failed; return }
        let itemID = document.itemID
        let progress: @Sendable (Double) async -> Void = { [weak self] share in await self?.report(share) }
        task = Task { [weak self] in
            do {
                let scan = try await PageCleanupScanner(renderer: renderer, store: store).scan(itemID, progress: progress)
                let found = scan.suggestions
                let copies = try await store.identicalDocuments(to: itemID)
                guard let self, !Task.isCancelled else { return }
                self.foundOn = scan.pages
                self.suggestions = found
                self.selected = Set(found.filter(\.isPreselected).map(\.page))
                self.copies = copies
                self.phase = .ready
            } catch is CancellationError {
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.phase = .failed
            }
        }
    }

    func cancel() { task?.cancel() }

    private func report(_ share: Double) {
        if case .looking = phase { phase = .looking(share) }
    }

    func toggle(_ page: Int) {
        if selected.contains(page) { selected.remove(page) } else { selected.insert(page) }
    }

    /// A document keeps a page: choosing every one is not allowed.
    var choosesEveryPage: Bool { !selected.isEmpty && selected.count >= document.pages.count }

    /// Deletes the chosen pages as one undoable step — only if each is still
    /// the page it was found on, at the revision it was found at, and the
    /// document keeps a page. Otherwise nothing goes, and the document is
    /// looked through again.
    func deleteSelected(undoManager: UndoManager?) async -> Bool {
        guard let store = session.environment?.store, !choosesEveryPage else { return false }
        let chosen = selected.sorted().compactMap { foundOn.indices.contains($0) ? foundOn[$0] : nil }
        guard !chosen.isEmpty, chosen.count == selected.count,
              let current = try? await store.pages(of: document.itemID) else { return false }
        let now = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0.revision) })
        let unchanged = current.count == foundOn.count && chosen.allSatisfy { now[$0.id] == $0.revision }
        guard unchanged, current.count > chosen.count else {
            lookedAgain = true
            look()
            return false
        }
        await document.load()
        return await document.deletePages(chosen.map(\.id), undoManager: undoManager)
    }

    /// Moves an identical document to Recently Deleted, where it stays for 30 days.
    func moveToRecentlyDeleted(_ copy: PaperNestCore.LibraryItem) async {
        guard let store = session.environment?.store else { return }
        do {
            try await store.moveToRecentlyDeleted([copy.id])
            copies.removeAll { $0.id == copy.id }
            session.didChange()
        } catch {
            document.presentedError = .saveFailed()
        }
    }

    func describe(_ suggestion: CleanupSuggestion) -> String {
        let page = suggestion.page + 1
        switch suggestion.reason {
        case .blank: return L10n.cleanupBlank(page)
        case .looksBlank: return L10n.cleanupLooksBlank(page)
        case .duplicate(let of): return L10n.cleanupDuplicate(page, of + 1)
        case .similar(let to): return L10n.cleanupSimilar(page, to + 1)
        }
    }

    /// What deleting the page would take with it.
    func losses(_ suggestion: CleanupSuggestion) -> [String] {
        CleanupAttachment.allCases.filter(suggestion.attachments.contains).map {
            switch $0 {
            case .comment: L10n.cleanupWithComment
            case .bookmark: L10n.cleanupWithBookmark
            case .keptDetails: L10n.cleanupWithKeptDetails
            case .correctedText: L10n.cleanupWithCorrectedText
            }
        }
    }
}

struct CleanupSheet: View {
    @State private var model: CleanupModel
    @State private var isConfirming = false
    @State private var movingCopy: PaperNestCore.LibraryItem?
    let undoManager: UndoManager?
    @Environment(\.dismiss) private var dismiss

    init(document: DocumentModel, undoManager: UndoManager?) {
        _model = State(initialValue: CleanupModel(document: document))
        self.undoManager = undoManager
    }

    var body: some View {
        NavigationStack {
            Form { content }
                .navigationTitle(L10n.cleanupTitle)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.cancel) { model.cancel(); dismiss() }.accessibilityIdentifier("cleanup-cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.cleanupReview) { isConfirming = true }
                            .disabled(model.phase != .ready || model.selected.isEmpty || model.choosesEveryPage)
                            .accessibilityIdentifier("cleanup-review")
                    }
                }
                .task { model.look() }
                .onDisappear { model.cancel() }
                .confirmationDialog(L10n.cleanupConfirmTitle, isPresented: $isConfirming, titleVisibility: .visible) {
                    Button(L10n.cleanupDelete, role: .destructive) {
                        Task { if await model.deleteSelected(undoManager: undoManager) { dismiss() } }
                    }
                    Button(L10n.cancel, role: .cancel) {}
                } message: { Text(confirmation) }
                .confirmationDialog(L10n.cleanupMoveCopyTitle(movingCopy?.name ?? ""),
                                    isPresented: Binding(get: { movingCopy != nil }, set: { if !$0 { movingCopy = nil } }),
                                    titleVisibility: .visible) {
                    Button(L10n.cleanupMoveCopy, role: .destructive) {
                        guard let copy = movingCopy else { return }
                        Task { await model.moveToRecentlyDeleted(copy) }
                    }
                    Button(L10n.cancel, role: .cancel) {}
                } message: { Text(L10n.cleanupCopiesNote) }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }

    /// The pages chosen and what goes with each, then how long Undo lasts.
    private var confirmation: String {
        let chosen = model.suggestions.filter { model.selected.contains($0.page) }
        let lines = chosen.map { suggestion in
            ([model.describe(suggestion)] + model.losses(suggestion)).joined(separator: " ")
        }
        return (lines + [L10n.cleanupConfirmDetail]).joined(separator: "\n")
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .looking(let share):
            ProgressView(L10n.cleanupLooking, value: share).accessibilityIdentifier("cleanup-looking")
        case .failed:
            Text(L10n.cleanupFailed).accessibilityIdentifier("cleanup-failed")
        case .ready:
            suggestions
            if !model.copies.isEmpty { copies }
        }
    }

    private var suggestions: some View {
        Section {
            if model.suggestions.isEmpty {
                Text(L10n.cleanupNone).foregroundStyle(.secondary).accessibilityIdentifier("cleanup-none")
            }
            // Inline rows: "Página 9: parecida a la página 2 (revísala)" is long.
            ForEach(model.suggestions, id: \.page) { suggestion in
                Button { model.toggle(suggestion.page) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: model.selected.contains(suggestion.page) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(model.selected.contains(suggestion.page) ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: model.describe(suggestion)).foregroundStyle(.primary)
                            ForEach(model.losses(suggestion), id: \.self) { loss in
                                Text(verbatim: loss).font(.app(.caption)).foregroundStyle(.orange)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cleanup-page-\(suggestion.page + 1)")
                .accessibilityValue(model.selected.contains(suggestion.page) ? L10n.selectionOn : L10n.selectionOff)
            }
        } header: {
            Text(L10n.cleanupSuggestions)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if !model.suggestions.isEmpty {
                    Text(L10n.cleanupSelected(model.selected.count)).accessibilityIdentifier("cleanup-selected")
                }
                if model.lookedAgain {
                    Text(L10n.cleanupLookedAgain).foregroundStyle(.orange).accessibilityIdentifier("cleanup-looked-again")
                }
                if model.choosesEveryPage {
                    Text(L10n.cleanupAllPages).foregroundStyle(.orange).accessibilityIdentifier("cleanup-all-pages")
                }
                Text(L10n.cleanupOnDevice)
            }
        }
    }

    private var copies: some View {
        Section {
            ForEach(model.copies, id: \.id) { copy in
                HStack {
                    Text(verbatim: copy.name)
                    Spacer()
                    Button(L10n.cleanupMoveCopy) { movingCopy = copy }
                        .font(.app(.footnote))
                        .accessibilityIdentifier("cleanup-move-copy")
                }
            }
        } header: {
            Text(L10n.cleanupCopies)
        } footer: {
            Text(L10n.cleanupCopiesNote)
        }
    }
}

import SwiftUI
import Observation
import PaperNestCore

/// Window-local editing state; the durable library remains the source of truth.
@MainActor @Observable final class DocumentEditorState: Identifiable {
    let id: ItemID
    let model: DocumentModel
    let textSession: InlineTextSession
    let undoManager = UndoManager()
    var zoom: CGFloat = 1
    var signatureDrafts: [PageID: SignatureDraft] = [:]
    var formSession: PDFFormSession?
    var pageToolBusy = false
    var hasUnsavedToolDrafts: Bool {
        signatureDrafts.values.contains { $0.hasUnsavedChanges } || (formSession?.hasUnsavedChanges ?? false)
    }
    var isToolBusy: Bool {
        pageToolBusy || signatureDrafts.values.contains { $0.busy } || (formSession?.saving ?? false)
    }

    init(id: ItemID, session: LibrarySession) {
        self.id = id
        model = DocumentModel(itemID: id, session: session)
        textSession = InlineTextSession(model: model)
    }
}

/// Never drops a tab or changes selection before its pending edit is durable.
@MainActor @Observable final class DocumentTabs {
    private(set) var entries: [DocumentEditorState] = []
    private(set) var selectedID: ItemID?
    private(set) var isChanging = false
    var selected: DocumentEditorState? { entries.first { $0.id == selectedID } }

    @discardableResult
    func open(_ id: ItemID, session: LibrarySession, finish: () async -> Bool) async -> Bool {
        guard !isChanging else { return false }
        isChanging = true
        defer { isChanging = false }
        guard await finish() else { return false }
        if !entries.contains(where: { $0.id == id }) { entries.append(DocumentEditorState(id: id, session: session)) }
        selectedID = id
        return true
    }

    @discardableResult
    func select(_ id: ItemID, finish: () async -> Bool) async -> Bool {
        guard !isChanging, entries.contains(where: { $0.id == id }) else { return false }
        isChanging = true
        defer { isChanging = false }
        guard await finish() else { return false }
        selectedID = id
        return true
    }

    @discardableResult
    func close(_ id: ItemID, discardDrafts: Bool = false, finish: () async -> Bool) async -> Bool {
        guard !isChanging, let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        isChanging = true
        defer { isChanging = false }
        guard await finish() else { return false }
        // Also flush an inactive tab's retained draft before releasing it.
        let entry = entries[index]
        guard !entry.isToolBusy, discardDrafts || !entry.hasUnsavedToolDrafts else { return false }
        guard await entry.textSession.finish(undoManager: entry.undoManager) else { return false }
        entries.remove(at: index)
        if selectedID == id { selectedID = entries.isEmpty ? nil : entries[min(index, entries.count - 1)].id }
        return true
    }
}

struct DocumentWorkspace: View {
    let initialID: ItemID
    let session: LibrarySession
    @Bindable var tabs: DocumentTabs
    @State private var closingDraft: ItemID?
    @Environment(DocumentEditingGuard.self) private var editingGuard
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var widthClass
    #endif

    private var compact: Bool {
        #if os(iOS)
        widthClass == .compact || typeSize.isAccessibilitySize
        #else
        typeSize.isAccessibilitySize
        #endif
    }

    var body: some View {
        Group {
            if let entry = tabs.selected {
                DocumentView(itemID: entry.id, session: session, retainedState: entry,
                             workspaceHeader: AnyView(tabStrip))
                    .id(entry.id)
            } else {
                ProgressView(L10n.loadingLibrary)
            }
        }
        .task(id: initialID) {
            _ = await tabs.open(initialID, session: session, finish: finishEditing)
        }
        .confirmationDialog(L10n.closeDraftTitle, isPresented: Binding(get: { closingDraft != nil }, set: { if !$0 { closingDraft = nil } })) {
            Button(L10n.inlineDiscardDraft, role: .destructive) {
                if let id = closingDraft { close(id, discardDrafts: true) }
                closingDraft = nil
            }
            Button(L10n.keepDocumentOpen, role: .cancel) { closingDraft = nil }
        } message: { Text(L10n.closeDraftMessage) }
    }

    private func finishEditing() async -> Bool { await editingGuard.finish?() ?? true }
    private func choose(_ id: ItemID) { Task { _ = await tabs.select(id, finish: finishEditing) } }
    private func close(_ id: ItemID, discardDrafts: Bool = false) {
        if !discardDrafts, tabs.entries.first(where: { $0.id == id })?.hasUnsavedToolDrafts == true {
            closingDraft = id
            return
        }
        Task {
            if await tabs.close(id, discardDrafts: discardDrafts, finish: finishEditing), tabs.entries.isEmpty { dismiss() }
        }
    }
    private func openAnother() {
        Task { if await finishEditing() { dismiss() } }
    }

    private var tabStrip: some View {
        HStack(spacing: 6) {
            if compact {
                Menu {
                    ForEach(tabs.entries) { entry in
                        Button { choose(entry.id) } label: {
                            Label(entry.model.item?.name ?? L10n.loadingLibrary,
                                  systemImage: entry.id == tabs.selectedID ? "checkmark" : "doc")
                        }
                    }
                    if let id = tabs.selectedID { Button(L10n.closeDocumentTab, systemImage: "xmark") { close(id) } }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.on.square").font(.system(size: 20))
                        Text(verbatim: String(tabs.entries.count)).font(.subheadline.monospacedDigit())
                    }
                    .padding(.horizontal, 8).frame(minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(L10n.openDocumentTabs(tabs.entries.count))
                .accessibilityIdentifier("document-tabs-menu")
                Spacer(minLength: 0)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tabs.entries) { entry in
                            HStack(spacing: 0) {
                                Button { choose(entry.id) } label: {
                                    Label(entry.model.item?.name ?? L10n.loadingLibrary,
                                          systemImage: entry.model.item?.kind == .notebook ? "book.closed" : "doc.text")
                                        .font(.subheadline).lineLimit(1).frame(maxWidth: 210)
                                        .padding(.horizontal, 12).frame(minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityIdentifier("document-tab-\(entry.id.rawValue)")
                                .accessibilityValue(entry.id == tabs.selectedID ? L10n.selectionOn : L10n.selectionOff)
                                .accessibilityAddTraits(entry.id == tabs.selectedID ? .isSelected : [])
                                Button { close(entry.id) } label: {
                                    Image(systemName: "xmark").font(.caption).frame(width: 44, height: 44).contentShape(Rectangle())
                                }.accessibilityLabel(L10n.closeDocumentTab)
                                    .accessibilityIdentifier("document-tab-close-\(entry.id.rawValue)")
                            }
                            .background(entry.id == tabs.selectedID ? Theme.selection : Theme.surface,
                                        in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .frame(height: 44)
            }
            Button(action: openAnother) {
                Image(systemName: "plus").font(.system(size: 20)).frame(width: 44, height: 44).contentShape(Rectangle())
            }.accessibilityLabel(L10n.openAnotherDocument)
                .accessibilityIdentifier("document-tab-add")
        }
        .buttonStyle(.plain).foregroundStyle(Theme.primaryText)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Theme.sidebar)
        .disabled(tabs.isChanging)
    }
}

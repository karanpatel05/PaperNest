import PaperNestCore
import PaperNestStore
import SwiftUI

/// Shared page workspace. Mutations use the editor's existing durable model
/// and history; extraction creates a separate document without changing pages.
struct DocumentPagesSheet: View {
    @Bindable var model: DocumentModel
    let undoManager: UndoManager?
    var isEmbedded = false
    var onClose: (() -> Void)? = nil
    var beforeAction: (() async -> Bool)? = nil
    var onBusyChange: ((Bool) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var failed = false
    @State private var proFeature: ProFeature?
    @State private var extractRequest: DocumentToolsRequest?
    @State private var extractedName: String?
    @State private var extractedID: ItemID?

    var body: some View {
        EditorToolNavigation(isEmbedded: isEmbedded, title: L10n.pages) {
            VStack(spacing: 0) {
                List {
                    ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
                        HStack(spacing: 12) {
                            Button { selectPage(page.id) } label: {
                                HStack(spacing: 12) {
                                    PageImageView(page: page, pixelSize: 160,
                                                  accessibilityLabel: L10n.pageLabel(index + 1, of: model.pages.count))
                                        .frame(width: 56, height: 76)
                                        .accessibilityHidden(true)
                                    Text(L10n.pageLabel(index + 1, of: model.pages.count))
                                        .font(.body).multilineTextAlignment(.leading)
                                    Spacer(minLength: 4)
                                    if model.selectedPageID == page.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                                    }
                                }.frame(maxWidth: .infinity, minHeight: 80).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.pageLabel(index + 1, of: model.pages.count))
                            .accessibilityValue(model.selectedPageID == page.id ? L10n.selectionOn : L10n.selectionOff)
                            .accessibilityIdentifier("pages-select-\(index + 1)")
                            Menu {
                                Button(L10n.movePageUp) { perform(page.id) { await model.moveSelected(by: -1, undoManager: undoManager) } }
                                    .disabled(index == 0).accessibilityIdentifier("pages-move-up")
                                Button(L10n.movePageDown) { perform(page.id) { await model.moveSelected(by: 1, undoManager: undoManager) } }
                                    .disabled(index + 1 == model.pages.count).accessibilityIdentifier("pages-move-down")
                                Button(L10n.rotateLeft) { perform(page.id) { await model.rotate(clockwise: false, undoManager: undoManager) } }
                                Button(L10n.rotateRight) { perform(page.id) { await model.rotate(clockwise: true, undoManager: undoManager) } }
                                Button(L10n.duplicate) { perform(page.id) { try await model.duplicateSelectedPage(undoManager: undoManager) } }
                                Button(L10n.deletePage, role: .destructive) { perform(page.id) { await model.deleteSelectedPage(undoManager: undoManager) } }
                            } label: {
                                Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            #if os(macOS)
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            #endif
                            .accessibilityLabel(L10n.more)
                            .accessibilityIdentifier("pages-more-\(index + 1)")
                        }
                        .accessibilityElement(children: .contain)
                    }
                    .onMove { offsets, destination in
                        perform { await model.movePages(from: offsets, to: destination, undoManager: undoManager) }
                    }
                }
                .listStyle(.plain)
                .accessibilityIdentifier("pages-list")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        action(L10n.duplicate, icon: "doc.on.doc", id: "pages-duplicate") {
                            perform { try await model.duplicateSelectedPage(undoManager: undoManager) }
                        }
                        action(L10n.rotateLeft, icon: "rotate.left", id: "pages-rotate-left") {
                            perform { await model.rotate(clockwise: false, undoManager: undoManager) }
                        }
                        action(L10n.rotateRight, icon: "rotate.right", id: "pages-rotate-right") {
                            perform { await model.rotate(clockwise: true, undoManager: undoManager) }
                        }
                        action(L10n.extractPages, icon: "doc.on.doc", id: "pages-extract") { openExtraction() }
                        action(L10n.deletePage, icon: "trash", id: "pages-delete") {
                            perform { await model.deleteSelectedPage(undoManager: undoManager) }
                        }
                    }.padding(12)
                }
                .disabled(model.selectedPage == nil)
                .accessibilityIdentifier("pages-actions")
                .background(Theme.surface)
            }
            .disabled(busy || model.isChangingNotebookPage)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .safeAreaInset(edge: .top, spacing: 0) {
                if isEmbedded {
                    VStack(spacing: 8) {
                        HStack {
                            Text(L10n.pages).font(.headline)
                            Spacer()
                            doneButton
                        }
                        historyActions
                    }.padding(12).background(Theme.surface)
                }
            }
            .toolbar {
                if !isEmbedded {
                    ToolbarItem(placement: .cancellationAction) { doneButton }
                    ToolbarItemGroup(placement: .primaryAction) { historyActions }
                }
            }
            .overlay { if busy { ProgressView().padding().background(Theme.surface, in: RoundedRectangle(cornerRadius: 12)) } }
            .alert(L10n.saveFailed, isPresented: $failed) { Button(L10n.ok, role: .cancel) {} }
            .alert(L10n.extractPages, isPresented: Binding(get: { extractedName != nil }, set: { if !$0 { extractedName = nil } })) {
                Button(L10n.ok, role: .cancel) { extractedName = nil }
            } message: { Text(extractedName ?? "") }
        }
        #if os(macOS)
        .frame(minWidth: isEmbedded ? nil : 440, idealWidth: isEmbedded ? nil : 580,
               minHeight: isEmbedded ? nil : 400, idealHeight: isEmbedded ? nil : 620)
        #endif
        .interactiveDismissDisabled(busy)
        .proPaywall($proFeature)
        .sheet(item: $extractRequest, onDismiss: {
            guard let id = extractedID else { return }
            extractedID = nil
            Task { extractedName = try? await model.session.environment?.store.item(id)?.name }
        }) { request in
            DocumentToolsSheet(request: request) { id in extractedID = id }
        }
    }

    private var doneButton: some View {
        Button(L10n.done) { close() }.disabled(busy).accessibilityIdentifier("pages-done")
    }

    private var historyActions: some View {
        HStack {
            NotebookHistoryActions(undoManager: undoManager, busy: busy || model.isChangingNotebookPage,
                                   historyRevision: model.historyRevision, beforeAction: beforeAction)
            #if os(iOS)
            EditButton().accessibilityIdentifier("pages-reorder")
            #endif
        }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private func action(_ title: String, icon: String, id: String, run: @escaping () -> Void) -> some View {
        Button(action: run) { Label(title, systemImage: icon).fixedSize(horizontal: true, vertical: false).frame(minHeight: 44) }
            .buttonStyle(.bordered).accessibilityIdentifier(id)
    }

    private func selectPage(_ id: PageID) {
        guard !busy else { return }
        busy = true
        onBusyChange?(true)
        Task {
            defer { busy = false; onBusyChange?(false) }
            guard await beforeAction?() ?? true else { return }
            model.selectedPageID = id
        }
    }

    private func perform(_ pageID: PageID? = nil, action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        onBusyChange?(true)
        Task {
            defer { busy = false; onBusyChange?(false) }
            guard await beforeAction?() ?? true else { return }
            if let pageID { model.selectedPageID = pageID }
            do {
                try await action()
                if model.presentedError != nil { failed = true; model.presentedError = nil }
            } catch let error as ProAccessError { proFeature = error.feature }
            catch { failed = true }
        }
    }

    private func openExtraction() {
        guard SubscriptionStore.shared.allows(.pageTools) else { proFeature = .pageTools; return }
        perform {
            guard let store = model.session.environment?.store,
                  let source = try await store.items(in: .all).first(where: { $0.id == model.itemID }) else {
                throw StoreError.itemNotFound
            }
            extractRequest = DocumentToolsRequest(operation: .extract(source))
        }
    }
}

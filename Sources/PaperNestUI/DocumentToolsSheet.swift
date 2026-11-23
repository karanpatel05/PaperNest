import PaperNestCore
import PaperNestStore
import SwiftUI

/// Captures the selection and its order when the sheet opens. Library
/// refreshes and sorting cannot silently rearrange a merge in progress.
struct DocumentToolsRequest: Identifiable {
    enum Operation {
        case merge([LibraryStore.ItemSummary], FolderID?)
        case extract(LibraryStore.ItemSummary)
    }
    let id = UUID()
    let operation: Operation
}

struct DocumentToolsSheet: View {
    let request: DocumentToolsRequest
    let created: (ItemID) -> Void
    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var orderedItems: [LibraryStore.ItemSummary]
    @State private var pages: [Page] = []
    @State private var selectedPages: Set<PageID> = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var failed = false
    @State private var proFeature: ProFeature?

    init(request: DocumentToolsRequest, created: @escaping (ItemID) -> Void) {
        self.request = request
        self.created = created
        switch request.operation {
        case .merge(let items, _):
            _name = State(initialValue: L10n.mergedDocumentName)
            _orderedItems = State(initialValue: items)
        case .extract(let source):
            _name = State(initialValue: L10n.extractedDocumentName(source.item.name))
            _orderedItems = State(initialValue: [])
        }
    }

    private var isMerge: Bool {
        if case .merge = request.operation { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.documentName, text: $name)
                        .accessibilityIdentifier("document-tools-name")
                } footer: {
                    Text(L10n.toolsPreserveOriginals)
                }
                if isMerge {
                    Section(L10n.mergeOrder) {
                        ForEach(Array(orderedItems.enumerated()), id: \.element.id) { index, summary in
                            HStack(spacing: 12) {
                                Text(verbatim: "\(index + 1)")
                                    .font(.app(.caption).weight(.semibold)).monospacedDigit()
                                    .foregroundStyle(EditorChrome.purple)
                                    .frame(width: 30, height: 30)
                                    .background(EditorChrome.lavender, in: RoundedRectangle(cornerRadius: 9))
                                VStack(alignment: .leading) {
                                    // Identified by position: a UI test matching the name
                                    // alone would find the library tile behind the sheet,
                                    // which stays visible in an iPad form sheet.
                                    Text(summary.item.name)
                                        .accessibilityIdentifier("merge-row-\(index)")
                                    Text(L10n.pageCount(summary.pageCount)).font(.app(.caption)).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Button { orderedItems.swapAt(index, index - 1) } label: {
                                    Image(systemName: "arrow.up")
                                }
                                .accessibilityLabel(L10n.moveDocumentUp(summary.item.name))
                                .accessibilityIdentifier("merge-up-\(index)")
                                .disabled(index == 0)
                                Button { orderedItems.swapAt(index, index + 1) } label: {
                                    Image(systemName: "arrow.down")
                                }
                                .accessibilityLabel(L10n.moveDocumentDown(summary.item.name))
                                .accessibilityIdentifier("merge-down-\(index)")
                                .disabled(index == orderedItems.count - 1)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } else {
                    Section {
                        if isLoading { ProgressView() }
                        if !pages.isEmpty {
                            Button(selectedPages.count == pages.count ? L10n.deselectAll : L10n.selectAll) {
                                selectedPages = selectedPages.count == pages.count ? [] : Set(pages.map(\.id))
                            }
                            ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                                Button {
                                    if !selectedPages.insert(page.id).inserted { selectedPages.remove(page.id) }
                                } label: {
                                    HStack(spacing: 14) {
                                        PageImageView(page: page, pixelSize: 180).frame(width: 44, height: 58)
                                            .accessibilityHidden(true)
                                        Text(L10n.pageLabel(index + 1, of: pages.count)).foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName: selectedPages.contains(page.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(EditorChrome.purple)
                                    }
                                    .padding(10)
                                    .background(selectedPages.contains(page.id) ? EditorChrome.lavender : EditorChrome.surface,
                                                in: RoundedRectangle(cornerRadius: 12))
                                    .contentShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("extract-page-\(index + 1)")
                                .accessibilityValue(selectedPages.contains(page.id) ? L10n.selectionOn : L10n.selectionOff)
                            }
                        }
                    } header: {
                        Text(L10n.pages)
                    } footer: {
                        Text(L10n.extractChoosePages)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(EditorChrome.secondaryBackground)
            .disabled(isSaving)
            .navigationTitle(isMerge ? L10n.mergeTitle : L10n.extractTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await create() } } label: {
                        if isSaving { ProgressView() } else { Text(L10n.createDocument) }
                    }
                    .accessibilityLabel(L10n.createDocument)
                    .accessibilityIdentifier("document-tools-create")
                    .disabled(isLoading || isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!isMerge && selectedPages.isEmpty))
                }
            }
            .task {
                defer { isLoading = false }
                if case .extract(let source) = request.operation, let store = session.environment?.store {
                    do { pages = try await store.pages(of: source.id) }
                    catch { failed = true }
                }
            }
            .alert(L10n.genericErrorTitle, isPresented: $failed) {
                Button(L10n.ok) {}
            } message: {
                Text(L10n.saveFailed)
            }
            .interactiveDismissDisabled(isSaving)
        }
        .toolPanelAppearance()
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 420, idealHeight: 560)
        #endif
        .proPaywall($proFeature)
    }

    private func create() async {
        guard SubscriptionStore.shared.allows(.pageTools) else { proFeature = .pageTools; return }
        guard !isSaving, let store = session.environment?.store else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let item: PaperNestCore.LibraryItem
            switch request.operation {
            case .merge(_, let folder):
                item = try await store.mergeItems(orderedItems.map(\.id), named: name, folderID: folder)
            case .extract(let source):
                item = try await store.extractPages(pages.filter { selectedPages.contains($0.id) }.map(\.id), from: source.id, named: name)
            }
            session.didChange()
            created(item.id)
            dismiss()
        } catch { failed = true }
    }
}

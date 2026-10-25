import PaperNestCore
import PaperNestStore
import PhotosUI
import SwiftUI

/// One home for the document tools, instead of hunting through a ⋯ menu.
///
/// A tile appears here only when the tool behind it works today. Tools that
/// belong to a milestone that hasn't landed are simply absent — no disabled
/// placeholders, per `docs/FEATURE_EXPANSION.md`.
struct ToolsSheet: View {
    @Bindable var model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var creatingNotebook = false
    @State private var picking: ToolPick?
    @State private var composing: DocumentToolsRequest?
    @State private var archiving: BulkExportRequest?
    @State private var createdItemID: ItemID?
    @State private var photoSelection: [PhotosPickerItem] = []

    /// The tools that can start from the library, with the selection each needs.
    enum Tool: String, CaseIterable, Identifiable, Hashable {
        case merge, extract, split, archive

        var id: String { rawValue }

        var title: String {
            switch self {
            case .merge: L10n.mergeDocuments
            case .extract: L10n.extractPages
            case .split: L10n.splitPages
            case .archive: L10n.exportAsZip
            }
        }

        var systemImage: String {
            switch self {
            case .merge: "arrow.triangle.merge"
            case .extract: "doc.on.doc"
            case .split: "square.split.2x1"
            case .archive: "doc.zipper"
            }
        }

        var prompt: String {
            switch self {
            case .merge: L10n.pickForMerge
            case .extract: L10n.pickForExtract
            case .split: L10n.pickForSplit
            case .archive: L10n.pickForArchive
            }
        }

        var allowsMany: Bool { self == .merge || self == .archive }
        var minimum: Int { self == .merge ? 2 : 1 }

        /// Splitting one page would just copy the document. Only the
        /// archive takes file items: the rest are page operations.
        func accepts(_ summary: LibraryStore.ItemSummary) -> Bool {
            switch self {
            case .split: summary.pageCount > 1
            case .archive: summary.pageCount > 0 || summary.file != nil
            default: summary.pageCount > 0
            }
        }
    }

    struct ToolPick: Identifiable, Hashable {
        let tool: Tool
        var id: Tool { tool }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.toolsCreate) {
                    tiles(createTiles)
                    // A picker brings its own presentation, so it sits beside
                    // the tiles rather than inside the grid.
                    PhotosPicker(selection: $photoSelection, maxSelectionCount: 20, matching: .images) {
                        Label(L10n.importPhotos, systemImage: "photo.on.rectangle")
                    }
                    .accessibilityIdentifier("tool-photos")
                }
                Section(L10n.toolsDocuments) {
                    tiles(Tool.allCases.map { tool in
                        ChoiceTile(title: tool.title, systemImage: tool.systemImage, iconColor: Theme.accent,
                                   isSelected: false, identifier: "tool-\(tool.rawValue)") {
                            picking = ToolPick(tool: tool)
                        }
                    })
                }
            }
            .formStyle(.grouped)
            .navigationTitle(L10n.toolsTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.done) { dismiss() }.accessibilityIdentifier("tools-done")
                }
            }
            #else
            // A Mac sheet retains its root confirmation toolbar while pushing
            // a destination. Keep each screen's action in its own content so
            // the picker can replace Done with Continue.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Spacer()
                    Button(L10n.done) { dismiss() }
                        .accessibilityIdentifier("tools-done")
                        .keyboardShortcut(.defaultAction)
                }
                .padding()
                .background(.bar)
            }
            #endif
            .onChange(of: photoSelection) { _, picked in
                guard !picked.isEmpty else { return }
                photoSelection = []
                dismiss()
                Task { await importPhotos(picked) }
            }
            .navigationDestination(item: $picking) { pick in
                DocumentPicker(tool: pick.tool) { chosen in
                    picking = nil
                    run(pick.tool, on: chosen)
                }
            }
        }
        .sheet(item: $composing, onDismiss: openCreatedItem) { request in
            DocumentToolsSheet(request: request) { createdItemID = $0 }
        }
        .sheet(isPresented: $creatingNotebook, onDismiss: openCreatedItem) {
            NotebookCreationSheet(model: model) { createdItemID = $0 }
        }
        .sheet(item: $archiving) { request in
            BulkExportSheet(request: request)
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 420, idealHeight: 540)
        #endif
    }

    private var createTiles: [ChoiceTile] {
        var tiles: [ChoiceTile] = []
        #if os(iOS)
        tiles.append(ChoiceTile(title: L10n.scan, systemImage: "doc.viewfinder", iconColor: Theme.accent, isSelected: false,
                                isEnabled: DocumentCameraView.isSupported, identifier: "tool-scan") {
            dismiss()
            model.isShowingScanner = true
        })
        #endif
        tiles.append(ChoiceTile(title: L10n.importFiles, systemImage: "square.and.arrow.down", iconColor: Theme.accent,
                                isSelected: false, identifier: "tool-import") {
            dismiss()
            model.isShowingFileImporter = true
        })
        tiles.append(ChoiceTile(title: L10n.newNotebook, systemImage: "book.closed", iconColor: Theme.accent,
                                isSelected: false, identifier: "tool-notebook") {
            creatingNotebook = true
        })
        return tiles
    }

    /// Two per row, so a long translated title wraps instead of truncating.
    private func tiles(_ tiles: [ChoiceTile]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in tile }
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
    }

    /// Photos are loaded one at a time: the picker hands back whole images,
    /// and a selection of twenty should not sit in memory at once.
    private func importPhotos(_ picked: [PhotosPickerItem]) async {
        var loaded: [(data: Data, name: String)] = []
        for (index, item) in picked.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let suggested = item.itemIdentifier.map { String($0.prefix(8)) } ?? "\(index + 1)"
            loaded.append((data, "Photo \(suggested)"))
        }
        await model.importPhotos(loaded)
    }

    private func run(_ tool: Tool, on chosen: [LibraryStore.ItemSummary]) {
        guard !chosen.isEmpty else { return }
        switch tool {
        case .merge:
            composing = DocumentToolsRequest(operation: .merge(chosen, model.currentFolderID))
        case .extract:
            composing = DocumentToolsRequest(operation: .extract(chosen[0]))
        case .split:
            let summary = chosen[0]
            dismiss()
            Task { _ = await model.split(summary) }
        case .archive:
            archiving = BulkExportRequest(ids: chosen.map(\.id))
        }
    }

    private func openCreatedItem() {
        guard let id = createdItemID else { return }
        createdItemID = nil
        dismiss()
        model.open(id)
    }
}

/// Picks the documents a tool runs on. Rows that the tool cannot use are
/// shown but not selectable, so an unusable document is explained rather
/// than silently missing.
private struct DocumentPicker: View {
    let tool: ToolsSheet.Tool
    let chosen: ([LibraryStore.ItemSummary]) -> Void
    @Environment(LibrarySession.self) private var session
    @State private var items: [LibraryStore.ItemSummary] = []
    @State private var selection: [ItemID] = []
    @State private var isLoading = true

    var body: some View {
        Form {
            Section {
                if isLoading {
                    ProgressView()
                } else if items.isEmpty {
                    Text(L10n.toolsNoDocuments).foregroundStyle(.secondary)
                }
                ForEach(items) { summary in
                    let usable = tool.accepts(summary)
                    Button { toggle(summary) } label: {
                        HStack(spacing: 14) {
                            Text(summary.item.name)
                                .foregroundStyle(usable ? .primary : .secondary)
                            Spacer()
                            Text(L10n.pageCount(summary.pageCount))
                                .font(.caption).foregroundStyle(.secondary)
                            Image(systemName: selection.contains(summary.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selection.contains(summary.id) ? Theme.accent : .secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!usable)
                    .accessibilityIdentifier("pick-\(summary.item.name)")
                    .accessibilityValue(selection.contains(summary.id) ? L10n.selectionOn : L10n.selectionOff)
                }
            } footer: {
                Text(tool.prompt)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(tool.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                continueButton
            }
        }
        #else
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Spacer()
                continueButton.keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(.bar)
        }
        #endif
        .task {
            defer { isLoading = false }
            items = (try? await session.environment?.store.items(in: .all)) ?? []
        }
    }

    private var continueButton: some View {
        Button(L10n.toolsContinue) { chosen(items.filter { selection.contains($0.id) }.sorted(by: pickOrder)) }
            .accessibilityIdentifier("pick-continue")
            .disabled(selection.count < tool.minimum)
    }

    private func toggle(_ summary: LibraryStore.ItemSummary) {
        if let index = selection.firstIndex(of: summary.id) {
            selection.remove(at: index)
        } else if tool.allowsMany {
            selection.append(summary.id)
        } else {
            selection = [summary.id]
        }
    }

    /// Hands the tool the documents in the order they were picked, which is
    /// the order a merge starts from.
    private func pickOrder(_ a: LibraryStore.ItemSummary, _ b: LibraryStore.ItemSummary) -> Bool {
        (selection.firstIndex(of: a.id) ?? 0) < (selection.firstIndex(of: b.id) ?? 0)
    }
}

import Foundation
import Observation
import PaperNestCore
import PaperNestExport
import PaperNestStore
import SwiftUI

/// A transient form draft. The completed PDF becomes a new immutable library asset.
@MainActor @Observable final class PDFFormSession {
    let itemID: ItemID
    let library: LibrarySession
    private(set) var fields: [FormField] = []
    var values: [String: FormValue] = [:]
    private(set) var editableNames = Set<String>()
    var name = ""
    var failed = false
    var savedName: String?
    private var initialName = ""
    private var initialValues: [String: FormValue] = [:]
    var hasUnsavedChanges: Bool { loaded && savedName == nil && (name != initialName || values != initialValues) }
    private(set) var pageCount = 0
    private(set) var loaded = false
    private(set) var loading = false
    private(set) var loadFailed = false
    private(set) var saving = false
    private var data: Data?
    private var folderID: FolderID?

    init(itemID: ItemID, library: LibrarySession) {
        self.itemID = itemID; self.library = library
    }

    func load() async {
        guard !loaded, !loading, let env = library.environment else { return }
        loading = true
        defer { loading = false }
        loadFailed = false
        do {
            guard let item = try await env.store.item(itemID), !item.isDeleted else { throw StoreError.itemNotFound }
            let pages = try await env.store.pages(of: itemID)
            let output = try await env.exporter.export(itemName: item.name, pages: pages, options: ExportOptions(includesRecognizedText: false))
            defer { output.removeTemporaryFiles() }
            guard let url = output.files.first else { throw FormError.writeFailed }
            let bytes = try Data(contentsOf: url)
            let discovered = try await PDFFormWorker.run { try PDFForm.fields(in: bytes) }
            // Repeated widgets share one value. Present their field once, on its first page.
            var names = Set<String>()
            fields = discovered.filter { names.insert($0.name).inserted }
            editableNames = Set(Dictionary(grouping: discovered, by: \.name).compactMap { name, widgets in
                widgets.allSatisfy(\.isFillable) && Set(widgets.map(\.isCheckbox)).count == 1 ? name : nil
            })
            values = Dictionary(uniqueKeysWithValues: fields.filter { editableNames.contains($0.name) }.map {
                ($0.name, $0.isCheckbox ? FormValue.checked($0.value == "on") : .text($0.value))
            })
            data = bytes; folderID = item.folderID; pageCount = pages.count
            name = L10n.formCopyName(item.name)
            initialName = name
            initialValues = values
            loaded = true
        } catch { loadFailed = true }
    }

    func saveCopy() async throws -> PaperNestCore.LibraryItem {
        try SubscriptionStore.shared.require(.forms)
        guard !saving, let data, let env = library.environment,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FormError.writeFailed }
        saving = true
        defer { saving = false }
        let values = values
        let bytes = try await PDFFormWorker.run { try PDFForm.filled(data, with: values) }
        let prepared = try await env.importer.prepareInBackground(.data(bytes, name: name + ".pdf"))
        let copy = try await env.store.createItem(kind: .document, name: name, folderID: folderID,
                                                   pages: prepared.pages, assets: prepared.assets)
        library.didChange()
        return copy
    }
}

/// PDFKit font resolution must run on a dedicated queue, not block Swift's cooperative pool.
private enum PDFFormWorker {
    static func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(with: Result(catching: work)) }
        }
    }
}

struct PDFFormSheet: View {
    let isEmbedded: Bool
    let onClose: (() -> Void)?
    let beforeAction: (() async -> Bool)?
    @State private var draft: PDFFormSession
    let useTextBox: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var proFeature: ProFeature?
    @FocusState private var focusedField: String?

    init(model: DocumentModel, isEmbedded: Bool = false, onClose: (() -> Void)? = nil,
         beforeAction: (() async -> Bool)? = nil, retainedSession: PDFFormSession? = nil,
         useTextBox: @escaping () -> Void) {
        self.beforeAction = beforeAction
        self.isEmbedded = isEmbedded
        self.onClose = onClose
        _draft = State(initialValue: retainedSession ?? PDFFormSession(itemID: model.itemID, library: model.session))
        self.useTextBox = useTextBox
    }

    var body: some View {
        EditorToolNavigation(isEmbedded: isEmbedded, title: L10n.formTitle) {
            Group {
                if draft.loadFailed {
                    ContentUnavailableView {
                        Label(L10n.formLoadFailed, systemImage: "exclamationmark.triangle")
                    } actions: { Button(L10n.inlineRetry) { Task { await draft.load() } } }
                } else if !draft.loaded {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if draft.fields.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.formNoFields, systemImage: "doc.text")
                    } description: { Text(L10n.formNoFieldsHelp) }
                    actions: {
                        Button(L10n.textBox) { close(); useTextBox() }.accessibilityIdentifier("form-use-text")
                    }
                } else {
                    // Keep the native field hierarchy alive after saving. Replacing
                    // a focused Mac Form with a success view causes an AX focus cycle.
                    Form {
                        if let savedName = draft.savedName {
                            Section {
                                Label(L10n.formSaved, systemImage: "checkmark.circle")
                                Text(savedName)
                            }.accessibilityIdentifier("form-saved")
                        }
                        Section {
                            TextField(L10n.documentName, text: $draft.name)
                                .focused($focusedField, equals: "copy-name")
                                .accessibilityIdentifier("form-copy-name")
                                .disabled(draft.savedName != nil)
                        } footer: { Text(L10n.formCopyHelp) }
                        ForEach(Array(Set(draft.fields.map(\.pageIndex))).sorted(), id: \.self) { page in
                            Section(L10n.pageLabel(page + 1, of: draft.pageCount)) {
                                ForEach(draft.fields.filter { $0.pageIndex == page }, id: \.name) { field in
                                    fieldRow(field).disabled(draft.savedName != nil)
                                }
                            }
                        }
                        Section { Text(L10n.formExportHelp).font(.callout).foregroundStyle(.secondary) }
                        if draft.failed { Section { Label(L10n.saveFailed, systemImage: "exclamationmark.triangle") } }
                    }
                    .formStyle(.grouped)
                    .scrollContentBackground(.hidden)
                    .background(EditorChrome.secondaryBackground)
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #else
            .frame(minWidth: isEmbedded ? nil : 460, minHeight: isEmbedded ? nil : 480)
            #endif
            .safeAreaInset(edge: .top, spacing: 0) {
                if isEmbedded {
                    VStack(spacing: 8) {
                        HStack {
                            Text(L10n.formTitle).font(.headline)
                            Spacer()
                            closeButton
                        }
                        saveButton
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(16)
                    .background(EditorChrome.surface)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 0.5) }
                }
            }
            .toolbar {
                if !isEmbedded {
                    ToolbarItem(placement: .cancellationAction) { closeButton }
                    ToolbarItem(placement: .confirmationAction) { saveButton }
                }
            }
            .disabled(draft.saving)
            .interactiveDismissDisabled(draft.saving)
        }
        .toolPanelAppearance(isEmbedded: isEmbedded)
        .task { await draft.load() }
        .proPaywall($proFeature)
    }

    private var closeButton: some View {
        Button(draft.savedName == nil ? L10n.cancel : L10n.done) { close() }
            .disabled(draft.saving).accessibilityIdentifier("form-close")
    }

    @ViewBuilder private var saveButton: some View {
        if !draft.editableNames.isEmpty {
            Button(L10n.formSaveCopy) {
                focusedField = nil
                Task { await save() }
            }
            .disabled(draft.savedName != nil || draft.saving || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("form-save-copy")
        }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    @ViewBuilder private func fieldRow(_ field: FormField) -> some View {
        if !draft.editableNames.contains(field.name) {
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: field.name).font(.headline)
                Text(verbatim: field.value)
                Text(L10n.formUnsupported).font(.caption).foregroundStyle(.secondary)
            }.accessibilityIdentifier("form-unsupported-\(field.name)")
        } else if field.isCheckbox {
            Toggle(field.name, isOn: Binding(get: {
                if case .checked(let value) = draft.values[field.name] { return value }; return false
            }, set: { draft.values[field.name] = .checked($0) }))
            .accessibilityIdentifier("form-field-\(field.name)")
        } else {
            VStack(alignment: .leading) {
                Text(verbatim: field.name).font(.headline)
                TextField(field.name, text: Binding(get: {
                    if case .text(let value) = draft.values[field.name] { return value }; return ""
                }, set: { draft.values[field.name] = .text($0) }), axis: .vertical)
                .focused($focusedField, equals: "field-" + field.name)
                .lineLimit(1...5).accessibilityIdentifier("form-field-\(field.name)")
            }
        }
    }

    private func save() async {
        guard await beforeAction?() ?? true else { return }
        guard SubscriptionStore.shared.allows(.forms) else { proFeature = .forms; return }
        do { draft.savedName = try await draft.saveCopy().name; draft.failed = false }
        catch { draft.failed = true }
    }
}

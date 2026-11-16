import PaperNestCore
import PaperNestExport
import SwiftUI

/// Makes a smaller copy of the document, measured, to save or share.
///
/// An export, not an edit: the library and the originals are untouched, so
/// there is nothing to undo and nothing that could be lost. The sizes shown
/// are the real files', before and after.
///
/// What it can and cannot shrink is the exporter's rule, stated here so the
/// sheet can say it plainly: only pages with no text of their own are
/// re-encoded, because rasterising a page with text would destroy the text.
/// A document that cannot get smaller gets its original back and says so.
struct CompressSheet: View {
    let itemID: ItemID
    var isEmbedded = false
    var onClose: (() -> Void)? = nil
    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var preset: CompressionPreset = .strong
    @State private var loaded: (name: String, pages: [Page], bytes: Int64)?
    @State private var phase: Phase = .choosing
    @State private var task: Task<Void, Never>?
    @State private var isSaving = false
    @State private var shareRequest: ShareRequest?

    enum Phase {
        case choosing
        case working(Double)
        case done(CompressionResult)
        case failed
    }

    private var result: CompressionResult? {
        if case .done(let result) = phase { result } else { nil }
    }

    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    var body: some View {
        Group {
            if isEmbedded {
                ScrollView { content }
            } else {
                #if os(macOS)
                // Keep a bounded Mac sheet: self-sizing wrapped content previously
                // caused an AppKit/SwiftUI constraint cycle.
                ScrollView { content }.frame(width: 460, height: 480)
                #else
                ScrollView { content }
                #endif
            }
        }
        .toolPanelAppearance(isEmbedded: isEmbedded)
    }

    private func close() { if let onClose { onClose() } else { dismiss() } }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.title3.weight(.medium)).foregroundStyle(EditorChrome.purple)
                    .frame(width: 38, height: 38)
                    .background(EditorChrome.lavender, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                Text(L10n.compressTitle).font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { task?.cancel(); close() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30).background(EditorChrome.lavender, in: Circle())
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(L10n.done)
                .accessibilityIdentifier("compress-close")
            }
            if let loaded {
                HStack(spacing: 12) {
                    Image(systemName: "doc.richtext")
                        .font(.title2).foregroundStyle(EditorChrome.purple)
                        .frame(width: 44, height: 56)
                        .background(EditorChrome.lavender, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: loaded.name).font(.subheadline.weight(.semibold))
                        note(L10n.compressCurrentSize(size(loaded.bytes)))
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(EditorChrome.surface, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .combine)
                PanelSection(title: L10n.compressLevel) {
                    levelPicker.disabled(isWorking)
                    note(L10n.compressRule)
                }
                .onChange(of: preset) { _, _ in clearResult() }
                status
                actions(loaded)
            } else if case .failed = phase {
                note(L10n.exportFailed)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(18)
        .foregroundStyle(EditorChrome.navy)
        .tint(EditorChrome.purple)
        #if os(iOS)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        #endif
        .background(EditorChrome.secondaryBackground)
        .background(SystemSharePresenter(request: $shareRequest, finished: { _ in }))
        .modifier(SaveExportedFiles(isPresented: $isSaving, output: result?.output, format: .pdf, onSaved: {}))
        .task { await load() }
        .onDisappear { task?.cancel(); result?.output.removeTemporaryFiles() }
    }

    /// Light, Strong or Smallest.
    ///
    /// On a Mac this is the native segmented control. The shared
    /// `PanelSegmented` picks between a row and a column by measuring which
    /// fits, and inside a Mac sheet — which sizes itself to its content — that
    /// measuring and the sheet's own looped ("AttributeGraph: cycle
    /// detected", found by drawing the sheet in stages), so the sheet never
    /// left its spinner. Three short words always fit a row here anyway.
    @ViewBuilder private var levelPicker: some View {
        #if os(macOS)
        Picker(L10n.compressLevel, selection: $preset) {
            Text(L10n.compressLight).tag(CompressionPreset.light)
            Text(L10n.compressStrong).tag(CompressionPreset.strong)
            Text(L10n.compressSmallest).tag(CompressionPreset.smallest)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("compress-level")
        #else
        PanelSegmented(options: [
            .init(value: CompressionPreset.light, title: L10n.compressLight, id: "compress-light"),
            .init(value: CompressionPreset.strong, title: L10n.compressStrong, id: "compress-strong"),
            .init(value: CompressionPreset.smallest, title: L10n.compressSmallest, id: "compress-smallest"),
        ], selection: $preset)
        #endif
    }

    /// A quiet line of explanation. Not `PanelNote`: that one forces its text
    /// to its full height, and inside a Mac sheet — which sizes itself to its
    /// content — that and the sheet's height waited on each other and SwiftUI
    /// looped ("AttributeGraph: cycle detected" millions of times), leaving
    /// the sheet on its spinner for good. A plain wrapping line has no loop.
    private func note(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.caption)
            .foregroundStyle(EditorChrome.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isWorking: Bool { if case .working = phase { true } else { false } }

    @ViewBuilder private var status: some View {
        switch phase {
        case .working(let fraction):
            ProgressView(value: fraction).accessibilityIdentifier("compress-progress")
        case .done(let result):
            VStack(alignment: .leading, spacing: 4) {
                if result.isSmaller {
                    Text(L10n.compressResult(size(result.originalByteCount), size(result.compressedByteCount),
                                             (result.savedFraction ?? 0).formatted(.percent.precision(.fractionLength(0)))))
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text(L10n.compressNoGain).font(.subheadline.weight(.semibold))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EditorChrome.lavender, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("compress-result")
        case .failed:
            note(L10n.exportFailed)
        case .choosing:
            EmptyView()
        }
    }

    @ViewBuilder private func actions(_ loaded: (name: String, pages: [Page], bytes: Int64)) -> some View {
        if result == nil {
            Button { start(loaded) } label: {
                Label { Text(L10n.compressAction) } icon: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .foregroundStyle(Color.white)
                    .background(EditorChrome.selection, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            .accessibilityIdentifier("compress-start")
        } else {
            HStack(spacing: 10) {
                secondary(L10n.exportSave, symbol: "square.and.arrow.down", id: "compress-save") { isSaving = true }
                secondary(L10n.exportShare, symbol: "square.and.arrow.up", id: "compress-share") {
                    if let files = result?.output.files { shareRequest = ShareRequest(files: files) }
                }
            }
        }
    }

    private func secondary(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label { Text(verbatim: title) } icon: { Image(systemName: symbol) }
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(EditorChrome.lavender, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func clearResult() {
        result?.output.removeTemporaryFiles()
        if case .done = phase { phase = .choosing }
    }

    private func load() async {
        guard let store = session.environment?.store else { phase = .failed; return }
        do {
            guard let item = try await store.item(itemID) else { phase = .failed; return }
            let pages = try await store.pages(of: itemID)
            let bytes = try await store.originalByteCount(of: itemID)
            loaded = (item.name, pages, bytes)
        } catch { phase = .failed }
    }

    private func start(_ loaded: (name: String, pages: [Page], bytes: Int64)) {
        guard let exporter = session.environment?.exporter else { phase = .failed; return }
        let preset = preset
        phase = .working(0)
        task = Task {
            do {
                let result = try await exporter.compress(itemName: loaded.name, pages: loaded.pages,
                                                         originalByteCount: loaded.bytes, preset: preset) { progress in
                    let fraction = progress.totalPages > 0 ? Double(progress.completedPages) / Double(progress.totalPages) : 0
                    Task { @MainActor in if case .working = phase { phase = .working(fraction) } }
                }
                if Task.isCancelled { result.output.removeTemporaryFiles(); return }
                phase = .done(result)
            } catch is CancellationError {
                phase = .choosing
            } catch {
                phase = .failed
            }
        }
    }
}

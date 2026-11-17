import Foundation
import PaperNestCore
import PaperNestExport
import PaperNestStore
import SwiftUI

/// The selection as it was when the sheet opened. Later library refreshes
/// must not change what the archive contains.
struct BulkExportRequest: Identifiable {
    let id = UUID()
    let ids: [ItemID]
}

/// Exports several chosen documents as one ZIP of PDFs. The archive writer is
/// the same one the Settings backup uses; only the set of documents differs.
@MainActor @Observable
final class BulkExportModel {
    enum Phase {
        case idle
        case exporting(ExportProgress)
        case ready(ExportOutput)
        case failed
    }

    let session: LibrarySession
    private(set) var phase: Phase = .idle
    private var task: Task<Void, Never>?

    init(session: LibrarySession) {
        self.session = session
    }

    var output: ExportOutput? {
        if case .ready(let output) = phase { return output }
        return nil
    }

    /// Exports `ids` in the order given. Documents with no pages are skipped;
    /// if none of them has a page the export fails rather than writing an
    /// empty archive.
    func start(_ ids: [ItemID], archiveName: String) {
        guard let env = session.environment, case .idle = phase, !ids.isEmpty else { return }
        phase = .exporting(ExportProgress(completedPages: 0, totalPages: 0))
        task = Task {
            do {
                var entries: [LibraryExportEntry] = []
                for id in ids {
                    guard let item = try await env.store.item(id), !item.isDeleted else { continue }
                    if let payload = try await env.store.filePayload(id) {
                        // A file goes in as itself, not re-rendered as a PDF,
                        // and its original is resolved through the record's
                        // own kind: an assumed kind names a file that was
                        // never written and costs the whole archive.
                        entries.append(.file(name: item.name, originalFilename: payload.originalFilename,
                                             url: try await env.store.originalURL(for: payload.assetID)))
                    } else {
                        entries.append(.document(LibraryExportItem(name: item.name, pages: try await env.store.pages(of: id))))
                    }
                }
                // A free user's PDFs carry the PaperNest mark, as any export of
                // theirs does. Decided once entitlements have loaded, so a
                // paying user is not marked for opening this soon after launch.
                if !SubscriptionStore.shared.hasLoaded { await SubscriptionStore.shared.refresh() }
                // Cancelled while waiting: nothing is started, so nothing is left behind.
                try Task.checkCancellation()
                let pdfOptions = ExportOptions(format: .pdf, paperSize: .original, pdfImageQuality: .balanced,
                                               attribution: Watermark.freeExportMark)
                let output = try await env.exporter.exportArchive(entries, archiveName: archiveName,
                                                                  pdfOptions: pdfOptions) { progress in
                    Task { @MainActor in
                        if case .exporting = self.phase { self.phase = .exporting(progress) }
                    }
                }
                // A cancel that lands after the last page still throws the
                // finished archive away, so nothing is left in the temporary
                // directory and the user sees the state they asked for.
                if Task.isCancelled {
                    output.removeTemporaryFiles()
                } else {
                    phase = .ready(output)
                }
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed
            }
        }
    }

    func cancel() {
        task?.cancel()
        phase = .idle
    }

    /// Drops the temporary archive once it has been saved, shared or dismissed.
    func finish() {
        task?.cancel()
        if case .ready(let output) = phase { output.removeTemporaryFiles() }
        phase = .idle
    }
}

struct BulkExportSheet: View {
    let request: BulkExportRequest
    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var model: BulkExportModel?
    @State private var isShowingSaver = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.zipper")
                            .font(.title2.weight(.medium))
                            .foregroundStyle(EditorChrome.purple)
                            .frame(width: 48, height: 56)
                            .background(EditorChrome.lavender, in: RoundedRectangle(cornerRadius: 14))
                            .accessibilityHidden(true)
                        Text(L10n.selectionCount(request.ids.count))
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        body(for: model?.phase ?? .idle)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(EditorChrome.surface, in: RoundedRectangle(cornerRadius: 16))
                    Text(L10n.exportZipFooter)
                        .font(.footnote)
                        .foregroundStyle(EditorChrome.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if !SubscriptionStore.shared.allows(.removeWatermark) {
                        Text(L10n.exportWatermarkFreeRedrawNote)
                            .font(.footnote)
                            .foregroundStyle(EditorChrome.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("export-zip-mark-note")
                    }
                }
                .padding(20)
            }
            .navigationTitle(L10n.exportZipTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.done) { close() }
                        .accessibilityIdentifier("bulk-export-done")
                }
            }
            .modifier(SaveExportedFiles(isPresented: $isShowingSaver, output: model?.output, format: .pdf) { close() })
            .task {
                guard model == nil else { return }
                let model = BulkExportModel(session: session)
                self.model = model
                let date = Date().formatted(.iso8601.year().month().day())
                model.start(request.ids, archiveName: L10n.exportZipArchiveName(date))
            }
        }
        .toolPanelAppearance()
        #if os(macOS)
        .frame(width: 460, height: 340)
        #endif
    }

    @ViewBuilder
    private func body(for phase: BulkExportModel.Phase) -> some View {
        switch phase {
        case .idle:
            ProgressView()
        case .exporting(let progress):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress.fraction) {
                    Text(L10n.exportProgress(min(progress.completedPages + 1, max(progress.totalPages, 1)),
                                             max(progress.totalPages, 1)))
                        .font(.caption)
                }
                Button(L10n.cancel, role: .cancel) { close() }
            }
            .accessibilityIdentifier("bulk-export-progress")
        case .ready(let output):
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.exportReady(ByteCountFormatter.string(fromByteCount: output.totalByteCount, countStyle: .file)))
                    .accessibilityIdentifier("bulk-export-status")
                VStack(alignment: .leading, spacing: 10) {
                    ShareLink(items: output.files) {
                        Label(L10n.exportShare, systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("bulk-export-share")
                    Button(L10n.exportSave) { isShowingSaver = true }
                        .accessibilityIdentifier("bulk-export-save")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        case .failed:
            Text(L10n.exportFailed)
                .foregroundStyle(.red)
                .accessibilityIdentifier("bulk-export-status")
        }
    }

    private func close() {
        model?.finish()
        dismiss()
    }
}

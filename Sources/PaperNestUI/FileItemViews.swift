import Foundation
import PaperNestCore
import PaperNestStore
import SwiftUI
import UniformTypeIdentifiers

/// How a file item is shown when there is no page to draw.
enum FileKind {
    /// A symbol chosen from what the file actually is, never from its name.
    static func symbol(for uti: String) -> String {
        guard let type = UTType(uti) else { return "doc" }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return "film" }
        if type.conforms(to: .audio) { return "music.note" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .archive) || type.conforms(to: .zip) { return "doc.zipper" }
        if type.conforms(to: .spreadsheet) { return "tablecells" }
        if type.conforms(to: .presentation) { return "rectangle.on.rectangle" }
        if type.conforms(to: .text) { return "doc.plaintext" }
        return "doc"
    }

    /// The system's own name for the type, or a plain fallback. Never a guess
    /// dressed up as a fact.
    static func description(for uti: String) -> String {
        UTType(uti)?.localizedDescription ?? L10n.fileKindUnknown
    }

    /// Only offer to unpack things we can actually read.
    static func isArchive(_ uti: String) -> Bool {
        guard let type = UTType(uti) else { return false }
        return type.conforms(to: .zip)
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Prepare a copy off the UI actor without loading a large file into memory.
    /// Retain the returned owner for as long as a preview, share or save uses it.
    static func prepareTemporaryCopy(of payload: FilePayload, in store: LibraryStore) async throws -> PreparedFileCopy {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("PaperNestFile-\(UUID().uuidString)", isDirectory: true)
            let basename = (payload.originalFilename as NSString).lastPathComponent
            let name = ["", ".", "..", "/"].contains(basename) ? "\(payload.assetID.sha256).bin" : basename
            let copy = PreparedFileCopy(url: directory.appendingPathComponent(name), directory: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: store.assets.url(for: payload.assetID, kind: .file), to: copy.url)
            try Task.checkCancellation()
            return copy
        }
        return try await withTaskCancellationHandler {
            let copy = try await worker.value
            try Task.checkCancellation()
            return copy
        } onCancel: {
            worker.cancel()
        }
    }
}

/// Owns only the directory this copy created. View disappearance is not a
/// lifetime boundary: sharing or saving can temporarily cover the parent view.
final class PreparedFileCopy: Sendable {
    let url: URL
    private let directory: URL

    fileprivate init(url: URL, directory: URL) {
        self.url = url
        self.directory = directory
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}

struct FileDetailsRequest: Identifiable {
    let id = UUID()
    let summary: LibraryStore.ItemSummary
}

/// What a file is, where it came from and how big it is, with share/save actions.
struct FileDetailsSheet: View {
    let request: FileDetailsRequest
    var existingCopy: PreparedFileCopy? = nil
    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var preparedCopy: PreparedFileCopy?
    @State private var isShowingSaver = false
    @State private var failed = false

    private var payload: FilePayload? { request.summary.file }
    private var shareURL: URL? { preparedCopy?.url ?? existingCopy?.url }

    var body: some View {
        NavigationStack {
            Form {
                if let payload {
                    Section {
                        HStack(spacing: 14) {
                            Image(systemName: FileKind.symbol(for: payload.uti))
                                .font(.largeTitle)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 44)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(request.summary.item.name).font(.headline)
                                Text(verbatim: FileKind.size(payload.byteCount))
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("file-details-header")
                    }
                    Section {
                        LabeledContent(L10n.fileKind, value: FileKind.description(for: payload.uti))
                        LabeledContent(L10n.fileOriginalName, value: payload.originalFilename)
                        LabeledContent(L10n.fileSize, value: FileKind.size(payload.byteCount))
                        LabeledContent(L10n.fileAdded, value: request.summary.item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent(L10n.fileModified, value: request.summary.item.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    Section {
                        if let shareURL {
                            ShareLink(item: shareURL) {
                                Label(L10n.exportShare, systemImage: "square.and.arrow.up")
                            }
                            .accessibilityIdentifier("file-share")
                        }
                        Button {
                            isShowingSaver = true
                        } label: {
                            Label(L10n.fileSaveCopy, systemImage: "arrow.down.circle")
                        }
                        .disabled(shareURL == nil)
                        .accessibilityIdentifier("file-save-copy")
                    } footer: {
                        Text(L10n.fileDetailsFooter)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(L10n.fileDetailsTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.done) { dismiss() }.accessibilityIdentifier("file-details-done")
                }
            }
            .fileExporter(isPresented: $isShowingSaver, document: shareURL.map(ExportedFile.init),
                          contentType: UTType(payload?.uti ?? "") ?? .data,
                          defaultFilename: payload?.originalFilename) { _ in }
            .alert(L10n.genericErrorTitle, isPresented: $failed) {
                Button(L10n.ok) {}
            } message: {
                Text(L10n.saveFailed)
            }
            .task {
                guard shareURL == nil, let payload, let store = session.environment?.store else { return }
                do {
                    preparedCopy = try await FileKind.prepareTemporaryCopy(of: payload, in: store)
                } catch is CancellationError {
                    // Dismissing the sheet is not a failed save.
                } catch { failed = true }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 320, idealHeight: 380)
        #endif
    }
}

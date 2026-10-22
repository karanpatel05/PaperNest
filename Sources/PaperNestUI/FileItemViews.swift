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

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Copies the stored bytes to a temporary file under the name the user
    /// gave it, for sharing or saving. The library's own copy is untouched.
    static func temporaryCopy(of payload: FilePayload, in store: LibraryStore) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestFile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(payload.originalFilename)
        // Copied from the asset file rather than read into memory, so a large
        // video costs no more than the copy itself.
        try FileManager.default.copyItem(at: store.assets.url(for: payload.assetID, kind: .file), to: destination)
        return destination
    }
}

struct FileDetailsRequest: Identifiable {
    let id = UUID()
    let summary: LibraryStore.ItemSummary
}

/// What a file is, where it came from and how big it is — the "Show Info" of
/// the reference app, and the only way to open a file until QuickLook lands.
struct FileDetailsSheet: View {
    let request: FileDetailsRequest
    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var shareURL: URL?
    @State private var isShowingSaver = false
    @State private var failed = false

    private var payload: FilePayload? { request.summary.file }

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
                do { shareURL = try FileKind.temporaryCopy(of: payload, in: store) } catch { failed = true }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 320, idealHeight: 380)
        #endif
    }
}

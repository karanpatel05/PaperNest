import Foundation
import PaperNestCore

/// One document to include in a library backup.
public struct LibraryExportItem: Sendable {
    public var name: String
    public var pages: [Page]

    public init(name: String, pages: [Page]) {
        self.name = name
        self.pages = pages
    }
}

/// What one entry of an archive is. A document is rendered to a PDF as the
/// app shows it; a file is copied exactly as it was given to us, because
/// re-encoding someone's video or spreadsheet would be a lie about what they
/// got back.
///
/// The single exception is an explicit compression preset, which reaches only
/// what can genuinely be re-encoded — an image. Everything else still arrives
/// byte for byte even then, and a re-encoded image changes extension, which is
/// a real change to what someone gets back and is said rather than hidden.
public enum LibraryExportEntry: Sendable {
    case document(LibraryExportItem)
    case file(name: String, originalFilename: String, url: URL)

    var displayName: String {
        switch self {
        case .document(let item): item.name
        case .file(let name, _, _): name
        }
    }

    /// Units of work, so progress means something for a mixed selection.
    var weight: Int {
        switch self {
        case .document(let item): item.pages.count
        case .file: 1
        }
    }
}

extension Exporter {
    /// Exports every item as a PDF, as shown in the app with edits applied,
    /// into one ZIP: a portable backup that opens anywhere, independent of
    /// PaperNest and of sync. Items without pages are skipped. Progress
    /// counts pages across the whole library; cancelling removes everything
    /// written so far.
    public func exportLibrary(
        _ items: [LibraryExportItem],
        archiveName: String,
        pdfOptions: ExportOptions = ExportOptions(format: .pdf, paperSize: .original, pdfImageQuality: .balanced),
        progress: @Sendable (ExportProgress) -> Void = { _ in }
    ) async throws -> ExportOutput {
        try await exportArchive(items.map { .document($0) }, archiveName: archiveName,
                                pdfOptions: pdfOptions, progress: progress)
    }

    /// Packs a mixed selection into one ZIP: documents as PDFs, files as the
    /// bytes they arrived with. Entries that hold nothing are skipped, and an
    /// archive with nothing in it is an error rather than an empty file.
    /// `preset` makes the archive smaller. It returns the ordinary
    /// `ExportOutput` rather than a `CompressionResult`, deliberately: a
    /// saving needs a "before", and for a document that is the originals it
    /// is made of, which live in the store this cannot see. The caller
    /// already knows what it had, so nothing here invents a baseline.
    ///
    /// Two rules: **nothing is dropped** — anything that cannot be compressed
    /// goes in as it was, because an archive missing a file is data loss that
    /// stays invisible until someone looks for it — and **nothing is grown**,
    /// so a re-encode that came out bigger is discarded and the original kept.
    public func exportArchive(
        _ entries: [LibraryExportEntry],
        archiveName: String,
        pdfOptions: ExportOptions = ExportOptions(format: .pdf, paperSize: .original, pdfImageQuality: .balanced),
        preset: CompressionPreset? = nil,
        progress: @Sendable (ExportProgress) -> Void = { _ in }
    ) async throws -> ExportOutput {
        let exportable = entries.filter { $0.weight > 0 }
        guard !exportable.isEmpty else { throw ExportError.noPages }
        let totalPages = exportable.reduce(0) { $0 + $1.weight }
        let directory = temporaryRoot.appendingPathComponent("PaperNestExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let archive = directory.appendingPathComponent("\(ExportNaming.baseName(archiveName, fallback: "Backup")).zip")
            let zip = try ZipWriter(url: archive)
            var usedNames: [String] = []
            var completed = 0
            progress(ExportProgress(completedPages: 0, totalPages: totalPages))
            for entry in exportable {
                try Task.checkCancellation()
                // Distinct items can share a name (or sanitize to the same
                // one); every entry gets its own file.
                let offset = completed
                switch entry {
                case .document(let item):
                    let base = NameDeduplicator.uniqueName(ExportNaming.baseName(item.name), existing: usedNames)
                    usedNames.append(base)
                    let pdf = try await export(itemName: item.name, pages: item.pages, options: pdfOptions,
                                               rasterQuality: preset?.rasterQuality) { inner in
                        progress(ExportProgress(completedPages: offset + inner.completedPages, totalPages: totalPages))
                    }
                    defer { pdf.removeTemporaryFiles() }
                    try zip.addFile(named: "\(base).pdf", data: Data(contentsOf: pdf.files[0]))
                case .file(_, let filename, let url):
                    // Kept under the name it came in with, extension and all.
                    let sanitized = ExportNaming.baseName((filename as NSString).deletingPathExtension)
                    let ext = (filename as NSString).pathExtension
                    let base = NameDeduplicator.uniqueName(sanitized, existing: usedNames)
                    usedNames.append(base)
                    let original = try Data(contentsOf: url)
                    let (data, extension_) = try await reduced(original, named: filename,
                                                               extension: ext, preset: preset)
                    try zip.addFile(named: extension_.isEmpty ? base : "\(base).\(extension_)", data: data)
                }
                completed += entry.weight
                progress(ExportProgress(completedPages: completed, totalPages: totalPages))
            }
            try zip.finish()
            return ExportOutput(directory: directory, files: [archive])
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}

extension Exporter {
    /// One loose file, re-encoded if a preset was asked for and it is actually
    /// worth it. Returns the bytes to archive and the extension they should
    /// carry.
    ///
    /// Three ways to end up with the original, all of them normal: no preset
    /// was given; the bytes are not something that can be re-encoded (a video,
    /// a spreadsheet, a protected PDF), which `compress` refuses outright; or
    /// the re-encode came out no smaller, which is the common case for an
    /// already-compact photo.
    private func reduced(_ original: Data, named filename: String, extension ext: String,
                         preset: CompressionPreset?) async throws -> (Data, String) {
        guard let preset else { return (original, ext) }
        guard let result = try? await compress(fileNamed: filename, data: original, preset: preset) else {
            return (original, ext)
        }
        defer { result.output.removeTemporaryFiles() }
        guard let compressed = try? Data(contentsOf: result.output.files[0]),
              compressed.count < original.count else { return (original, ext) }
        return (compressed, result.output.files[0].pathExtension)
    }
}

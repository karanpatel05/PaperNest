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
        let exportable = items.filter { !$0.pages.isEmpty }
        guard !exportable.isEmpty else { throw ExportError.noPages }
        let totalPages = exportable.reduce(0) { $0 + $1.pages.count }
        let directory = temporaryRoot.appendingPathComponent("PaperNestExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let archive = directory.appendingPathComponent("\(ExportNaming.baseName(archiveName, fallback: "Backup")).zip")
            let zip = try ZipWriter(url: archive)
            var usedNames: [String] = []
            var completed = 0
            progress(ExportProgress(completedPages: 0, totalPages: totalPages))
            for item in exportable {
                try Task.checkCancellation()
                // Distinct documents can share a name (or sanitize to the
                // same one); every entry gets its own file.
                let base = NameDeduplicator.uniqueName(ExportNaming.baseName(item.name), existing: usedNames)
                usedNames.append(base)
                let offset = completed
                let pdf = try await export(itemName: item.name, pages: item.pages, options: pdfOptions) { inner in
                    progress(ExportProgress(completedPages: offset + inner.completedPages, totalPages: totalPages))
                }
                defer { pdf.removeTemporaryFiles() }
                try zip.addFile(named: "\(base).pdf", data: Data(contentsOf: pdf.files[0]))
                completed += item.pages.count
            }
            try zip.finish()
            return ExportOutput(directory: directory, files: [archive])
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}

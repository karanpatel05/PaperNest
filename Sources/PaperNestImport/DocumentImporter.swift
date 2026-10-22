import Foundation
import PaperNestCore
import PaperNestStore

/// Turns files, pasted data and camera scans into library items or pages.
///
/// Originals are validated, then durably stored, then referenced by a single
/// database transaction (see `AssetFileStore`). PDFs stay vector PDFs; pages
/// are never rasterized on import.
public struct DocumentImporter: Sendable {
    public let store: LibraryStore

    public init(store: LibraryStore) {
        self.store = store
    }

    public enum Source: Sendable {
        /// A file URL, possibly security-scoped (file picker, drag and drop).
        case file(URL)
        /// In-memory bytes, e.g. a pasted image or a camera scan.
        case data(Data, name: String)

        var displayName: String {
            switch self {
            case .file(let url): url.lastPathComponent
            case .data(_, let name): name
            }
        }

        var suggestedItemName: String {
            switch self {
            case .file(let url):
                return url.deletingPathExtension().lastPathComponent
            case .data(_, let name):
                let ext = (name as NSString).pathExtension.lowercased()
                return ["pdf", "jpg", "jpeg", "png"].contains(ext) ? (name as NSString).deletingPathExtension : name
            }
        }
    }

    /// Validated pages ready to be committed.
    public struct Prepared: Sendable {
        public var suggestedName: String
        public var pages: [LibraryStore.NewPage]
        public var assets: [AssetFileStore.StagedAsset]
    }

    /// Validates `source` and durably stores its original. Nothing is visible
    /// in the library until the result is committed.
    public func prepare(_ source: Source, password: String? = nil) throws -> Prepared {
        let data = try loadData(source)
        let name = source.displayName
        guard !data.isEmpty else { throw ImportError.empty(filename: name) }
        guard let kind = FileTypeSniffer.kind(of: data) else { throw ImportError.unsupportedType(filename: name) }
        switch kind {
        case .file:
            // This path builds page-based documents. Bytes we do not
            // interpret become file items, which have their own import.
            throw ImportError.unsupportedType(filename: name)
        case .pdf:
            let facts = try PDFInspector.open(data, password: password, filename: name)
            let staged = try store.assets.store(facts.storedData, kind: .pdf, originalFilename: name)
            let pages = facts.pageSizes.enumerated().map { index, size in
                LibraryStore.NewPage(sourceSize: size, content: .pdfPage(staged.id, index: index))
            }
            return Prepared(suggestedName: source.suggestedItemName, pages: pages, assets: [staged])
        case .jpeg, .png:
            let facts = try ImageInspector.inspect(data, expected: kind, filename: name)
            let staged = try store.assets.store(data, kind: kind, originalFilename: name)
            return Prepared(suggestedName: source.suggestedItemName,
                            pages: [LibraryStore.NewPage(sourceSize: facts.pointSize, content: .image(staged.id))],
                            assets: [staged])
        }
    }

    /// `prepare`, off the caller's thread: reading and validating a large
    /// file must not block the UI.
    public func prepareInBackground(_ source: Source, password: String? = nil) async throws -> Prepared {
        try prepare(source, password: password)
    }

    /// Prepares several sources (e.g. one camera session) as one ordered
    /// set of pages.
    public func prepareAll(_ sources: [Source], password: String? = nil) async throws -> Prepared {
        var pages: [LibraryStore.NewPage] = []
        var assets: [AssetFileStore.StagedAsset] = []
        for source in sources {
            let prepared = try prepare(source, password: password)
            pages += prepared.pages
            assets += prepared.assets
        }
        guard let first = sources.first, !pages.isEmpty else { throw ImportError.empty(filename: "") }
        return Prepared(suggestedName: first.suggestedItemName, pages: pages, assets: assets)
    }

    /// Imports one file or data blob as a new document.
    public func importItem(_ source: Source, password: String? = nil, folderID: FolderID? = nil) async throws -> LibraryItem {
        let prepared = try prepare(source, password: password)
        return try await store.createItem(kind: .document, name: prepared.suggestedName, folderID: folderID,
                                          pages: prepared.pages, assets: prepared.assets)
    }

    /// Combines several images (e.g. one camera scan session) into a single
    /// document, in the order given.
    public func importScan(images: [Data], name: String, folderID: FolderID? = nil) async throws -> LibraryItem {
        guard !images.isEmpty else { throw ImportError.empty(filename: name) }
        let prepared = try await prepareAll(images.enumerated().map { .data($1, name: "\(name) \($0 + 1)") })
        return try await store.createItem(kind: .document, name: name, folderID: folderID, pages: prepared.pages, assets: prepared.assets)
    }

    /// Adds the pages of `source` to an existing item after `pageID`
    /// (or at the end).
    @discardableResult
    public func insertPages(from source: Source, password: String? = nil, into itemID: ItemID, after pageID: PageID?) async throws -> [Page] {
        let prepared = try prepare(source, password: password)
        return try await store.insertPages(prepared.pages, into: itemID, after: pageID, assets: prepared.assets)
    }

    /// Reads the bytes behind `source`, e.g. to keep a protected PDF in
    /// memory while the user is asked for its password.
    public func loadData(_ source: Source) throws -> Data {
        switch source {
        case .data(let data, _):
            return data
        case .file(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            // Coordinated reading lets cloud file providers download the file
            // first and keeps other writers from changing it mid-read.
            var coordinationError: NSError?
            var result: Result<Data, Error> = .failure(ImportError.unreadable(filename: url.lastPathComponent))
            NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { readURL in
                result = Result { try Data(contentsOf: readURL, options: .mappedIfSafe) }
            }
            if coordinationError != nil { throw ImportError.unreadable(filename: url.lastPathComponent) }
            do {
                return try result.get()
            } catch {
                throw ImportError.unreadable(filename: url.lastPathComponent)
            }
        }
    }
}

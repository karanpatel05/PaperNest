import Foundation
import PaperNestCore
import PaperNestStore
import UniformTypeIdentifiers

/// Brings a file into the library as itself, rather than as pages.
///
/// The bytes are copied and hashed in one streaming pass, so a large video
/// never has to be held in memory, and they are durable before any row
/// references them — the same rule the page importer follows.
public struct FileItemImporter: Sendable {
    public let store: LibraryStore

    public init(store: LibraryStore) {
        self.store = store
    }

    /// What the library will show for a file, decided before anything is
    /// copied so a refusal costs nothing.
    public struct Description: Sendable, Equatable {
        public var itemName: String
        public var originalFilename: String
        public var uti: String
    }

    public static func describe(_ url: URL) -> Description {
        let filename = url.lastPathComponent
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
        // The system invents a *dynamic* type for an extension it does not
        // know. That identifier means nothing on another device or after
        // sync, so unknown bytes are recorded as plain data instead.
        let known = type.flatMap { $0.isDynamic ? nil : $0 }
        return Description(
            itemName: url.deletingPathExtension().lastPathComponent,
            originalFilename: filename,
            uti: known?.identifier ?? UTType.data.identifier
        )
    }

    @discardableResult
    public func importFile(at url: URL, into folderID: FolderID? = nil) async throws -> LibraryItem {
        let description = Self.describe(url)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        // Coordinated reading lets a cloud provider materialize the file and
        // keeps another writer from changing it while it is copied.
        var coordinationError: NSError?
        var staged: Result<AssetFileStore.StagedAsset, Error> =
            .failure(ImportError.unreadable(filename: description.originalFilename))
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { readURL in
            staged = Result {
                try store.assets.store(contentsOf: readURL, kind: .file,
                                       originalFilename: description.originalFilename)
            }
        }
        if coordinationError != nil { throw ImportError.unreadable(filename: description.originalFilename) }
        let asset: AssetFileStore.StagedAsset
        do {
            asset = try staged.get()
        } catch {
            throw ImportError.unreadable(filename: description.originalFilename)
        }

        return try await store.createFileItem(named: description.itemName, folderID: folderID, asset: asset,
                                              uti: description.uti,
                                              originalFilename: description.originalFilename)
    }
}

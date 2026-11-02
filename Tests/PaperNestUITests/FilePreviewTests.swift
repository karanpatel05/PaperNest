import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestRender
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestUI

@Suite struct FilePreviewTests {
    @Test func temporaryPreviewHasRealExtensionAndCannotChangeTheStoredOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestPreviewTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root)
        let bytes = Data("synthetic preview text".utf8)
        let staged = try store.assets.store(bytes, kind: .file, originalFilename: "Résumé.txt")
        _ = try await store.createFileItem(named: "Résumé", asset: staged, uti: "public.plain-text", originalFilename: "Résumé.txt")
        let payload = FilePayload(assetID: staged.id, uti: "public.plain-text", originalFilename: "Résumé.txt", byteCount: Int64(bytes.count))
        var copy: PreparedFileCopy? = try await FileKind.prepareTemporaryCopy(of: payload, in: store)
        let url = try #require(copy?.url)
        #expect(url.lastPathComponent == "Résumé.txt")
        #expect(try Data(contentsOf: url) == bytes)
        try Data("changed preview".utf8).write(to: url)
        #expect(try store.assets.read(staged.id, kind: .file) == bytes)
        copy = nil
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        #expect(try store.assets.read(staged.id, kind: .file) == bytes)
    }

    @Test func previewNameCannotEscapeItsTemporaryDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestPreviewTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root)
        let staged = try store.assets.store(Data("synthetic".utf8), kind: .file, originalFilename: nil)
        _ = try await store.createFileItem(named: "Synthetic", asset: staged, uti: "public.data", originalFilename: "synthetic.bin")
        for name in ["../../report.txt", "..", ".", "/"] {
            let payload = FilePayload(assetID: staged.id, uti: "public.data", originalFilename: name, byteCount: staged.byteCount)
            let copy = try await FileKind.prepareTemporaryCopy(of: payload, in: store)
            #expect(copy.url.deletingLastPathComponent().lastPathComponent.hasPrefix("PaperNestFile-"))
            #expect(try Data(contentsOf: copy.url) == Data("synthetic".utf8))
        }
    }

    @Test func previewResolvesTheRecordedKindOfASharedAsset() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestPreviewTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root)
        let bytes = SyntheticDocuments.textPDF(pages: ["Synthetic shared asset"])
        let staged = try store.assets.store(bytes, kind: .pdf, originalFilename: "shared.pdf")
        let item = try await store.createFileItem(named: "Shared PDF", asset: staged, uti: "com.adobe.pdf", originalFilename: "shared.pdf")
        let payload = try #require(try await store.filePayload(item.id))
        let copy = try await FileKind.prepareTemporaryCopy(of: payload, in: store)
        #expect(copy.url.pathExtension == "pdf")
        #expect(try Data(contentsOf: copy.url) == bytes)
        #expect(try await store.assetData(staged.id).0 == bytes)
    }

    @Test func canceledPreparationDoesNotReturnAPreview() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestPreviewTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root)
        let staged = try store.assets.store(Data("synthetic".utf8), kind: .file, originalFilename: nil)
        let payload = FilePayload(assetID: staged.id, uti: "public.data", originalFilename: "sample.bin", byteCount: staged.byteCount)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await FileKind.prepareTemporaryCopy(of: payload, in: store)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    /// A copy with **no extension** tells Quick Look nothing, and it refuses to
    /// look inside: measured, such a file yields no thumbnail at all. The item
    /// already records what it is, so the staged copy borrows the extension
    /// from that type — which is what makes a thumbnail possible for a file
    /// whose name never had one.
    @Test func aCopyWithNoExtensionBorrowsOneFromTheRecordedType() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestPreviewTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root)
        let bytes = Data("a plain note with no extension on its name\n".utf8)
        let staged = try store.assets.store(bytes, kind: .file, originalFilename: "scan")
        _ = try await store.createFileItem(named: "Scan", asset: staged, uti: "public.plain-text", originalFilename: "scan")
        let payload = FilePayload(assetID: staged.id, uti: "public.plain-text",
                                  originalFilename: "scan", byteCount: Int64(bytes.count))

        let copy = try await FileKind.prepareTemporaryCopy(of: payload, in: store)

        #expect(copy.url.lastPathComponent == "scan.txt")
        // And that is the whole point: the system will now look inside it.
        let thumbnail = try await FileThumbnail.image(
            at: copy.url, boundedBy: CGSize(width: 88, height: 88), scale: 1)
        #expect(thumbnail != nil, "a staged copy still gave no thumbnail")
    }

    /// A name that already has an extension is left exactly as it is, even when
    /// it disagrees with the recorded type. This copy is what the share sheet
    /// hands over, and quietly renaming someone's file to match its bytes is
    /// not this function's business.
    @Test func aNameThatAlreadyHasAnExtensionIsNotRewritten() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestPreviewTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root)
        let bytes = Data("plain text under a misleading name\n".utf8)
        let staged = try store.assets.store(bytes, kind: .file, originalFilename: "notes.doc")
        _ = try await store.createFileItem(named: "Notes", asset: staged, uti: "public.plain-text", originalFilename: "notes.doc")
        let payload = FilePayload(assetID: staged.id, uti: "public.plain-text",
                                  originalFilename: "notes.doc", byteCount: Int64(bytes.count))

        let copy = try await FileKind.prepareTemporaryCopy(of: payload, in: store)

        #expect(copy.url.lastPathComponent == "notes.doc")
    }
}

import Foundation
import Testing
import PaperNestCore
import PaperNestStore
@testable import PaperNestUI

@Suite struct FilePreviewTests {
    @Test func temporaryPreviewHasRealExtensionAndCannotChangeTheStoredOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestPreviewTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(directory: root)
        let bytes = Data("synthetic preview text".utf8)
        let staged = try store.assets.store(bytes, kind: .file, originalFilename: "Résumé.txt")
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
        for name in ["../../report.txt", "..", ".", "/"] {
            let payload = FilePayload(assetID: staged.id, uti: "public.data", originalFilename: name, byteCount: staged.byteCount)
            let copy = try await FileKind.prepareTemporaryCopy(of: payload, in: store)
            #expect(copy.url.deletingLastPathComponent().lastPathComponent.hasPrefix("PaperNestFile-"))
            #expect(try Data(contentsOf: copy.url) == Data("synthetic".utf8))
        }
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
}

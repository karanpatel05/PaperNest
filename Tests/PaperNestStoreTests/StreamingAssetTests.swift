import CryptoKit
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// F2a: a file item can be a large video, so its bytes are copied and hashed
/// in one pass instead of being loaded whole.
@Suite struct StreamingAssetTests {
    private func writeFile(_ dir: borrowing TempDirectory, name: String, bytes: Int) throws -> (URL, Data) {
        // Varied bytes, so a truncated or reordered copy cannot pass by luck.
        var data = Data(count: bytes)
        for i in stride(from: 0, to: bytes, by: 7) { data[i] = UInt8((i / 7) % 251) }
        let url = dir.url.appendingPathComponent(name)
        try data.write(to: url)
        return (url, data)
    }

    @Test func aFileLargerThanTheBufferIsStoredByteForByteWithTheRightHash() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        // Several buffers plus a partial one, so the chunk loop is exercised.
        let (url, data) = try writeFile(dir, name: "Clip.mov", bytes: AssetFileStore.copyBufferSize * 2 + 12_345)

        let staged = try store.assets.store(contentsOf: url, kind: .file, originalFilename: "Clip.mov")
        #expect(staged.byteCount == Int64(data.count))
        #expect(staged.id == AssetFileStore.assetID(for: data), "the streamed hash must match the whole-file hash")
        #expect(try store.assets.read(staged.id, kind: .file) == data)
        try store.assets.verify(staged.id, kind: .file)
    }

    @Test func streamingAndInMemoryStoresAgreeAndDeduplicate() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (url, data) = try writeFile(dir, name: "Report.bin", bytes: 300_000)

        let streamed = try store.assets.store(contentsOf: url, kind: .file, originalFilename: "Report.bin")
        let inMemory = try store.assets.store(data, kind: .file, originalFilename: "Report-copy.bin")
        #expect(streamed.id == inMemory.id)
        // One file on disk for both: content addressing, not two copies.
        #expect(try store.assets.allFiles().filter { $0.id == streamed.id }.count == 1)

        // Storing it again over the existing file keeps the bytes intact.
        let again = try store.assets.store(contentsOf: url, kind: .file, originalFilename: "Report.bin")
        #expect(again.id == streamed.id)
        #expect(try store.assets.read(streamed.id, kind: .file) == data)
    }

    @Test func aDamagedStoredFileIsReplacedRatherThanTrusted() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (url, data) = try writeFile(dir, name: "Scan.bin", bytes: 50_000)
        let staged = try store.assets.store(contentsOf: url, kind: .file, originalFilename: "Scan.bin")

        // Corrupt the stored file, keeping its length, as a bad disk would.
        var damaged = data
        damaged[100] = damaged[100] &+ 1
        try damaged.write(to: store.assets.url(for: staged.id, kind: .file))
        #expect(throws: StoreError.self) { try store.assets.verify(staged.id, kind: .file) }

        let restored = try store.assets.store(contentsOf: url, kind: .file, originalFilename: "Scan.bin")
        #expect(restored.id == staged.id)
        #expect(try store.assets.read(staged.id, kind: .file) == data, "the damaged copy should have been replaced")
    }

    @Test func anUnreadableSourceLeavesNothingBehind() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let missing = dir.url.appendingPathComponent("gone.bin")

        #expect(throws: StoreError.self) {
            try store.assets.store(contentsOf: missing, kind: .file, originalFilename: "gone.bin")
        }
        #expect(try store.assets.allFiles().isEmpty)
        let staging = try FileManager.default.contentsOfDirectory(atPath: store.assets.stagingURL.path)
        #expect(staging.isEmpty, "a failed copy must not leave a staging file: \(staging)")
    }

    @Test func anEmptyFileStillStoresAndReadsBack() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let url = dir.url.appendingPathComponent("empty.txt")
        try Data().write(to: url)

        let staged = try store.assets.store(contentsOf: url, kind: .file, originalFilename: "empty.txt")
        #expect(staged.byteCount == 0)
        #expect(staged.id == AssetFileStore.assetID(for: Data()))
        #expect(try store.assets.read(staged.id, kind: .file).isEmpty)
    }
}

import Foundation
import Testing
import UniformTypeIdentifiers
import PaperNestCore
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestUI

/// F2c: photos picked from the system library. The picker itself is Apple's
/// and is driven by the user; what is tested here is everything after it —
/// the bytes it hands back becoming documents.
@MainActor
@Suite(.serialized) struct PhotoImportTests {
    let root: URL
    let libraryURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestPhotos-\(UUID().uuidString)", isDirectory: true)
        libraryURL = root.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func readySession() async throws -> LibrarySession {
        let session = LibrarySession(libraryURL: libraryURL)
        await session.bootstrap()
        guard case .ready = session.state else {
            Issue.record("library did not open: \(session.state)")
            throw CancellationError()
        }
        return session
    }

    @Test func eachPhotoBecomesItsOwnDocument() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try await readySession()
        let library = LibraryModel(session: session)
        let heic = SyntheticDocuments.image(width: 600, height: 900, type: .heic, dpi: 300)
        let jpeg = SyntheticDocuments.image(width: 400, height: 400, type: .jpeg)

        await library.importPhotos([(heic, "Photo 1.heic"), (jpeg, "Photo 2.jpg")])
        await library.reload()

        #expect(library.items.count == 2, "two photos, two documents — not one document of two pages")
        #expect(library.presentedError == nil)
        let env = try #require(session.environment)
        for summary in library.items {
            #expect(summary.item.kind == .document)
            #expect(summary.pageCount == 1)
        }
        // The HEIC kept its resolution, so it is a 2×3 inch page.
        let fromHEIC = try #require(library.items.first { $0.item.name.contains("1") })
        let page = try await env.store.pages(of: fromHEIC.id)[0]
        #expect(abs(page.sourceSize.width - 144) < 1)
        let asset = try #require(page.content.assetID)
        #expect(try await env.store.assetRecord(asset)?.kind == .heic)
    }

    @Test func oneUnreadablePhotoDoesNotStopTheRest() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try await readySession()
        let library = LibraryModel(session: session)
        let good = SyntheticDocuments.image(width: 200, height: 200, type: .png)

        await library.importPhotos([(Data("not an image".utf8), "Broken.heic"), (good, "Good.png")])
        await library.reload()

        #expect(library.items.count == 1, "the readable photo should still be imported")
        #expect(library.presentedError != nil, "the failure should be reported, not swallowed")
    }

    @Test func photosLandInTheFolderOnScreen() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try await readySession()
        let library = LibraryModel(session: session)
        let env = try #require(session.environment)
        let folder = try await env.store.createFolder(named: "Receipts")
        library.sidebarSelection = .folder(folder.id)
        await library.reload()

        await library.importPhotos([(SyntheticDocuments.image(width: 300, height: 300, type: .heic), "Shot.heic")])
        #expect(try await env.store.items(in: .folder(folder.id)).count == 1)
    }
}

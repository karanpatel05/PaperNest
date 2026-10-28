import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
import PaperNestRender

/// Ledger row 8's remaining piece: a picture of what a file item actually
/// holds, rather than the symbol for its type.
///
/// Every test writes a file with a **unique name and unique bytes**, because
/// Quick Look keeps a thumbnail cache: a test that reused a name could pass on
/// an earlier test's picture and prove nothing. One probe in this project was
/// read wrongly for exactly that reason.
@Suite struct FileThumbnailTests {
    /// Its own directory, removed afterwards. Residue in the shared temp root
    /// has already failed an unrelated test here once.
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileThumbnailTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Bytes no other test has written, so no cached thumbnail can match them.
    private func writeUniqueText(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("PaperNest \(UUID().uuidString)\nsecond line\nthird line\n".utf8).write(to: url)
        return url
    }

    @Test func aReadableFileGivesAPictureOfItsContents() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try writeUniqueText(named: "\(UUID().uuidString).txt", in: directory)

        let image = try await FileThumbnail.image(
            at: file, boundedBy: CGSize(width: 200, height: 200), scale: 1)

        let thumbnail = try #require(image, "Quick Look reads plain text; this should be a picture")
        #expect(thumbnail.width > 0)
        #expect(thumbnail.height > 0)
    }

    /// The honest answer to "no preview for this type" is *nothing*.
    ///
    /// This is the guard on asking Quick Look for `.thumbnail` only. Ask it for
    /// `.all` and this same file comes back as a 512×512 generic **type icon**
    /// — which is the symbol the grid already draws, and passing that off as a
    /// picture of the contents would be inventing a preview. If someone widens
    /// the representation types, this test is what fails.
    @Test func aFileTheSystemCannotReadGivesNothingRatherThanAnIcon() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // `.bin` is exactly how a stored asset is named on disk.
        let file = try writeUniqueText(named: "\(UUID().uuidString).bin", in: directory)

        let image = try await FileThumbnail.image(
            at: file, boundedBy: CGSize(width: 200, height: 200), scale: 1)

        #expect(image == nil)
    }

    /// A file that is not there is a different thing from a file with no
    /// preview, and the system says so: `NSCocoaErrorDomain` 4 rather than
    /// `QLThumbnailErrorDomain` 0. Reporting it as "no preview" would hide a
    /// missing original behind a blank square.
    @Test func aFileThatIsNotThereIsAnErrorRatherThanNoPreview() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let absent = directory.appendingPathComponent("\(UUID().uuidString).txt")

        await #expect(throws: FileThumbnailError.noSuchFile) {
            try await FileThumbnail.image(
                at: absent, boundedBy: CGSize(width: 200, height: 200), scale: 1)
        }
    }

    /// The size asked for is a box the picture fits inside, not the size it
    /// comes back as. Measured: asked 120×400, a text file gives 120×120.
    @Test func theThumbnailFitsInsideTheBoxItWasGiven() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try writeUniqueText(named: "\(UUID().uuidString).txt", in: directory)

        let image = try #require(try await FileThumbnail.image(
            at: file, boundedBy: CGSize(width: 120, height: 400), scale: 1))

        #expect(image.width <= 120)
        #expect(image.height <= 400)
    }

    /// Scale asks for more pixels in the same box, as a Retina grid cell needs.
    @Test func scaleAsksForMorePixelsInTheSameBox() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let single = try writeUniqueText(named: "\(UUID().uuidString).txt", in: directory)
        let double = try writeUniqueText(named: "\(UUID().uuidString).txt", in: directory)
        let box = CGSize(width: 64, height: 64)

        let one = try #require(try await FileThumbnail.image(at: single, boundedBy: box, scale: 1))
        let two = try #require(try await FileThumbnail.image(at: double, boundedBy: box, scale: 2))

        #expect(two.width > one.width)
        #expect(two.width <= 128)
    }

    /// What a caller has to do, pinned so the advice in the doc comment is a
    /// measurement and not a suggestion: the same bytes give nothing under the
    /// name a stored asset carries, and a picture under the extension the
    /// item's own recorded type names.
    @Test func theRecordedTypeNamesTheFileWhenTheStoredNameCannot() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let body = "PaperNest \(UUID().uuidString)\nsecond line\nthird line\n"
        let box = CGSize(width: 200, height: 200)

        let stored = directory.appendingPathComponent("\(UUID().uuidString).bin")
        try Data(body.utf8).write(to: stored)
        #expect(try await FileThumbnail.image(at: stored, boundedBy: box, scale: 1) == nil)

        let extensionFromType = try #require(UTType("public.plain-text")?.preferredFilenameExtension)
        let named = directory.appendingPathComponent("\(UUID().uuidString).\(extensionFromType)")
        try Data(body.utf8).write(to: named)
        #expect(try await FileThumbnail.image(at: named, boundedBy: box, scale: 1) != nil)
    }
}

import Foundation
import Testing
import PaperNestTestSupport
import PaperNestImport

/// Ledger row 42's backend: how long a media file is, and what it calls
/// itself. The owner confirmed row 42 on 2026-10-23; playing the file is a
/// view and is not this.
@Suite struct MediaInspectionTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaInspectionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ data: Data, named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    /// The length has to be the file's own, not a guess from its size.
    @Test func anAudioFileReportsItsRealLength() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try write(SyntheticDocuments.wavAudio(seconds: 1.5),
                             named: "recording.wav", in: directory)

        let info = try #require(try await MediaInspection.inspect(at: file))

        let duration = try #require(info.duration)
        #expect(abs(duration - 1.5) < 0.01)
    }

    /// A player needs to know whether there is a picture to show.
    @Test func anAudioFileHasSoundAndNoPicture() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try write(SyntheticDocuments.wavAudio(), named: "recording.wav", in: directory)

        let info = try #require(try await MediaInspection.inspect(at: file))

        #expect(info.hasAudio)
        #expect(!info.hasVideo)
    }

    /// Read from the file's own tags.
    ///
    /// `asset.load(.commonMetadata)` is **empty** for this file even though the
    /// tags are there — measured — so a reader built on it would quietly find
    /// nothing. The items only come back through
    /// `AVMetadataItem.metadataItems(from:filteredByIdentifier:)`.
    @Test func aRecordingsOwnTitleAndArtistAreRead() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try write(
            SyntheticDocuments.wavAudio(title: "A Quiet Recording", artist: "PaperNest Tests"),
            named: "recording.wav", in: directory)

        let info = try #require(try await MediaInspection.inspect(at: file))

        #expect(info.title == "A Quiet Recording")
        #expect(info.artist == "PaperNest Tests")
    }

    /// An untagged file says so, rather than borrowing its filename.
    @Test func anUntaggedFileReportsNothingRatherThanGuessing() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try write(SyntheticDocuments.wavAudio(), named: "Holiday Mix.wav", in: directory)

        let info = try #require(try await MediaInspection.inspect(at: file))

        #expect(info.title == nil)
        #expect(info.artist == nil)
    }

    /// Most file items are not media, and that is an answer rather than a fault.
    @Test func aFileThatIsNotMediaIsNotAnError() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try write(Data("just some words\n".utf8), named: "notes.txt", in: directory)

        #expect(try await MediaInspection.inspect(at: file) == nil)
    }

    /// The same trap the thumbnail engine has, reached a different way: a
    /// stored asset is `<sha>.bin`, and AVFoundation refuses it outright
    /// (`AVFoundationErrorDomain` −11828) even though the bytes are playable.
    /// So a caller must stage a copy under a name that says what the file is.
    @Test func theStoredAssetNameIsNotEnoughToReadIt() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let playable = SyntheticDocuments.wavAudio(seconds: 1.5)

        let stored = try write(playable, named: "abc123.bin", in: directory)
        #expect(try await MediaInspection.inspect(at: stored) == nil)

        let named = try write(playable, named: "abc123.wav", in: directory)
        #expect(try await MediaInspection.inspect(at: named) != nil)
    }

    /// A missing original must not look like "this is not media".
    @Test func aFileThatIsNotThereIsAnError() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        await #expect(throws: MediaInspectionError.noSuchFile) {
            try await MediaInspection.inspect(at: directory.appendingPathComponent("gone.wav"))
        }
    }
}

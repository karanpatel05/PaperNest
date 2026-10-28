import AVFoundation
import Foundation

public enum MediaInspectionError: Error, Equatable, Sendable {
    /// There is nothing at that URL.
    ///
    /// Kept apart from *this is not a media file*, which is `nil`, so a
    /// missing original cannot be mistaken for an ordinary document.
    case noSuchFile
}

/// What a media file says about itself.
///
/// Every value here is read from the file. Nothing is inferred from its name
/// or its size, so an untagged file reports `nil` rather than borrowing
/// "Holiday Mix" from its filename.
public struct MediaInfo: Hashable, Sendable {
    /// Seconds, from the file's own timing.
    ///
    /// `nil` when the file declares no finite length — which no local file in
    /// testing did, so that branch is written but unexercised. It is `nil`
    /// rather than `0` because a wrong zero would be shown as a length.
    public let duration: Double?
    public let hasAudio: Bool
    /// Whether there is a picture to show as well as sound.
    public let hasVideo: Bool
    public let title: String?
    public let artist: String?
    public let albumName: String?
    /// The cover the file carries, **as the bytes it carries**.
    ///
    /// Not decoded or re-rendered here: handing back the original bytes means
    /// nothing is lost or invented on the way, and the caller decides what
    /// size it wants to draw.
    public let artwork: Data?
}

/// What a media file is, before anything plays it.
///
/// Ledger row 42's groundwork. A player needs the length to draw a scrubber
/// and the file's own title to label it; both come from here, and playing it
/// is a view's job rather than this one's.
///
/// **The URL must carry an extension that says what the file is.** A stored
/// asset is named `<sha256>.bin`, and AVFoundation refuses that outright —
/// `AVFoundationErrorDomain` −11828, measured on bytes it reads happily under
/// a `.wav` name. This is the same requirement `FileThumbnail` has, arrived at
/// through different machinery, so the two agree: stage a copy named from
/// `FilePayload.originalFilename`, or from `UTType(uti)`.
public enum MediaInspection {
    /// What the file at `url` says about itself, or `nil` when AVFoundation
    /// does not recognise it as media at all.
    ///
    /// `nil` is an answer, not a failure: most file items are documents.
    public static func inspect(at url: URL) async throws -> MediaInfo? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MediaInspectionError.noSuchFile
        }
        let asset = AVURLAsset(url: url)
        do {
            let (duration, tracks, metadata) = try await (
                asset.load(.duration), asset.load(.tracks), asset.load(.metadata))
            return MediaInfo(
                duration: duration.isNumeric ? CMTimeGetSeconds(duration) : nil,
                hasAudio: tracks.contains { $0.mediaType == .audio },
                hasVideo: tracks.contains { $0.mediaType == .video },
                title: await string(.commonIdentifierTitle, in: metadata),
                artist: await string(.commonIdentifierArtist, in: metadata),
                albumName: await string(.commonIdentifierAlbumName, in: metadata),
                artwork: await data(.commonIdentifierArtwork, in: metadata))
        } catch let error as NSError where error.isNotRecognisedAsMedia {
            return nil
        }
        // A file AVFoundation recognises but cannot parse reports something
        // else, and is thrown rather than called "not media". Only −11828 was
        // measured, so only −11828 is treated as an answer.
    }

    /// One field, found the way that works across formats.
    ///
    /// `asset.load(.commonMetadata)` is **empty** for a WAV whose title and
    /// artist are plainly there — measured — so reading that list, which is
    /// the obvious thing to do, finds nothing. Filtering all the items by a
    /// common identifier does the per-format mapping instead, and turns
    /// `caaf/info-title` into a title.
    private static func string(_ identifier: AVMetadataIdentifier,
                               in items: [AVMetadataItem]) async -> String? {
        guard let item = first(identifier, in: items) else { return nil }
        return try? await item.load(.stringValue) ?? nil
    }

    /// The same lookup, for a field whose value is bytes rather than words.
    private static func data(_ identifier: AVMetadataIdentifier,
                             in items: [AVMetadataItem]) async -> Data? {
        guard let item = first(identifier, in: items) else { return nil }
        return try? await item.load(.dataValue) ?? nil
    }

    private static func first(_ identifier: AVMetadataIdentifier,
                              in items: [AVMetadataItem]) -> AVMetadataItem? {
        AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier).first
    }
}

private extension NSError {
    /// AVFoundation's own answer that this is not a file it reads as media.
    ///
    /// Matched on the domain as well as the code, and deliberately narrow: a
    /// different AVFoundation failure is a problem to report, not a document.
    var isNotRecognisedAsMedia: Bool {
        domain == AVFoundationErrorDomain && code == AVError.Code.fileFormatNotRecognized.rawValue
    }
}

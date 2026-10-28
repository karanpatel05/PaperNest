import CoreGraphics
import Foundation
import QuickLookThumbnailing

public enum FileThumbnailError: Error, Equatable, Sendable {
    /// There is nothing at that URL.
    ///
    /// Distinct from *the system has no preview for this kind of file*, which
    /// is `nil` rather than an error, so a missing original cannot hide behind
    /// a blank square.
    case noSuchFile
}

/// A picture of what a file item actually holds, from the system's Quick Look.
///
/// Ledger row 8's remaining piece. A file item already shows its size and a
/// symbol for its type; this is the thumbnail of the contents that a grid or
/// list cell can show instead, when the system can make one.
///
/// **This takes a URL and does not stage anything.** Two things follow from
/// how a library stores a file, and a caller has to deal with both:
///
/// - A stored asset is named `<sha256>.bin`, because `AssetKind.file` covers
///   every type. Quick Look decides what a file *is* from its extension, and
///   refuses `.bin` outright, so handing it the asset's own path always
///   answers `nil`.
/// - So the URL must carry the real extension. `FilePayload.originalFilename`
///   is the first source; when that basename is unusable, the item's recorded
///   `uti` gives one through `UTType(uti)?.preferredFilenameExtension`. That
///   is measured, not advice: the test
///   `theRecordedTypeNamesTheFileWhenTheStoredNameCannot` writes the same
///   bytes both ways and gets nothing from one and a picture from the other.
///
/// `FileKind.prepareTemporaryCopy` already makes such a copy for the full
/// preview, so this deliberately does not add a second way to stage files.
public enum FileThumbnail {
    /// Pictures of the contents, and deliberately **not** `.icon`.
    ///
    /// Asked for `.all`, Quick Look answers anything it cannot read with a
    /// generic 512×512 icon for the file's type — measured on a `.bin`, a file
    /// with no extension and an unknown extension alike. That icon is the
    /// symbol the grid already draws from `uti`, so returning it here would
    /// dress a type symbol up as a preview of the contents. Both of these are
    /// real renderings of the file; a low-quality one is still the file.
    private static let contentPreviews: QLThumbnailGenerator.Request.RepresentationTypes =
        [.thumbnail, .lowQualityThumbnail]

    /// A thumbnail of the file's contents, or `nil` when the system has none
    /// for that kind of file.
    ///
    /// **`nil` is an answer, not a failure.** Most types have no preview, and
    /// the caller's job then is to keep showing the type symbol rather than to
    /// report a problem.
    ///
    /// `boundedBy` is a box the picture fits inside, not the size it comes back
    /// as: Quick Look keeps the document's own proportions. Measured, asking
    /// 120×400 of a text file gives 120×120. `scale` multiplies the pixels in
    /// that box, so a Retina cell asks for the points it will draw and a scale
    /// of 2.
    public static func image(at url: URL,
                             boundedBy size: CGSize,
                             scale: CGFloat) async throws -> CGImage? {
        // Asked about a file that is not there, Quick Look answers with
        // `NSCocoaErrorDomain` 4 — close enough to its own "cannot preview"
        // to be worth not relying on. Checking here says plainly which it is.
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileThumbnailError.noSuchFile
        }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale,
                                                   representationTypes: contentPreviews)
        do {
            let representation = try await QLThumbnailGenerator.shared
                .generateBestRepresentation(for: request)
            return representation.cgImage
        } catch let error as NSError where error.isNoPreviewAvailable {
            return nil
        }
        // Anything else — a cancelled or invalid request, or the file going
        // away after the check above — is thrown, not reported as "no preview".
    }
}

private extension NSError {
    /// Quick Look's own answer that it cannot make a picture of this file.
    ///
    /// Matched on the domain as well as the code, so an unrelated error that
    /// happens to be 0 is not read as "no preview".
    var isNoPreviewAvailable: Bool {
        domain == QLThumbnailError.errorDomain && code == QLThumbnailError.Code.generationFailed.rawValue
    }
}

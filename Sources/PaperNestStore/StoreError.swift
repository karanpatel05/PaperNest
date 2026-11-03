import Foundation

public enum StoreError: Error, Equatable, Sendable {
    case database(code: Int32, message: String)
    /// The library was written by a newer app version. It is left untouched
    /// rather than risk damaging data this version does not understand.
    case newerSchema(found: Int, supported: Int)
    case itemNotFound
    case folderNotFound
    case pageNotFound
    case assetMissing(String)
    case assetChecksumMismatch(String)
    case invalidComment
    case invalidOrder
    /// Something was offered for a page that could not be put on one: bytes
    /// the renderer cannot decode as an image, or a frame with no area. Both
    /// are refused at the write, because the alternative is finding out when
    /// someone opens the page and the object is already saved.
    case invalidPlacement
    case notebookPageChanged
    /// Recognition or the page changed while a text-markup picker was open.
    case recognitionChanged
    /// Saved marks or page geometry changed while the markup manager was open.
    case pageObjectsChanged
    /// A recolor was asked for on something that has no ink colour — a placed
    /// image, or a text box, whose colour is not what that picker means.
    /// Refused rather than quietly skipped, so no caller can believe a mark
    /// was recoloured when it was left alone.
    case cannotRecolor
    case io(String)
    /// A migration left dangling references behind; the library is rolled
    /// back to its previous, consistent version.
    case migrationBrokeReferences(String)
}

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
    case invalidOrder
    case io(String)
}

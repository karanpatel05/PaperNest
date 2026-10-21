import Foundation

/// Every product-name and identifier decision lives here so the working name
/// ("PaperNest" is a placeholder, not a cleared trademark) can be changed in one
/// place before release. Bundle identifiers live in `Config/Base.xcconfig`.
public enum Brand {
    /// Customer-visible product name. Localized strings take it as a `%@`
    /// argument instead of embedding the name in translations.
    public static let displayName = "PaperNest"

    /// Directory name under Application Support that holds the local library.
    public static let storageDirectoryName = "PaperNest"

    /// Written into exported PDF metadata as the creating application.
    public static let pdfCreator = "PaperNest"
}

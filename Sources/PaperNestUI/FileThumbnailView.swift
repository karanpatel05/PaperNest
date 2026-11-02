import CoreGraphics
import PaperNestCore
import PaperNestRender
import SwiftUI

/// A picture of what a file actually holds, falling back to the symbol for its
/// type.
///
/// **The fallback is the ordinary case, not an error path.** Most types have no
/// preview at all, and the symbol is a different claim rather than a worse
/// thumbnail — "this is a spreadsheet" instead of "this is what the
/// spreadsheet looks like". Nothing here invents the second from the first, and
/// `FileThumbnail` is asked only for a real rendering of the contents for the
/// same reason: asked for anything it can take, the system hands back a
/// generic type icon, which is the symbol below dressed up as a preview.
struct FileThumbnailView: View {
    /// A staged copy of the file, or nil while there is not one yet.
    ///
    /// Never the stored asset's own path: that is `<sha256>.bin`, because
    /// `AssetKind.file` covers every type, and the system refuses to look
    /// inside a `.bin`.
    let url: URL?
    let uti: String
    /// The longest edge, in points.
    var size: CGFloat = 44

    @State private var thumbnail: CGImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: FileKind.symbol(for: uti))
                    .font(.largeTitle)
                    .foregroundStyle(Theme.accent)
            }
        }
        // A fixed box either way, so the row does not change height when a
        // thumbnail arrives after the copy is staged.
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            thumbnail = nil
            return
        }
        // Nothing is thrown away quietly here that matters: `nil` means the
        // system has no preview for this kind of file, which is an answer and
        // not a fault, and a missing copy is already reported by the sheet
        // around this view.
        thumbnail = try? await FileThumbnail.image(
            at: url, boundedBy: CGSize(width: size, height: size), scale: 2)
    }
}

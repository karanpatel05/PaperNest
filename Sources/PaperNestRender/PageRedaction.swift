import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import PaperNestCore

public enum RedactionError: Error, Equatable, Sendable {
    /// Redacting nothing. Rewriting the page unchanged would spend a content
    /// replacement, bump its revision and discard its text for no reason, and
    /// would report a redaction that did not happen.
    case noRectangles
    case encodingFailed
}

/// Removing content from a page rather than covering it.
///
/// A black rectangle drawn over a word is the classic fake. In a PDF the word
/// is still there underneath: selectable, searchable, and recoverable by
/// anyone who opens the file with the right tool. The only way to be sure a
/// word is gone is for it not to be in the bytes.
///
/// So the page is **flattened**: rendered to pixels, painted, and stored as an
/// image. The cost is real and has to be said wherever this is offered — a
/// digital PDF loses its selectable text across the **whole page**, not just
/// the redacted part, and the page becomes a picture of itself.
///
/// What this does not do:
///
/// - It does not touch ink, comments or other page objects, which live in
///   their own rows. A note sitting under a redaction rectangle survives it.
/// - It does not scrub the disk. Deleting the original asset unlinks a file;
///   the bytes may persist until overwritten, and on a copy-on-write file
///   system that is not controllable from here.
public enum PageRedaction {
    /// Resolution of the flattened page. 200 dpi keeps small print legible
    /// without turning every redacted page into a huge file.
    public static let defaultDPI: CGFloat = 200

    /// The page, flattened, with `rectangles` painted out — as PNG.
    ///
    /// PNG rather than JPEG deliberately: a lossy encode leaves ringing around
    /// the edge of a painted rectangle and artefacts around the text next to
    /// it, which is exactly the residue a recovery tool looks for.
    ///
    /// `rectangles` are in upright, uncropped source space with a top-left
    /// origin, the same space as ink and recognised text, so a redaction
    /// stays on its words through any later crop or rotation.
    public static func redactedPNG(for page: Page, rectangles: [NormalizedRect],
                                   renderer: PageRenderer,
                                   dpi: CGFloat = defaultDPI) async throws -> Data {
        guard !rectangles.isEmpty else { throw RedactionError.noRectangles }
        let pixelsPerPoint = dpi / 72
        let source = try await renderer.uprightSourceRaster(for: page, pixelsPerPoint: pixelsPerPoint)

        let painted = try PageRenderer.bitmap(width: source.width, height: source.height) { ctx in
            ctx.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            for rect in rectangles {
                // Source space is y-down and the bitmap is y-up, so the
                // rectangle is flipped as it is placed. Rounding outwards:
                // half a pixel of a letter left showing is a legible letter.
                let x = (rect.x * Double(source.width)).rounded(.down)
                let width = (rect.width * Double(source.width)).rounded(.up)
                let height = (rect.height * Double(source.height)).rounded(.up)
                let top = (rect.y * Double(source.height)).rounded(.down)
                let y = Double(source.height) - top - height
                ctx.fill(CGRect(x: x, y: y, width: width, height: height))
            }
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
                data, UTType.png.identifier as CFString, 1, nil) else {
            throw RedactionError.encodingFailed
        }
        CGImageDestinationAddImage(destination, painted, nil)
        guard CGImageDestinationFinalize(destination) else { throw RedactionError.encodingFailed }
        return data as Data
    }
}

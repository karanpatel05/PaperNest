import CoreGraphics

/// What a redaction would leave behind, worked out before anything is
/// written, so the review can say it.
///
/// Redacting flattens the page's paper into a picture and paints the areas
/// black. Marks — ink, text boxes, placed pictures — are not paper: they live
/// in rows of their own and are drawn **over** the picture, on screen and in
/// every export, and a text box's words answer searches. A mark over a black
/// area would show the very thing redacted, so the review names those marks
/// and the redaction removes them, whole, unless told not to.
public enum PageRedactionReview {
    /// The marks drawn over any of `areas` (normalized to the source), in the
    /// order given. A mark touching an area by any amount counts: half a
    /// signature over a redacted name is enough to read it.
    ///
    /// Private comments are never drawn or exported, so they are never here.
    public static func marksOverlapping(_ areas: [NormalizedRect], in objects: [PageObject],
                                        sourceSize: CGSize) -> [PageObject] {
        let painted = areas.map { $0.denormalized(in: sourceSize) }
        return objects.filter { object in
            guard let bounds = object.drawnSourceBounds else { return false }
            return painted.contains { $0.intersects(bounds) }
        }
    }

    /// Private comments on the page: kept by a redaction, since they never
    /// leave the app.
    public static func comments(in objects: [PageObject]) -> [PageObject] {
        objects.filter { $0.commentText != nil }
    }
}

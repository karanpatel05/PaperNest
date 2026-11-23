import CoreGraphics
import Foundation

/// Edits that act on a lassoed selection as a whole: making it larger or
/// smaller, turning it, and laying copies of it on a page.
///
/// Each is worked out in page space — the page as the reader sees it, cropped
/// and turned — and carried into source space through `PageGeometry`, so a
/// selection on a turned page grows towards the corner the reader dragged and
/// turns the way the reader turned it. Nothing here writes: the results go to
/// the store through its guarded calls, like any other change to a page.
public enum SelectionEdits {
    public enum Failure: Error, Equatable, Sendable {
        /// A text box or a placed image cannot be turned or stretched: neither
        /// stores an angle, and its words or picture would no longer fit the
        /// frame. Only uniform scaling and moving apply to them.
        case cannotRotate
        /// The result would not be a usable mark: a value that is not finite,
        /// nothing to act on, or something that is not painted on the page (a
        /// private comment).
        case invalid
    }

    /// The smallest a selection may be made, on its longer side, in page
    /// points. Smaller than this and the lasso could hardly loop it again.
    public static let minimumSide: Double = 8

    /// Where the objects are drawn on the page as the reader sees it, ink's
    /// width included, or nil when none of them is drawn.
    public static func pageBounds(of objects: [PageObject], in geometry: PageGeometry) -> CGRect? {
        objects.compactMap(\.drawnSourceBounds).reduce(nil) { accumulated, next in
            let shown = next.applying(geometry.sourceToPage)
            return accumulated.map { $0.union(shown) } ?? shown
        }
    }

    /// `objects` with `transform` applied, `transform` being in page space.
    ///
    /// Ink is carried point by point, and its line is made thicker or thinner
    /// by the same amount as the writing, keeping each point's recorded
    /// pressure and timing. A text box's type is scaled with its frame, or the
    /// words would no longer fit it. A text box or an image refuses anything
    /// but moving and uniform scaling (`cannotRotate`). Ids and paint order are
    /// kept: this is the same marks changed, which is what undo expects.
    public static func transformed(_ objects: [PageObject], by transform: CGAffineTransform,
                                   in geometry: PageGeometry, at date: Date = Date()) throws -> [PageObject] {
        let source = geometry.sourceToPage.concatenating(transform).concatenating(geometry.pageToSource)
        let determinant = source.a * source.d - source.b * source.c
        guard !objects.isEmpty,
              [source.a, source.b, source.c, source.d, source.tx, source.ty, determinant].allSatisfy(\.isFinite),
              determinant > 0 else { throw Failure.invalid }
        let factor = determinant.squareRoot()
        // After conjugating by a quarter turn a uniform scale is still exactly
        // one; the tolerance only absorbs the arithmetic of a free angle.
        let tolerance = 1e-9 * max(1, abs(source.a), abs(source.d))
        // A half turn has no off-diagonal part at all; it shows as a negative
        // scale, and would draw a text box upside down.
        let turnsOrStretches = abs(source.b) > tolerance || abs(source.c) > tolerance
            || abs(source.a - source.d) > tolerance || source.a <= 0
        return try objects.map { object in
            var result = object
            switch object.payload {
            case .ink(var stroke):
                stroke.points = stroke.points.map { point in
                    let mapped = CGPoint(x: point.x, y: point.y).applying(source)
                    return InkPoint(x: mapped.x, y: mapped.y, widthScale: point.widthScale, time: point.time)
                }
                stroke.width *= factor
                guard !stroke.points.isEmpty, stroke.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
                      stroke.width.isFinite, stroke.width > 0 else { throw Failure.invalid }
                result.payload = .ink(stroke)
            case .text(var box):
                guard !turnsOrStretches else { throw Failure.cannotRotate }
                box.frame = box.frame.applying(source)
                box.fontSize *= factor
                guard isUsable(box.frame), box.fontSize.isFinite, box.fontSize > 0 else { throw Failure.invalid }
                result.payload = .text(box)
            case .image(var image):
                guard !turnsOrStretches else { throw Failure.cannotRotate }
                image.frame = image.frame.applying(source)
                guard isUsable(image.frame) else { throw Failure.invalid }
                result.payload = .image(image)
            case .comment:
                throw Failure.invalid
            }
            result.modifiedAt = date
            return result
        }
    }

    // MARK: - Scaling

    /// How far a selection drawn over `bounds` may be scaled about `anchor`,
    /// all in page space: no smaller than `minimumSide` on its longer side,
    /// and no larger than keeps it on `page`.
    ///
    /// The lasso only picks up what it wholly encloses, so a selection grown
    /// past the page's edge could never be selected again. One that already
    /// hangs over an edge may keep its size or shrink, but not grow.
    public static func clampedScale(_ factor: Double, bounds: CGRect, anchor: CGPoint, page: CGRect) -> Double {
        guard factor.isFinite, factor > 0 else { return 1 }
        let longer = max(bounds.width, bounds.height)
        let lower = longer > 0 ? min(1, minimumSide / longer) : 1
        var upper = Double.infinity
        func limit(_ near: Double, _ far: Double, _ anchor: Double, _ edgeLow: Double, _ edgeHigh: Double) {
            if near < anchor { upper = min(upper, (anchor - edgeLow) / (anchor - near)) }
            if far > anchor { upper = min(upper, (edgeHigh - anchor) / (far - anchor)) }
        }
        limit(bounds.minX, bounds.maxX, anchor.x, page.minX, page.maxX)
        limit(bounds.minY, bounds.maxY, anchor.y, page.minY, page.maxY)
        upper = max(upper, 1)
        return min(max(factor, lower), max(upper, lower))
    }

    /// The selection made `factor` times its size about `anchor` (page
    /// space), the factor first held to what `clampedScale` allows.
    public static func scaled(_ objects: [PageObject], by factor: Double, about anchor: CGPoint,
                              in geometry: PageGeometry, at date: Date = Date()) throws -> [PageObject] {
        guard factor.isFinite, factor > 0, anchor.x.isFinite, anchor.y.isFinite,
              let bounds = pageBounds(of: objects, in: geometry) else { throw Failure.invalid }
        let allowed = clampedScale(factor, bounds: bounds, anchor: anchor,
                                   page: CGRect(origin: .zero, size: geometry.pageSize))
        return try transformed(objects, by: scaling(by: allowed, about: anchor), in: geometry, at: date)
    }

    static func scaling(by factor: Double, about anchor: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
            .concatenating(CGAffineTransform(scaleX: factor, y: factor))
            .concatenating(CGAffineTransform(translationX: anchor.x, y: anchor.y))
    }

    // MARK: - Turning

    /// The selection turned by `radians` about its centre as the reader sees
    /// it — positive is clockwise on screen — then moved back onto the page
    /// wherever the turn carried it over an edge.
    ///
    /// Ink only: a text box or an image refuses (`cannotRotate`).
    public static func rotated(_ objects: [PageObject], by radians: Double, in geometry: PageGeometry,
                               at date: Date = Date()) throws -> [PageObject] {
        guard radians.isFinite, let bounds = pageBounds(of: objects, in: geometry) else { throw Failure.invalid }
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        let turn = CGAffineTransform(translationX: -centre.x, y: -centre.y)
            .concatenating(CGAffineTransform(rotationAngle: radians))
            .concatenating(CGAffineTransform(translationX: centre.x, y: centre.y))
        return try keptInside(try transformed(objects, by: turn, in: geometry, at: date), in: geometry, at: date)
    }

    // MARK: - Copies

    /// Copies of `objects`, which lie on a page laid out as `origin`, for the
    /// page `pageID` laid out as `target`.
    ///
    /// Each copy has a new id and lands where its original sat on its own page
    /// as the reader saw it, moved by `shift` in page points; then the group is
    /// made smaller if it is larger than the target page, and moved back onto
    /// it if it hangs over an edge. Ink is carried through both pages'
    /// geometry, so it reads upright on a page turned differently. A text box
    /// or an image cannot turn, so it keeps its own size and only its centre is
    /// carried over — on a page turned differently it shows turned, as any box
    /// placed on that page does.
    ///
    /// The copies come back bottom to top in their originals' paint order,
    /// carrying the originals' sort keys only as that order: the store gives
    /// them their places on the target page.
    public static func copies(of objects: [PageObject], from origin: PageGeometry, onto target: PageGeometry,
                              pageID: PageID, shiftedBy shift: CGPoint = .zero,
                              at date: Date = Date()) throws -> [PageObject] {
        guard !objects.isEmpty, shift.x.isFinite, shift.y.isFinite else { throw Failure.invalid }
        let carry = origin.sourceToPage
            .concatenating(CGAffineTransform(translationX: shift.x, y: shift.y))
            .concatenating(target.pageToSource)
        let ordered = objects.sorted { ($0.zKey, $0.id.rawValue) < ($1.zKey, $1.id.rawValue) }
        let laid = try ordered.map { object -> PageObject in
            let payload: PageObject.Payload
            switch object.payload {
            case .ink(var stroke):
                stroke.points = stroke.points.map { point in
                    let mapped = CGPoint(x: point.x, y: point.y).applying(carry)
                    return InkPoint(x: mapped.x, y: mapped.y, widthScale: point.widthScale, time: point.time)
                }
                guard !stroke.points.isEmpty,
                      stroke.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { throw Failure.invalid }
                payload = .ink(stroke)
            case .text(var box):
                box.frame = recentred(box.frame, by: carry)
                guard isUsable(box.frame) else { throw Failure.invalid }
                payload = .text(box)
            case .image(var image):
                image.frame = recentred(image.frame, by: carry)
                guard isUsable(image.frame) else { throw Failure.invalid }
                payload = .image(image)
            case .comment:
                throw Failure.invalid
            }
            return PageObject(pageID: pageID, zKey: object.zKey, payload: payload, modifiedAt: date)
        }
        guard let bounds = pageBounds(of: laid, in: target) else { throw Failure.invalid }
        let page = target.pageSize
        let fit = min(1, page.width / bounds.width, page.height / bounds.height)
        let fitted = fit < 1
            ? try transformed(laid, by: scaling(by: fit, about: CGPoint(x: bounds.midX, y: bounds.midY)),
                              in: target, at: date)
            : laid
        return try keptInside(fitted, in: target, at: date)
    }

    /// The selection moved the least distance that puts it wholly on the page,
    /// or centred on it when it is larger than the page.
    public static func keptInside(_ objects: [PageObject], in geometry: PageGeometry,
                                  at date: Date = Date()) throws -> [PageObject] {
        guard let bounds = pageBounds(of: objects, in: geometry) else { throw Failure.invalid }
        let page = CGRect(origin: .zero, size: geometry.pageSize)
        func shift(_ low: Double, _ high: Double, _ edgeLow: Double, _ edgeHigh: Double) -> Double {
            if high - low > edgeHigh - edgeLow { return (edgeLow + edgeHigh) / 2 - (low + high) / 2 }
            if low < edgeLow { return edgeLow - low }
            if high > edgeHigh { return edgeHigh - high }
            return 0
        }
        let dx = shift(bounds.minX, bounds.maxX, page.minX, page.maxX)
        let dy = shift(bounds.minY, bounds.maxY, page.minY, page.maxY)
        guard dx != 0 || dy != 0 else { return objects }
        return try transformed(objects, by: CGAffineTransform(translationX: dx, y: dy), in: geometry, at: date)
    }

    private static func recentred(_ frame: CGRect, by carry: CGAffineTransform) -> CGRect {
        let centre = CGPoint(x: frame.midX, y: frame.midY).applying(carry)
        return CGRect(x: centre.x - frame.width / 2, y: centre.y - frame.height / 2,
                      width: frame.width, height: frame.height)
    }

    private static func isUsable(_ frame: CGRect) -> Bool {
        frame.width > 0 && frame.height > 0
            && [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
    }
}

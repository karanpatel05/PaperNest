import ImageIO
import PaperNestCore
import PaperNestRender
import PaperNestStore
import SwiftUI

/// Redacting a page: mark the areas, review the page exactly as it will be
/// written, then apply.
///
/// Nothing is written until Redact Page in the review. The review shows the
/// engine's own drawing of the redacted page, not an overlay imitating it, and
/// says what goes with it: the page's selectable text, everywhere on it; its
/// recognized text; the marks drawn over the areas (removed unless the
/// person says otherwise); and that it cannot be undone. It says too when it
/// cannot finish the job — another page still showing the same original, or
/// copies already in iCloud — rather than let anyone believe the content is
/// gone.
///
/// Areas are drawn on the page as it is seen and stored through
/// `PageGeometry`, in the upright, uncropped source space the engine paints in.
/// Drawing needs a pointer or a finger; there is no way yet to mark an area
/// with VoiceOver alone.
struct RedactEditor: View {
    let model: DocumentModel
    let page: Page
    let undoManager: UndoManager?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    /// Areas drawn, in points of the page as it is seen.
    @State private var areas: [CGRect] = []
    @State private var drawing: CGRect?
    @State private var step: Step = .marking
    @State private var removeMarks = true

    enum Step {
        case marking
        case preparing
        case reviewing(DocumentModel.RedactionReview)
        case applying
        /// Done, but another page still shows the original.
        case finishedWithSharedOriginal
        case failed(String)
    }

    private var pageSize: CGSize { page.geometry.pageSize }
    private var restricted: Bool { model.permissions.isRestricted }
    private var sourceAreas: [NormalizedRect] { areas.map { page.geometry.normalizedSourceRect(forPageRect: $0) } }
    private var busy: Bool {
        switch step {
        case .preparing, .applying: true
        default: false
        }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L10n.redactTitle)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.cancel) { dismiss() }
                            .disabled(busy)
                            .accessibilityIdentifier("redact-cancel")
                    }
                }
        }
        .interactiveDismissDisabled(busy || !areas.isEmpty)
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 620, idealHeight: 760)
        #endif
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .marking: marking
        case .preparing: waiting(L10n.redactPreparing)
        case .reviewing(let review): reviewing(review)
        case .applying: waiting(L10n.redactApplying)
        case .finishedWithSharedOriginal: message(L10n.redactDoneShared, identifier: "redact-done-shared")
        case .failed(let text): message(text, identifier: "redact-failed")
        }
    }

    // MARK: - Marking

    private var marking: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let scale = min(proxy.size.width / pageSize.width, proxy.size.height / pageSize.height)
                let shown = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
                ZStack(alignment: .topLeading) {
                    PageImageView(page: page, pixelSize: max(shown.width, shown.height) * displayScale)
                    ForEach(Array(areas.enumerated()), id: \.offset) { _, area in areaShape(area, scale: scale, drafting: false) }
                    if let drawing { areaShape(drawing, scale: scale, drafting: true) }
                }
                .frame(width: shown.width, height: shown.height)
                .contentShape(Rectangle())
                .gesture(drawGesture(scale: scale, shown: shown))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.redactPageLabel)
                .accessibilityHint(L10n.redactHint)
                // How many areas are marked, for tests and VoiceOver.
                .accessibilityValue(String(areas.count))
                .accessibilityIdentifier("redact-page")
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .padding(16)
            // Not under the navigation bar, where it would hide the title.
            .background(Color(white: 0.12), ignoresSafeAreaEdges: [])
            markingBar
        }
    }

    private func areaShape(_ area: CGRect, scale: CGFloat, drafting: Bool) -> some View {
        let shown = area.applying(CGAffineTransform(scaleX: scale, y: scale))
        return Rectangle()
            .fill(Color.black.opacity(drafting ? 0.45 : 0.75))
            .overlay { Rectangle().strokeBorder(Theme.accent, lineWidth: drafting ? 1 : 1.5) }
            .frame(width: max(1, shown.width), height: max(1, shown.height))
            .offset(x: shown.minX, y: shown.minY)
            .allowsHitTesting(false)
    }

    /// One drag, one area, kept to the page.
    private func drawGesture(scale: CGFloat, shown: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                drawing = Self.area(from: value.startLocation, to: value.location, within: shown, scale: scale)
            }
            .onEnded { value in
                drawing = nil
                let area = Self.area(from: value.startLocation, to: value.location, within: shown, scale: scale)
                if area.width >= 2, area.height >= 2 { areas.append(area) }
            }
    }

    /// The rectangle between two touches on the shown page, in page points.
    static func area(from start: CGPoint, to end: CGPoint, within shown: CGSize, scale: CGFloat) -> CGRect {
        func clamped(_ point: CGPoint) -> CGPoint {
            CGPoint(x: min(max(point.x, 0), shown.width), y: min(max(point.y, 0), shown.height))
        }
        let a = clamped(start), b = clamped(end)
        let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        return rect.applying(CGAffineTransform(scaleX: 1 / max(scale, 0.0001), y: 1 / max(scale, 0.0001)))
    }

    private var markingBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if restricted {
                Text(L10n.redactRestricted)
                    .font(.app(.caption)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("redact-restricted")
            } else {
                Text(L10n.redactHint)
                    .font(.app(.caption)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Text(L10n.redactAreaCount(areas.count))
                    .font(.app(.subheadline))
                    .accessibilityIdentifier("redact-count")
                    .accessibilityValue(String(areas.count))
                Spacer(minLength: 8)
                Button { _ = areas.popLast() } label: {
                    Label(L10n.redactRemoveLast, systemImage: "arrow.uturn.backward").labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(areas.isEmpty)
                .accessibilityIdentifier("redact-remove-last")
                Button(L10n.redactReview) { review() }
                    .buttonStyle(.borderedProminent)
                    .disabled(areas.isEmpty || restricted)
                    .accessibilityIdentifier("redact-review")
            }
        }
        .padding(16)
        .background(EditorChrome.surface)
    }

    private func review() {
        let areas = sourceAreas
        step = .preparing
        Task {
            do {
                step = .reviewing(try await model.redactionReview(of: page, areas: areas))
            } catch {
                step = .failed(L10n.redactFailed)
            }
        }
    }

    // MARK: - Review

    private func reviewing(_ review: DocumentModel.RedactionReview) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    preview(review.picture)
                    warning(L10n.redactWarningFlatten, symbol: "photo", identifier: "redact-warning-flatten")
                    if review.hasSelectableText {
                        warning(L10n.redactWarningWholePage, symbol: "text.badge.xmark", identifier: "redact-warning-text")
                    }
                    if !review.marks.isEmpty {
                        Toggle(isOn: $removeMarks) {
                            Text(L10n.redactRemoveMarks(review.marks.count)).fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityIdentifier("redact-remove-marks")
                        .accessibilityValue(removeMarks ? L10n.selectionOn : L10n.selectionOff)
                        if !removeMarks {
                            warning(L10n.redactMarksStay, symbol: "exclamationmark.triangle", identifier: "redact-warning-marks",
                                    tint: .red)
                        }
                    }
                    if review.comments > 0 {
                        warning(L10n.redactCommentsKept, symbol: "text.bubble", identifier: "redact-comments-kept")
                    }
                    if review.originalUsedElsewhere {
                        warning(L10n.redactShared, symbol: "doc.on.doc", identifier: "redact-warning-shared", tint: .orange)
                    }
                    if review.syncIsOn {
                        warning(L10n.redactSync, symbol: "icloud", identifier: "redact-warning-sync", tint: .orange)
                    }
                }
                .padding(16)
            }
            // Beside the button, never scrolled out of sight.
            VStack(alignment: .leading, spacing: 10) {
                warning(L10n.redactWarningUndo, symbol: "arrow.uturn.backward.circle", identifier: "redact-warning-undo",
                        tint: .red)
                HStack(spacing: 12) {
                    Button(L10n.redactBack) { step = .marking }
                        .accessibilityIdentifier("redact-back")
                    Spacer(minLength: 8)
                    Button(role: .destructive) { apply(review) } label: {
                        Text(L10n.redactApply).frame(minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .accessibilityIdentifier("redact-apply")
                }
            }
            .padding(16)
            .background(EditorChrome.surface)
        }
    }

    /// The redacted sheet as written, shown the way the page is seen: the
    /// engine paints the upright, uncropped source, and the page shows it
    /// through its crop and rotation.
    private func preview(_ png: Data) -> some View {
        let image = CGImageSourceCreateWithData(png as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        let geometry = page.geometry
        return Canvas { context, size in
            guard let image else { return }
            let scale = min(size.width / pageSize.width, size.height / pageSize.height)
            context.translateBy(x: (size.width - pageSize.width * scale) / 2, y: (size.height - pageSize.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            context.clip(to: Path(CGRect(origin: .zero, size: pageSize)))
            context.concatenate(geometry.sourceToPage)
            context.draw(Image(decorative: image, scale: 1), in: CGRect(origin: .zero, size: geometry.sourceSize))
        }
        .aspectRatio(pageSize.width / max(pageSize.height, 1), contentMode: .fit)
        .background(Color.white)
        .shadow(color: Theme.paperShadow, radius: 3, y: 1)
        .frame(maxWidth: .infinity, maxHeight: 380)
        .accessibilityElement()
        .accessibilityLabel(L10n.redactPreviewLabel)
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("redact-preview")
    }

    private func warning(_ text: String, symbol: String, identifier: String, tint: Color = .secondary) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
        .font(.app(.callout))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private func apply(_ review: DocumentModel.RedactionReview) {
        let areas = sourceAreas
        let marks = removeMarks ? review.marks : []
        step = .applying
        Task {
            do {
                let outcome = try await model.redact(page, areas: areas, removingMarks: marks, undoManager: undoManager)
                if outcome.originalStillInLibrary { step = .finishedWithSharedOriginal } else { dismiss() }
            } catch RedactionError.restrictedByAuthor {
                step = .failed(L10n.redactRestricted)
            } catch {
                step = .failed(L10n.redactFailed)
            }
        }
    }

    // MARK: - States

    private func waiting(_ text: String) -> some View {
        ProgressView(text).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func message(_ text: String, identifier: String) -> some View {
        VStack(spacing: 16) {
            Text(text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier)
            Button(L10n.done) { dismiss() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("redact-done")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

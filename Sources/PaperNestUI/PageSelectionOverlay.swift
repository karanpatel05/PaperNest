import PaperNestCore
import PaperNestStore
import SwiftUI

/// A single lasso for all editable page content, on every platform.
struct PageSelectionOverlay: View {
    let model: DocumentModel
    let page: Page
    let sourceToView: CGAffineTransform
    let visible: CGRect
    let mode: PageSelectionMode
    let selectAllRequest: Int
    var enablesTwoFingerNavigation = false
    /// The kinds of content a loop may pick up. Anything else on the page is
    /// invisible to the lasso: not selected, not moved, not counted.
    var allowed: Set<LassoContent> = Set(LassoContent.allCases)
    let undoManager: UndoManager?
    @Binding var hiddenIDs: Set<PageObjectID>
    let onOpen: (PageObject) -> Void
    @Environment(\.displayScale) private var displayScale
    @State private var selectedIDs: Set<PageObjectID> = []
    @State private var selectionContour: PageSelectionContour?
    @State private var points: [CGPoint] = []
    @State private var moving: [PageObject] = []
    @State private var movePage: Page?
    @State private var translation: CGSize = .zero
    @State private var sourceTranslation: CGPoint = .zero
    @State private var isSaving = false
    @State private var preview: CGImage?
    @State private var movingPreview: CGImage?

    private var objects: [PageObject] {
        model.selectedPageObjects.filter { object in
            guard object.pageID == page.id, PageSelectionGeometry.bounds(of: object) != nil,
                  let kind = LassoContent.kind(of: object) else { return false }
            return allowed.contains(kind)
        }
    }
    private var selected: [PageObject] { objects.filter { selectedIDs.contains($0.id) } }
    private var previewKey: String { "\(page.id.rawValue):\(page.revision):\(selectedIDs.map(\.rawValue).sorted().joined(separator: ","))" }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                touchSurface
                    .accessibilityLabel(L10n.inkLasso)
                    .accessibilityValue(L10n.selectionCount(selected.count))
                    .accessibilityIdentifier("page-selection-canvas")
                    .accessibilityAction(named: L10n.selectAll) { selectAll() }
                    .accessibilityAction(named: L10n.deselectAll) { clearSelection() }
                if !hiddenIDs.isEmpty, let movingPreview {
                    Image(decorative: movingPreview, scale: 1).resizable()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .offset(translation).allowsHitTesting(false)
                }
                Canvas { context, _ in
                    if selectionContour == nil {
                        for object in selected {
                            guard let bounds = PageSelectionGeometry.bounds(of: object) else { continue }
                            let rect = bounds.applying(sourceToView).offsetBy(dx: translation.width, dy: translation.height)
                            context.stroke(Path(rect), with: .color(Theme.accent.opacity(0.45)), lineWidth: 1)
                        }
                    }
                    if let bounds = PageSelectionGeometry.bounds(of: selected) {
                        let outline: Path
                        if let selectionContour {
                            let vertices = selectionContour.viewPoints(selectionBounds: bounds, sourceToView: sourceToView)
                                .map { CGPoint(x: $0.x + translation.width, y: $0.y + translation.height) }
                            outline = closedPath(vertices)
                        } else {
                            let rect = bounds.applying(sourceToView).offsetBy(dx: translation.width, dy: translation.height)
                            outline = Path(roundedRect: rect.insetBy(dx: -3, dy: -3), cornerRadius: 3)
                        }
                        context.stroke(outline, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    }
                    let outline = PageSelectionGeometry.loop(from: points, mode: mode)
                    if let first = outline.first {
                        var path = Path(); path.move(to: first)
                        for point in outline.dropFirst() { path.addLine(to: point) }
                        path.closeSubpath()
                        context.fill(path, with: .color(Theme.accent.opacity(0.07)))
                        context.stroke(path, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    }
                }
                .accessibilityChildren {
                    ForEach(objects) { object in
                        Button { selectedIDs = [object.id]; selectionContour = nil } label: {
                            Text(objectLabel(object))
                        }
                        .accessibilityValue(objectValue(object))
                        .accessibilityIdentifier(object.payload.kind == "text" ? "inline-text-object" : "selection-object-\(object.id.rawValue)")
                        .accessibilityActions {
                            if object.payload.kind == "text" || object.payload.kind == "image" {
                                Button(L10n.selectionEdit) { onOpen(object) }
                            }
                        }
                    }
                }
                .allowsHitTesting(false)
                if !selected.isEmpty, moving.isEmpty, !visible.isNull, !visible.isEmpty,
                   let bounds = PageSelectionGeometry.bounds(of: selected) {
                    let frame = InlineTextLayout.toolbarFrame(box: bounds.applying(sourceToView), visible: visible,
                                                              size: CGSize(width: 260, height: 52))
                    selectionToolbar.frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
            .clipped()
            .task(id: previewKey) {
                preview = nil
                guard !selectedIDs.isEmpty, let renderer = model.session.environment?.renderer else { return }
                let key = previewKey
                let scale = min(2, max(0.25, proxy.size.width / page.geometry.pageSize.width * displayScale))
                guard let image = try? await renderer.renderSelection(page, objectIDs: selectedIDs, pixelsPerPoint: scale),
                      !Task.isCancelled, previewKey == key else { return }
                preview = image
            }
        }
        .onChange(of: selectAllRequest) { _, _ in selectAll() }
        .onChange(of: page.id) { _, _ in reset(); clearSelection() }
        .onChange(of: page.geometry) { _, _ in reset(); clearSelection() }
        .onChange(of: mode) { _, _ in reset(); clearSelection() }
        // Narrowing what the lasso may hold lets go of anything it no longer may.
        .onChange(of: allowed) { _, _ in reset(); clearSelection() }
        .onDisappear { hiddenIDs = [] }
    }

    private func closedPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }

    private func clearSelection() {
        selectedIDs = []; selectionContour = nil
    }

    private func objectLabel(_ object: PageObject) -> String {
        switch object.payload {
        case .text: L10n.textBox
        case .image: L10n.markupImage
        case .ink, .comment: L10n.markup
        }
    }

    private func objectValue(_ object: PageObject) -> String {
        if case .text(let box) = object.payload { return box.text }
        return selectedIDs.contains(object.id) ? L10n.selectionOn : L10n.selectionOff
    }

    private var selectionToolbar: some View {
        HStack(spacing: 4) {
            Text(L10n.selectionCount(selected.count)).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                .padding(.leading, 12)
            Spacer(minLength: 0)
            if selected.count == 1, let object = selected.first {
                switch object.payload {
                case .text, .image:
                    Button { onOpen(object) } label: { Image(systemName: "pencil").frame(width: 44, height: 44) }
                        .accessibilityLabel(L10n.selectionEdit).accessibilityIdentifier("selection-edit")
                default: EmptyView()
                }
            }
            Menu {
                Button(L10n.selectAll) { selectAll() }.accessibilityIdentifier("selection-all")
                Button(L10n.inlineMoveLeft) { nudge(-10, 0) }.accessibilityIdentifier("selection-left")
                Button(L10n.inlineMoveRight) { nudge(10, 0) }.accessibilityIdentifier("selection-right")
                Button(L10n.inlineMoveUp) { nudge(0, -10) }.accessibilityIdentifier("selection-up")
                Button(L10n.inlineMoveDown) { nudge(0, 10) }.accessibilityIdentifier("selection-down")
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                .accessibilityLabel(L10n.more).accessibilityIdentifier("selection-more")
            Button { clearSelection() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .accessibilityLabel(L10n.deselectAll).accessibilityIdentifier("selection-clear")
        }
        .buttonStyle(.plain).font(.system(size: 18)).foregroundStyle(Theme.primaryText)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.separator) }
        .shadow(color: Theme.paperShadow, radius: 5, y: 3)
        .accessibilityElement(children: .contain).accessibilityIdentifier("selection-toolbar")
        .disabled(isSaving)
    }

    @ViewBuilder private var touchSurface: some View {
        #if os(iOS)
        Group {
            NotebookLassoTouchSurface(changed: changeLasso, ended: endLasso, cancelled: reset, opened: openObject)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #else
        legacyTouchSurface
        #endif
    }

    private var legacyTouchSurface: some View {
        Color.clear.contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { changeLasso($0.startLocation, $0.location, $0.translation) }
                .onEnded { endLasso($0.location, $0.translation) })
            .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { openObject($0.location) })
    }

    private func openObject(_ point: CGPoint) {
        guard !isSaving, let object = PageSelectionGeometry.hit(at: point, objects: objects, sourceToView: sourceToView) else { return }
        switch object.payload { case .text, .image: onOpen(object); default: break }
    }

    private func changeLasso(_ start: CGPoint, _ location: CGPoint, _ translation: CGSize) {
        guard !isSaving else { return }
        if points.isEmpty && moving.isEmpty {
            if startsOnSelection(start) {
                moving = selected; movePage = page
                movingPreview = preview
            } else { points = [start] }
        }
        if !moving.isEmpty { setTranslation(translation) }
        else if points.last.map({ hypot($0.x - location.x, $0.y - location.y) > 1 }) ?? true {
            points.append(location)
        }
    }

    private func endLasso(_ location: CGPoint, _ delta: CGSize) {
        guard !isSaving else { return }
        if !moving.isEmpty {
            setTranslation(delta)
            if abs(translation.width) > 1 || abs(translation.height) > 1 { commitMove() }
            else { reset() }
        } else {
            points.append(location)
            let result = PageSelectionGeometry.selection(from: points, mode: mode, objects: objects, sourceToView: sourceToView)
            selectedIDs = Set(result.map(\.id))
            if mode == .freehand, points.count >= 3, let first = points.first,
               points.contains(where: { hypot($0.x - first.x, $0.y - first.y) > 3 }),
               let bounds = PageSelectionGeometry.bounds(of: result) {
                selectionContour = PageSelectionContour(viewPoints: points, selectionBounds: bounds, sourceToView: sourceToView)
            } else { selectionContour = nil }
            points = []
        }
    }


    private func startsOnSelection(_ point: CGPoint) -> Bool {
        guard let bounds = PageSelectionGeometry.bounds(of: selected) else { return false }
        if let selectionContour {
            return selectionContour.contains(point, selectionBounds: bounds, sourceToView: sourceToView)
        }
        return bounds.applying(sourceToView).insetBy(dx: -6, dy: -6).contains(point)
    }

    private func selectAll() {
        guard !isSaving else { return }
        selectedIDs = Set(objects.filter { PageSelectionGeometry.bounds(of: $0)?.intersects(page.geometry.cropRect) ?? false }.map(\.id))
        selectionContour = nil
    }

    private func setTranslation(_ value: CGSize) {
        guard let bounds = PageSelectionGeometry.bounds(of: moving), let movePage else { return }
        sourceTranslation = PageSelectionGeometry.dragTranslation(of: bounds, by: value,
            sourceToView: sourceToView, crop: movePage.geometry.cropRect)
        translation = PageSelectionGeometry.viewDelta(sourceTranslation, sourceToView: sourceToView)
        hiddenIDs = movingPreview != nil && translation != .zero ? Set(moving.map(\.id)) : []
    }

    private func nudge(_ x: CGFloat, _ y: CGFloat) {
        guard !isSaving else { return }
        moving = selected; movePage = page
        movingPreview = preview
        setTranslation(CGSize(width: x, height: y)); commitMove()
    }

    private func commitMove() {
        guard let snapshot = movePage else { reset(); return }
        let expected = moving, delta = sourceTranslation
        isSaving = true
        Task {
            do { try await model.moveSelection(expected, on: snapshot, by: delta, undoManager: undoManager) }
            catch StoreError.pageObjectsChanged {
                model.presentedError = PresentedError(title: L10n.genericErrorTitle, message: L10n.markupChanged)
            } catch { model.presentedError = .saveFailed() }
            reset(); isSaving = false
        }
    }

    private func reset() {
        points = []; moving = []; movingPreview = nil; movePage = nil; translation = .zero; sourceTranslation = .zero; hiddenIDs = []
    }
}

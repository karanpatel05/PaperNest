import PaperNestCore
import PaperNestRender
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Selecting the words on the page being read, and what can be done with
/// them: copy, highlight, underline, strike through.
///
/// A pointer drags across the words. A finger presses and holds on one, then
/// drags on — a plain drag has to stay a scroll. It sits under the layers
/// that move text boxes and pictures, so those keep their own touches, and it
/// is not there at all while a drawing tool is armed.
struct TextSelectionOverlay: View {
    let selection: PageTextSelectionModel
    let model: DocumentModel
    let page: Page
    /// Source space to this view's space, as every layer over the page gets.
    let sourceToView: CGAffineTransform
    var undoManager: UndoManager?
    /// False while something else has the keyboard — the find field — so
    /// that ⌘C there copies what is selected there.
    var claimsCopyShortcut = true

    @Environment(LibrarySession.self) private var session
    @State private var barSize = CGSize(width: 260, height: 44)
    @State private var didCopy = false
    #if os(macOS)
    @State private var isSelecting = false
    #endif

    private struct Stamp: Hashable {
        let id: PageID
        let revision: Int
        let content: PageContent
    }

    var body: some View {
        GeometryReader { proxy in
            let boxes = selection.pageID == page.id ? selection.boxes.map(viewRect) : []
            ZStack(alignment: .topLeading) {
                catcher(in: proxy.size)
                ForEach(Array(boxes.enumerated()), id: \.offset) { _, rect in
                    Rectangle().fill(Theme.accent.opacity(0.28))
                        .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                        .offset(x: rect.minX, y: rect.minY)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if selection.pageID == page.id, !selection.layout.isEmpty {
                    // What is selected, said out loud, with a way to select
                    // without a gesture.
                    Color.clear.frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel(L10n.textSelection)
                        .accessibilityValue(selection.text)
                        .accessibilityAction(named: L10n.selectAll) { selection.selectAll() }
                        .accessibilityIdentifier("text-selection")
                }
                if !boxes.isEmpty, !selection.isDragging {
                    actions
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { barSize = $0 }
                        .position(barCentre(over: boxes, in: proxy.size))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .task(id: Stamp(id: page.id, revision: page.revision, content: page.content)) { await load() }
        .onDisappear { selection.clear() }
    }

    private func load() async {
        guard let renderer = session.environment?.renderer,
              let layout = try? await renderer.textLayout(for: page), !Task.isCancelled else { return }
        selection.show(layout, on: page.id)
    }

    // MARK: - Touches

    #if os(macOS)
    private func catcher(in size: CGSize) -> some View {
        Color.clear.contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 3)
                .onChanged { value in
                    // From the margin, too: the nearest letter is where a
                    // drag that started beside a line means to start.
                    if !isSelecting {
                        isSelecting = selection.begin(at: unit(value.startLocation), grain: .character,
                                                      reach: .infinity)
                    }
                    if isSelecting { selection.extend(to: unit(value.location)) }
                }
                .onEnded { _ in
                    isSelecting = false
                    selection.end()
                })
            .simultaneousGesture(SpatialTapGesture(count: 2)
                .onEnded { value in selection.selectWord(at: unit(value.location), reach: reach(in: size)) }
                .exclusively(before: SpatialTapGesture(count: 1).onEnded { _ in selection.clear() }))
    }
    #else
    @ViewBuilder
    private func catcher(in size: CGSize) -> some View {
        TextSelectionPress(
            shouldBegin: { point in
                !isOverAMark(point) && selection.layout.fragmentIndex(nearest: unit(point), within: reach(in: size)) != nil
            },
            began: { point in selection.begin(at: unit(point), grain: .word, reach: reach(in: size)) },
            moved: { point in selection.extend(to: unit(point)) },
            ended: { selection.end() })
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        if selection.hasSelection {
            // A tap anywhere else lets go of the selection.
            Color.clear.contentShape(Rectangle())
                .onTapGesture { selection.clear() }
                .accessibilityHidden(true)
        }
    }

    /// A press on a text box or a picture is for that, not for the words
    /// under it.
    private func isOverAMark(_ point: CGPoint) -> Bool {
        let source = point.applying(sourceToView.inverted())
        return model.selectedPageObjects.contains { object in
            guard object.pageID == page.id else { return false }
            switch object.payload {
            case .text(let box): return box.frame.contains(source)
            case .image(let image): return image.frame.contains(source)
            case .ink, .comment: return false
            }
        }
    }
    #endif

    /// A point in this view, as a fraction of the upright source.
    private func unit(_ point: CGPoint) -> CGPoint {
        let source = point.applying(sourceToView.inverted())
        return CGPoint(x: source.x / max(page.sourceSize.width, 1), y: source.y / max(page.sourceSize.height, 1))
    }

    private func viewRect(_ box: NormalizedRect) -> CGRect {
        box.denormalized(in: page.sourceSize).applying(sourceToView)
    }

    /// How near text a press has to land: about a fingertip, whatever the zoom.
    private func reach(in size: CGSize) -> Double {
        28 / Double(max(min(size.width, size.height), 1))
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 2) {
            Button { copy() } label: {
                Label(didCopy ? L10n.textCopied : L10n.exportCopy, systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 8).frame(minHeight: 36).contentShape(Rectangle())
            }
            .keyboardShortcut(claimsCopyShortcut ? KeyboardShortcut("c", modifiers: .command) : nil)
            .accessibilityIdentifier("text-selection-copy")
            Divider().frame(height: 22)
            markButton(.highlight, symbol: "highlighter", name: L10n.annotationHighlight)
            markButton(.underline, symbol: "underline", name: L10n.annotationUnderline)
            markButton(.strikethrough, symbol: "strikethrough", name: L10n.annotationStrikethrough)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(EditorChrome.navy)
        .buttonStyle(.plain)
        .padding(.horizontal, 6).padding(.vertical, 4)
        .editorFloatingSurface(radius: 14)
        .fixedSize()
    }

    private func markButton(_ style: TextMarkupStyle, symbol: String, name: String) -> some View {
        Button { mark(style) } label: {
            Label(name, systemImage: symbol).labelStyle(.iconOnly)
                .frame(width: 40, height: 36).contentShape(Rectangle())
        }
        .help(name)
        .accessibilityIdentifier("text-selection-\(style.rawValue)")
    }

    private func copy() {
        Clipboard.write(text: selection.text)
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            didCopy = false
        }
    }

    private func mark(_ style: TextMarkupStyle) {
        let boxes = selection.boxes
        selection.clear()
        Task { await model.markText(on: page, boxes: boxes, style: style, undoManager: undoManager) }
    }

    /// Above the first line of the selection; below its last when there is
    /// no room above. Kept inside the page either way.
    private func barCentre(over boxes: [CGRect], in size: CGSize) -> CGPoint {
        let first = boxes[0], last = boxes[boxes.count - 1]
        let halfWidth = barSize.width / 2 + 6, halfHeight = barSize.height / 2
        let x = min(max(first.midX, halfWidth), max(size.width - halfWidth, halfWidth))
        let above = first.minY - halfHeight - 8
        let y = above - halfHeight >= 0 ? above : min(last.maxY + halfHeight + 8, max(size.height - halfHeight, halfHeight))
        return CGPoint(x: x, y: y)
    }
}

extension DocumentModel {
    /// Marks `boxes` of `page` — one per line of a text selection — as
    /// editable ink, the form every highlight on a page already takes, so it
    /// can be recoloured, removed, undone and exported like the rest.
    func markText(on page: Page, boxes: [NormalizedRect], style: TextMarkupStyle,
                  undoManager: UndoManager?) async {
        // The same gate as marking up recognised lines: it is the same tool.
        guard SubscriptionStore.shared.allows(.markup) else {
            proPaywall = .markup
            return
        }
        guard let store = session.environment?.store else { return }
        do {
            var lastKey = try await store.objects(on: page.id).last?.zKey
            var marks: [PageObject] = []
            for box in boxes {
                // A character can sit a hair outside the page; the mark may not.
                let minX = min(max(box.x, 0), 1), minY = min(max(box.y, 0), 1)
                let maxX = min(max(box.x + box.width, 0), 1), maxY = min(max(box.y + box.height, 0), 1)
                guard maxX > minX, maxY > minY else { continue }
                let line = RecognizedLine(text: "", box: .exact(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
                                          confidence: 1)
                let key = try SortKey.between(lastKey, nil)
                lastKey = key
                marks.append(PageObject(pageID: page.id, zKey: key,
                                        payload: .ink(try style.stroke(for: line, in: page.sourceSize)),
                                        modifiedAt: Date()))
            }
            await changeInk(on: page.id, saving: marks, deleting: [], undoManager: undoManager)
        } catch {
            presentedError = .saveFailed()
        }
    }
}

#if os(iOS)
/// A press-and-hold on the page, reported in the page's own coordinates.
///
/// UIKit rather than a SwiftUI gesture: the page is inside a scroll view, and
/// a recognizer added to that scroll view lets a plain drag stay a scroll —
/// the press fails the moment the finger moves — where a SwiftUI long-press
/// on scrolling content can take the scroll with it. The same arrangement the
/// pinch already uses (`PagePinchZoom`).
struct TextSelectionPress: UIViewRepresentable {
    var shouldBegin: (CGPoint) -> Bool
    var began: (CGPoint) -> Bool
    var moved: (CGPoint) -> Void
    var ended: () -> Void

    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) { view.handlers = self }
    static func dismantleUIView(_ view: Probe, coordinator: ()) { view.detach() }

    final class Probe: UIView, UIGestureRecognizerDelegate {
        var handlers: TextSelectionPress?
        private weak var scroll: UIScrollView?
        private lazy var press = UILongPressGestureRecognizer(target: self, action: #selector(pressed))

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { detach() } else { DispatchQueue.main.async { [weak self] in self?.attach() } }
        }

        private func attach() {
            var ancestor = superview
            while let view = ancestor {
                if let found = view as? UIScrollView {
                    guard scroll !== found else { return }
                    detach()
                    scroll = found
                    press.minimumPressDuration = 0.4
                    press.delegate = self
                    found.addGestureRecognizer(press)
                    return
                }
                ancestor = view.superview
            }
        }

        func detach() {
            scroll?.removeGestureRecognizer(press)
            scroll = nil
        }

        @objc private func pressed() {
            let point = press.location(in: self)
            switch press.state {
            case .began:
                if handlers?.began(point) != true {
                    // Nothing to select here after all: give the touch back.
                    press.isEnabled = false
                    press.isEnabled = true
                }
            case .changed:
                handlers?.moved(point)
            case .ended, .cancelled, .failed:
                handlers?.ended()
            default:
                break
            }
        }

        override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard recognizer === press else { return super.gestureRecognizerShouldBegin(recognizer) }
            let point = press.location(in: self)
            return bounds.contains(point) && (handlers?.shouldBegin(point) ?? false)
        }
    }
}
#endif

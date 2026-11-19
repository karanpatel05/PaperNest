#if os(iOS)
import SwiftUI
import PaperNestCore

/// Which page a presentation starts on: the one being read.
struct PresentationRequest: Identifiable {
    let id = UUID()
    let start: Int
}

/// A document full screen, one page at a time, on black (roadmap:
/// presentation mode; `docs/FEATURE_UI_SAMPLES.md` §13). A tap shows or
/// hides the controls — Exit and a ⋯ menu above, ‹ and › below with the
/// page indicator. Pages turn by swiping, by ‹ ›, by the arrow keys, space
/// and Page Up/Down on a keyboard, and by VoiceOver's adjustable action;
/// Exit and VoiceOver's escape end it. The screen does not sleep while it
/// runs.
///
/// The laser pointer, from the ⋯ menu, draws a red dot with a fading tail
/// where the finger goes; while it is on, swipes point instead of turning
/// pages. It marks nothing: it is never ink and never saved. Each page is
/// drawn as Print draws it (`PageImageView`: ink, typed text and pictures;
/// private comments never). Only the page shown is drawn, with the next one
/// prepared, so a long PDF does not draw every page.
struct PresentationView: View {
    let pages: [Page]
    /// Called with the last page shown, as the presentation closes.
    let finished: (Int) -> Void

    @State private var deck: PresentationDeck
    @State private var showsControls = false
    @State private var laserOn = false
    @State private var trail = LaserTrail()
    @State private var fade: Task<Void, Never>?
    @State private var idleTimerWasDisabled = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    init(pages: [Page], start: Int, finished: @escaping (Int) -> Void) {
        self.pages = pages
        self.finished = finished
        _deck = State(initialValue: PresentationDeck(pageCount: pages.count, startingAt: start))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Taps and swipes belong to the backdrop and the page only: over
                // the controls too, they caught the ⋯ menu's tap and it never opened.
                ZStack {
                    Color.black.ignoresSafeArea()
                    // The keyboard, read by a UIKit view that takes the first
                    // responder: SwiftUI's focus reached the presentation on iPad
                    // in only some test runs, and then no key turned a page.
                    KeyCatcher(forward: forward, back: back, exit: { dismiss() })
                        .accessibilityHidden(true)
                    if pages.indices.contains(deck.index) { stage(in: proxy.size) }
                }
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showsControls.toggle() } }
                .simultaneousGesture(pointer(in: proxy.size))
                if showsControls { controls }
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .accessibilityAction(.escape) { dismiss() }
        .onAppear {
            // A presentation must not let the screen sleep.
            idleTimerWasDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = idleTimerWasDisabled
            fade?.cancel()
            finished(deck.index)
        }
    }

    // MARK: The page

    private func stage(in size: CGSize) -> some View {
        let page = pages[deck.index]
        let fitted = Self.fitted(page.geometry.pageSize, in: size)
        return ZStack {
            PageImageView(page: page, pixelSize: max(fitted.width, fitted.height) * displayScale)
                .frame(width: fitted.width, height: fitted.height)
                .id(page.id)
            if laserOn { LaserTrailView(trail: trail).frame(width: fitted.width, height: fitted.height) }
            if deck.canGoForward {
                // The next page drawn ahead, at the size it will be shown, so turning to it is immediate.
                let next = pages[deck.index + 1]
                let nextFitted = Self.fitted(next.geometry.pageSize, in: size)
                PageImageView(page: next, pixelSize: max(nextFitted.width, nextFitted.height) * displayScale)
                    .frame(width: 1, height: 1).opacity(0).accessibilityHidden(true).allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.pageLabel(deck.index + 1, of: pages.count))
        .accessibilityValue(String(deck.index + 1))
        .accessibilityIdentifier("presentation.page")
        .accessibilityAdjustableAction { direction in
            if direction == .increment { forward() } else if direction == .decrement { back() }
        }
    }

    /// `pageSize` scaled to fit `room`, keeping its shape.
    static func fitted(_ pageSize: CGSize, in room: CGSize) -> CGSize {
        guard pageSize.width > 0, pageSize.height > 0, room.width > 0, room.height > 0 else { return .zero }
        let scale = min(room.width / pageSize.width, room.height / pageSize.height)
        return CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
    }

    // MARK: Turning pages and pointing

    private func forward() {
        if deck.forward() { trail.clear() }
    }

    private func back() {
        if deck.back() { trail.clear() }
    }

    /// With the laser off, a swipe turns the page; with it on, the finger
    /// points, in shares of the page shown.
    private func pointer(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: laserOn ? 0 : 24)
            .onChanged { value in
                guard laserOn, pages.indices.contains(deck.index) else { return }
                let fitted = Self.fitted(pages[deck.index].geometry.pageSize, in: size)
                guard fitted.width > 0, fitted.height > 0 else { return }
                let origin = CGPoint(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2)
                let share = CGPoint(x: (value.location.x - origin.x) / fitted.width,
                                    y: (value.location.y - origin.y) / fitted.height)
                guard (0...1).contains(share.x), (0...1).contains(share.y) else { return }
                fade?.cancel()
                trail.add(share, at: Date().timeIntervalSinceReferenceDate)
            }
            .onEnded { value in
                if laserOn {
                    // Once the tail has faded, clear it, so its redrawing stops.
                    fade?.cancel()
                    fade = Task {
                        try? await Task.sleep(for: .seconds(LaserTrail.lifetime + 0.05))
                        if !Task.isCancelled { trail.clear() }
                    }
                    return
                }
                let across = value.translation.width, down = value.translation.height
                guard abs(across) > 60, abs(across) > abs(down) else { return }
                if across < 0 { forward() } else { back() }
            }
    }

    // MARK: Controls

    private var controls: some View {
        VStack {
            HStack(spacing: 12) {
                Spacer()
                Button(L10n.presentationExit) { dismiss() }
                    .buttonStyle(.borderedProminent).tint(Color.white.opacity(0.25))
                    .accessibilityIdentifier("presentation.exit")
                Menu {
                    Toggle(isOn: $laserOn) { Label(L10n.presentationLaser, systemImage: "light.max") }
                        .accessibilityIdentifier("presentation.laser")
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title2).frame(width: 44, height: 44)
                }
                .accessibilityLabel(L10n.more)
                .accessibilityIdentifier("presentation.more")
            }
            Spacer()
            HStack {
                Button(action: back) { Image(systemName: "chevron.left").font(.title.weight(.semibold)).frame(width: 56, height: 56) }
                    .disabled(!deck.canGoBack)
                    .accessibilityLabel(L10n.pagePrevious)
                    .accessibilityIdentifier("presentation.previous")
                Spacer()
                indicator
                Spacer()
                Button(action: forward) { Image(systemName: "chevron.right").font(.title.weight(.semibold)).frame(width: 56, height: 56) }
                    .disabled(!deck.canGoForward)
                    .accessibilityLabel(L10n.pageNext)
                    .accessibilityIdentifier("presentation.next")
            }
        }
        .padding()
        .foregroundStyle(.white)
        .background {
            VStack {
                LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom).frame(height: 120)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom).frame(height: 140)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .transition(.opacity)
    }

    /// Dots for a short document, as in the sample; a count for a long one.
    @ViewBuilder private var indicator: some View {
        Group {
            if pages.count <= 12 {
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Circle().fill(index == deck.index ? Color.white : Color.white.opacity(0.35)).frame(width: 8, height: 8)
                    }
                }
            } else {
                Text(verbatim: "\(deck.index + 1) / \(pages.count)").font(.headline.monospacedDigit())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.pageLabel(deck.index + 1, of: pages.count))
        .accessibilityIdentifier("presentation.indicator")
    }
}

/// The keyboard for a presentation: the arrows, space and Page Up/Down turn
/// pages. Escape is asked to end it, but in the Simulator tests the press
/// never arrived (2026-11-19). No modifiers, so nothing clashes with the
/// system's shortcuts. A UIKit view that becomes the first responder as it appears —
/// taking it from the document's drawing canvas behind, which kept it on iPad
/// — and reads the presses itself.
private struct KeyCatcher: UIViewRepresentable {
    let forward: () -> Void
    let back: () -> Void
    let exit: () -> Void

    func makeUIView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: KeyCatcherView, context: Context) {
        view.forward = forward
        view.back = back
        view.exit = exit
    }
}

final class KeyCatcherView: UIView {
    var forward: () -> Void = {}
    var back: () -> Void = {}
    var exit: () -> Void = {}

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        // Once now and once the presentation has settled: as it opens,
        // the canvas behind can take the first responder back.
        DispatchQueue.main.async { [weak self] in _ = self?.becomeFirstResponder() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.window != nil, !self.isFirstResponder else { return }
            _ = self.becomeFirstResponder()
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let key = press.key, key.modifierFlags.intersection([.command, .control, .alternate]).isEmpty else { continue }
            switch key.keyCode {
            case .keyboardRightArrow, .keyboardDownArrow, .keyboardSpacebar, .keyboardPageDown: forward(); handled = true
            case .keyboardLeftArrow, .keyboardUpArrow, .keyboardPageUp: back(); handled = true
            case .keyboardEscape: exit(); handled = true
            default: break
            }
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }
}

/// The laser pointer's dot and fading tail, redrawn only while some of it shows.
private struct LaserTrailView: View {
    let trail: LaserTrail

    var body: some View {
        TimelineView(.animation(paused: trail.points.isEmpty)) { context in
            Canvas { canvas, size in
                let now = context.date.timeIntervalSinceReferenceDate
                for point in trail.visible(at: now) {
                    let centre = CGPoint(x: point.location.x * size.width, y: point.location.y * size.height)
                    let radius = 4 + 5 * point.opacity
                    let dot = CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
                    canvas.fill(Path(ellipseIn: dot.insetBy(dx: -4, dy: -4)), with: .color(.red.opacity(0.25 * point.opacity)))
                    canvas.fill(Path(ellipseIn: dot), with: .color(.red.opacity(point.opacity)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif

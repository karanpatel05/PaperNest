import Foundation

/// Decide before a drawing gesture begins. A Pencil never waits for a second
/// finger, and a two-finger contact cannot later turn into a stroke when lifted.
struct NotebookTouchIntent {
    enum Decision { case undecided, drawing, navigation }
    private(set) var decision = Decision.undecided
    mutating func observe(fingers: Int, pencil: Bool, moved: Bool) {
        guard decision == .undecided else { return }
        if pencil { decision = .drawing }
        else if fingers >= 2 { decision = .navigation }
        else if moved { decision = .drawing }
    }
}

#if os(iOS)
import SwiftUI
import UIKit

/// Configures only the notebook's outer scroll view, leaving the native scroll
/// physics, pinch zoom, accessibility scrolling and interruption handling intact.
struct NotebookTouchScrolling: UIViewRepresentable {
    let requiresTwoFingers: Bool
    func makeUIView(context: Context) -> Probe { let v = Probe(); v.isUserInteractionEnabled = false; return v }
    func updateUIView(_ view: Probe, context: Context) { view.requiresTwoFingers = requiresTwoFingers; view.configure() }
    static func dismantleUIView(_ view: Probe, coordinator: ()) { view.detach() }
    final class Probe: UIView {
        var requiresTwoFingers = false
        private weak var scroll: UIScrollView?
        private var originalMinimum = 1
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { detach() }
            else { DispatchQueue.main.async { [weak self] in self?.attach() } }
        }
        private func attach() {
            var ancestor = superview
            while let view = ancestor {
                if let found = view as? UIScrollView {
                    if found !== scroll {
                        detach(); scroll = found
                        originalMinimum = found.panGestureRecognizer.minimumNumberOfTouches
                    }
                    configure(); return
                }
                ancestor = view.superview
            }
        }
        func configure() {
            scroll?.panGestureRecognizer.minimumNumberOfTouches = requiresTwoFingers ? 2 : originalMinimum
        }
        func detach() { scroll?.panGestureRecognizer.minimumNumberOfTouches = originalMinimum; scroll = nil }
    }
}

/// PencilKit waits only until the first movement distinguishes one finger from
/// two. Two contacts reserve scrolling before PencilKit can commit an ink mark.
final class NotebookInkNavigationGuard: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private var intent = NotebookTouchIntent()
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delegate = self
        cancelsTouchesInView = true
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { decide(event, moved: false) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { decide(event, moved: true) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        state = state == .began || state == .changed ? .ended : .failed
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .cancelled }
    override func reset() { super.reset(); intent = NotebookTouchIntent() }
    private func decide(_ event: UIEvent, moved: Bool) {
        guard state == .possible else { return }
        let touches = event.touches(for: self) ?? []
        intent.observe(fingers: touches.filter { $0.type == .direct }.count,
                       pencil: touches.contains { $0.type == .pencil }, moved: moved)
        switch intent.decision {
        case .undecided: break
        case .drawing: state = .failed
        case .navigation: state = .began
        }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        if other is UIPinchGestureRecognizer { return true }
        guard let scroll = other.view as? UIScrollView else { return false }
        return other === scroll.panGestureRecognizer
    }
}

/// UIKit's maximum touch count governs recognition; explicitly cancel an
/// already-running lasso as well when a second finger joins the gesture.
final class NotebookLassoPan: UIPanGestureRecognizer {
    private(set) var origin: CGPoint?
    override func reset() { super.reset(); origin = nil }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if origin == nil, let touch = touches.first, let view { origin = touch.location(in: view) }
        super.touchesBegan(touches, with: event)
        cancelForMultipleContacts(event)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        cancelForMultipleContacts(event)
        guard state != .cancelled && state != .failed else { return }
        super.touchesMoved(touches, with: event)
    }
    private func cancelForMultipleContacts(_ event: UIEvent) {
        let active = (event.touches(for: self) ?? []).filter { $0.phase != .ended && $0.phase != .cancelled }
        guard active.count > 1 else { return }
        if state == .began || state == .changed { state = .cancelled }
        else if state == .possible { state = .failed }
    }
}

/// A native one-contact lasso yields cleanly to the outer two-finger scroll.
struct NotebookLassoTouchSurface: UIViewRepresentable {
    let changed: (CGPoint, CGPoint, CGSize) -> Void
    let ended: (CGPoint, CGSize) -> Void
    let cancelled: () -> Void
    let opened: (CGPoint) -> Void
    func makeUIView(context: Context) -> Surface { Surface() }
    func updateUIView(_ view: Surface, context: Context) {
        view.changed = changed; view.ended = ended; view.cancelled = cancelled; view.opened = opened
    }
    final class Surface: UIView, UIGestureRecognizerDelegate {
        var changed: ((CGPoint, CGPoint, CGSize) -> Void)?
        var ended: ((CGPoint, CGSize) -> Void)?
        var cancelled: (() -> Void)?
        var opened: ((CGPoint) -> Void)?
        let pan = NotebookLassoPan()
        override init(frame: CGRect) {
            super.init(frame: frame)
            isOpaque = false; backgroundColor = .clear
            pan.minimumNumberOfTouches = 1; pan.maximumNumberOfTouches = 1
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue), NSNumber(value: UITouch.TouchType.pencil.rawValue)]
            pan.delegate = self; pan.addTarget(self, action: #selector(dragged)); addGestureRecognizer(pan)
            let single = UITapGestureRecognizer(target: self, action: #selector(tapped))
            let double = UITapGestureRecognizer(target: self, action: #selector(doubleTapped))
            double.numberOfTapsRequired = 2
            single.require(toFail: double)
            addGestureRecognizer(single); addGestureRecognizer(double)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        @objc private func dragged() {
            let location = pan.location(in: self)
            let origin = pan.origin ?? location
            let translation = CGSize(width: location.x - origin.x, height: location.y - origin.y)
            switch pan.state {
            case .began, .changed:
                changed?(origin, location, translation)
            case .ended: ended?(location, translation)
            case .cancelled, .failed: cancelled?()
            default: break
            }
        }
        @objc private func tapped(_ tap: UITapGestureRecognizer) {
            let point = tap.location(in: self); changed?(point, point, .zero); ended?(point, .zero)
        }
        @objc private func doubleTapped(_ tap: UITapGestureRecognizer) { opened?(tap.location(in: self)) }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            guard let scroll = other.view as? UIScrollView else { return false }
            return other === scroll.panGestureRecognizer
        }
    }
}
#endif

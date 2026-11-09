import SwiftUI

/// A deliberate downward scroll can append once. Layout, momentum and repeated
/// bottom notifications never arm a new request; the next gesture must begin.
struct NotebookAppendGate {
    private var travel: CGFloat = 0
    private var fired = true

    mutating func begin() { travel = 0; fired = false }
    mutating func update(downward: CGFloat, offset: CGFloat, maximum: CGFloat, enabled: Bool) -> Bool {
        guard enabled else { fired = true; return false }
        guard !fired else { return false }
        travel += max(0, downward)
        guard travel >= 56, maximum >= 80, offset >= maximum - 8 else { return false }
        fired = true
        return true
    }
}

#if os(iOS)
import UIKit

struct NotebookScrollAppendObserver: UIViewRepresentable {
    let enabled: Bool
    let append: () -> Void
    func makeUIView(context: Context) -> ScrollProbe {
        let view = ScrollProbe(); view.isUserInteractionEnabled = false; return view
    }
    func updateUIView(_ view: ScrollProbe, context: Context) { view.enabled = enabled; view.append = append }
    static func dismantleUIView(_ view: ScrollProbe, coordinator: ()) { view.detach() }

    final class ScrollProbe: UIView {
        var enabled = false
        var append: (() -> Void)?
        private weak var scroll: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var gate = NotebookAppendGate()
        private var previous: CGFloat = 0
        private var tracking = false
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { detach() }
            else { DispatchQueue.main.async { [weak self] in self?.attach() } }
        }
        private func attach() {
            var ancestor = superview
            while let view = ancestor {
                if let found = view as? UIScrollView {
                    guard scroll !== found else { return }
                    detach(); scroll = found
                    found.panGestureRecognizer.addTarget(self, action: #selector(panChanged))
                    observation = found.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                        MainActor.assumeIsolated { self?.sample() }
                    }
                    return
                }
                ancestor = view.superview
            }
        }
        func detach() {
            scroll?.panGestureRecognizer.removeTarget(self, action: #selector(panChanged))
            observation?.invalidate(); observation = nil; scroll = nil; tracking = false
        }
        @objc private func panChanged() {
            guard let scroll else { return }
            switch scroll.panGestureRecognizer.state {
            case .began:
                gate.begin(); previous = scroll.contentOffset.y; tracking = true
            case .changed: sample()
            default: tracking = false
            }
        }
        private func sample() {
            guard let scroll, tracking, scroll.isDragging else { return }
            let y = scroll.contentOffset.y + scroll.adjustedContentInset.top
            let delta = scroll.contentOffset.y - previous
            previous = scroll.contentOffset.y
            let maximum = scroll.contentSize.height + scroll.adjustedContentInset.top + scroll.adjustedContentInset.bottom - scroll.bounds.height
            if gate.update(downward: delta, offset: y, maximum: maximum, enabled: enabled) { append?() }
        }
    }
}
#elseif os(macOS)
import AppKit

struct NotebookScrollAppendObserver: NSViewRepresentable {
    let enabled: Bool
    let append: () -> Void
    func makeNSView(context: Context) -> ScrollProbe { ScrollProbe() }
    func updateNSView(_ view: ScrollProbe, context: Context) { view.enabled = enabled; view.append = append }
    static func dismantleNSView(_ view: ScrollProbe, coordinator: ()) { view.detach() }

    final class ScrollProbe: NSView {
        var enabled = false
        var append: (() -> Void)?
        private weak var scroll: NSScrollView?
        private var monitor: Any?
        private var boundsObserver: NSObjectProtocol?
        private var gate = NotebookAppendGate()
        private var lastWheelTime: TimeInterval = 0
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { detach() }
            else { DispatchQueue.main.async { [weak self] in self?.attach() } }
        }
        private func attach() {
            guard let found = enclosingScrollView, scroll !== found else { return }
            detach(); scroll = found
            found.contentView.postsBoundsChangedNotifications = true
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: found.contentView, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, ProcessInfo.processInfo.systemUptime - self.lastWheelTime < 0.25 else { return }
                    self.sample(downward: 0)
                }
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                MainActor.assumeIsolated { self?.wheel(event) }
                return event
            }
        }
        func detach() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
            boundsObserver = nil
            monitor = nil; scroll = nil
        }
        private func wheel(_ event: NSEvent) {
            guard let scroll, event.window === scroll.window,
                  scroll.bounds.contains(scroll.convert(event.locationInWindow, from: nil)),
                  event.momentumPhase.isEmpty else { return }
            let newMouseGesture = event.phase.isEmpty && event.timestamp - lastWheelTime > 0.35
            if event.phase.contains(.began) || newMouseGesture { gate.begin() }
            lastWheelTime = event.timestamp
            let downward = -event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 10)
            // The local monitor sees the event before the native scroll view.
            DispatchQueue.main.async { [weak self] in self?.sample(downward: downward) }
        }
        private func sample(downward: CGFloat) {
            guard let scroll, let document = scroll.documentView else { return }
            let viewport = scroll.contentView.bounds
            // SwiftUI may represent safe areas as clip-view scroll limits rather
            // than NSScrollView.contentInsets. Ask AppKit for those limits.
            var lower = viewport; lower.origin.y = -1_000_000
            var upper = viewport; upper.origin.y = 1_000_000
            let minimumY = scroll.contentView.constrainBoundsRect(lower).minY
            let maximumY = scroll.contentView.constrainBoundsRect(upper).minY
            let offset = document.isFlipped ? viewport.minY - minimumY : maximumY - viewport.minY
            let maximum = maximumY - minimumY
            if gate.update(downward: downward, offset: offset, maximum: maximum, enabled: enabled) { append?() }
        }
    }
}
#endif

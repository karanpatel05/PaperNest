import SwiftUI

/// Shared limits and button stepping, including scales reached by pinching.
enum PageZoom {
    static let steps: [CGFloat] = [0.5, 0.75, 1, 1.5, 2, 3, 4]
    static func clamp(_ value: CGFloat) -> CGFloat { min(max(value, steps[0]), steps[steps.count - 1]) }
    static func step(_ value: CGFloat, direction: Int) -> CGFloat {
        if direction > 0 { return steps.first(where: { $0 > value + 0.001 }) ?? steps[steps.count - 1] }
        return steps.last(where: { $0 < value - 0.001 }) ?? steps[0]
    }
}

/// The floating bar's zoom: out, the zoom in force, in, fit.
///
/// The percentage opens display settings, where the presets are; the fit
/// button keeps the identifier and value the old one had, so anything that
/// reads the zoom from it still can.
struct ViewportZoomControls: View {
    @Binding var zoom: CGFloat
    let showSettings: () -> Void

    var body: some View {
        let percent = Double(zoom).formatted(.percent.precision(.fractionLength(0)))
        HStack(spacing: 0) {
            Button { zoom = PageZoom.step(zoom, direction: -1) } label: {
                Image(systemName: "minus").font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.zoomOut).help(L10n.zoomOut)
            .accessibilityIdentifier("editor-zoom-out")
            .keyboardShortcut("-", modifiers: .command)
            .disabled(zoom <= PageZoom.steps[0])
            Button(action: showSettings) {
                Text(verbatim: percent)
                    .font(.app(.subheadline).weight(.medium).monospacedDigit())
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 10).frame(minWidth: 58, minHeight: 32)
                    .background(EditorChrome.lavender, in: Capsule())
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.displayZoom)
            .accessibilityValue(percent)
            .accessibilityHint(L10n.displaySettings)
            .accessibilityIdentifier("editor-zoom-percent")
            Button { zoom = PageZoom.step(zoom, direction: 1) } label: {
                Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.zoomIn).help(L10n.zoomIn)
            .accessibilityIdentifier("editor-zoom-in")
            .keyboardShortcut("+", modifiers: .command)
            .disabled(zoom >= PageZoom.steps[PageZoom.steps.count - 1])
            Button { zoom = 1 } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 15, weight: .medium))
                    .frame(width: 40, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.zoomToFit).help(L10n.zoomToFit)
            .accessibilityValue(percent)
            .accessibilityIdentifier("editor-zoom-fit")
            .keyboardShortcut("0", modifiers: .command)
        }
    }
}

#if os(iOS)
import UIKit

/// Keep one native pinch recognizer on the outer page scroll view. Its baseline
/// survives SwiftUI relayout as the paper grows beneath the user's fingers.
struct PagePinchZoom: UIViewRepresentable {
    @Binding var zoom: CGFloat
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) {
        view.currentZoom = zoom
        view.changeZoom = { zoom = $0 }
    }
    static func dismantleUIView(_ view: Probe, coordinator: ()) { view.detach() }
    final class Probe: UIView, UIGestureRecognizerDelegate {
        var currentZoom: CGFloat = 1
        var changeZoom: ((CGFloat) -> Void)?
        private var baseline: CGFloat?
        private weak var scroll: UIScrollView?
        private lazy var pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched))
        override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
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
                    pinch.delegate = self
                    found.addGestureRecognizer(pinch)
                    return
                }
                ancestor = view.superview
            }
        }
        func detach() { scroll?.removeGestureRecognizer(pinch); scroll = nil; baseline = nil }
        @objc private func pinched() {
            if UserDefaults.standard.bool(forKey: "PaperNestDebugZoomTrace") { print("ZOOM TRACE", pinch.state.rawValue, pinch.scale, currentZoom, baseline as Any) }
            switch pinch.state {
            case .began: baseline = currentZoom
            case .changed, .ended:
                if let baseline { changeZoom?(PageZoom.clamp(baseline * pinch.scale)) }
                if pinch.state == .ended { baseline = nil }
            case .cancelled, .failed: baseline = nil
            default: break
            }
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if UserDefaults.standard.bool(forKey: "PaperNestDebugZoomTrace") { print("ZOOM TOUCH", touch.location(in: scroll), scroll?.bounds as Any, gestureRecognizer.state.rawValue) }
            return true
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
#endif

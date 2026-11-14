import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Files to hand to the system's share UI, once.
struct ShareRequest: Identifiable, Equatable {
    let id = UUID()
    let files: [URL]
}

/// Opens the system share UI from code, anchored to the view it is attached
/// to, and reports whether something was shared.
///
/// `ShareLink` opens only on its own tap, which comes too early when the file
/// has to be made first: that left the export sheet asking for Share twice.
/// Attach this behind the control that asked for the share, so on iPad and
/// Mac the share UI points at it.
///
/// `finished(true)` comes once a share target has the files, `finished(false)`
/// when the share UI was dismissed without one. Callers keep the files until
/// then: a target can still be reading them while its UI is up.
struct SystemSharePresenter: View {
    @Binding var request: ShareRequest?
    let finished: (Bool) -> Void

    var body: some View {
        Anchor(request: $request, finished: finished)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#if os(iOS)
private struct Anchor: UIViewRepresentable {
    @Binding var request: ShareRequest?
    let finished: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        guard let request, context.coordinator.shownID != request.id else { return }
        context.coordinator.shownID = request.id
        let finished = finished
        let clear = { self.request = nil }
        // Present after this update pass: SwiftUI is still laying out.
        DispatchQueue.main.async {
            // The window's root is already presenting the sheet this sits in,
            // so present from whatever is on top, or UIKit refuses quietly.
            guard var top = view.window?.rootViewController else {
                clear(); finished(false); return
            }
            while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
            let controller = UIActivityViewController(activityItems: request.files, applicationActivities: nil)
            // Required on iPad, where the share UI is a popover: without a
            // source UIKit raises an exception.
            controller.popoverPresentationController?.sourceView = view
            controller.popoverPresentationController?.sourceRect = view.bounds
            controller.completionWithItemsHandler = { _, completed, _, _ in
                clear()
                finished(completed)
            }
            top.present(controller, animated: true)
        }
    }

    final class Coordinator {
        var shownID: UUID?
    }
}
#else
private struct Anchor: NSViewRepresentable {
    @Binding var request: ShareRequest?
    let finished: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        guard let request, context.coordinator.shownID != request.id else { return }
        context.coordinator.shownID = request.id
        let coordinator = context.coordinator
        coordinator.finish = { shared in
            self.request = nil
            finished(shared)
        }
        DispatchQueue.main.async {
            guard view.window != nil else { coordinator.finish?(false); return }
            let picker = NSSharingServicePicker(items: request.files)
            picker.delegate = coordinator
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
    }

    /// Hears both the picker (a service chosen, or none) and the service it
    /// hands the files to (sent, or failed), so the files outlive the share.
    final class Coordinator: NSObject, NSSharingServicePickerDelegate, NSSharingServiceDelegate {
        var shownID: UUID?
        var finish: ((Bool) -> Void)?

        func sharingServicePicker(_ picker: NSSharingServicePicker, delegateFor sharingService: NSSharingService) -> NSSharingServiceDelegate? {
            self
        }

        func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
            if service == nil { done(false) }
        }

        func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
            done(true)
        }

        func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
            done(false)
        }

        private func done(_ shared: Bool) {
            let finish = finish
            self.finish = nil
            finish?(shared)
        }
    }
}
#endif

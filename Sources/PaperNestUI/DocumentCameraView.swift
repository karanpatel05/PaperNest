#if os(iOS)
import SwiftUI
import UIKit
import VisionKit

/// Wraps VisionKit's document camera, which handles edge detection,
/// perspective correction and multi-page capture. iPhone and iPad only:
/// this controller does not exist on native macOS.
///
/// Status: implemented, not yet compiled or run. The development machine
/// had no iOS SDK when this was written (see docs/TEST_MATRIX.md).
struct DocumentCameraView: UIViewControllerRepresentable {
    enum Outcome {
        /// JPEG data for each captured page, in capture order.
        case scanned([Data])
        case cancelled
        /// Includes a denied camera permission.
        case failed
    }

    let onFinish: (Outcome) -> Void

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: (Outcome) -> Void

        init(onFinish: @escaping (Outcome) -> Void) {
            self.onFinish = onFinish
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).jpegData(compressionQuality: 0.9) }
            onFinish(pages.isEmpty ? .failed : .scanned(pages))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish(.cancelled)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onFinish(.failed)
        }
    }
}
#endif

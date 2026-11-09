import Foundation

/// Capture conversion policy, independent of the camera so encoding failures
/// can be tested without requiring a physical device.
enum ScanCaptureEncoding {
    static func pages(count: Int, encode: (Int) -> Data?) -> [Data]? {
        guard count > 0 else { return nil }
        var pages: [Data] = []
        pages.reserveCapacity(count)
        for index in 0..<count {
            // A partial result would silently lose paper the user captured.
            guard let page = encode(index) else { return nil }
            pages.append(page)
        }
        return pages
    }
}

#if os(iOS)
import SwiftUI
import UIKit
import VisionKit

/// Wraps VisionKit's document camera, which handles edge detection,
/// perspective correction and multi-page capture. iPhone and iPad only:
/// this controller does not exist on native macOS.
///
/// Compiled for iOS; physical-device capture remains a verification gate.
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
        controller.view.tintColor = UIColor(Theme.accent)
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
            guard let pages = ScanCaptureEncoding.pages(count: scan.pageCount, encode: {
                scan.imageOfPage(at: $0).jpegData(compressionQuality: 0.9)
            }) else {
                onFinish(.failed)
                return
            }
            onFinish(.scanned(pages))
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

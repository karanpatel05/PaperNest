#if os(iOS)
import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A single photograph for an existing page, separate from document scanning.
struct PhotoCameraView: UIViewControllerRepresentable {
    enum Outcome {
        case captured(Data)
        case cancelled
        case failed
    }

    let onFinish: (Outcome) -> Void

    static var isSupported: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (Outcome) -> Void
        init(onFinish: @escaping (Outcome) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.9) else {
                onFinish(.failed)
                return
            }
            onFinish(.captured(data))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(.cancelled)
        }
    }
}
#endif

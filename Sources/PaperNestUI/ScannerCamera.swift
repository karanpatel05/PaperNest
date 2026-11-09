#if os(iOS)
@preconcurrency import AVFoundation
import Vision
import UIKit
import SwiftUI

/// All session mutation and frame analysis are confined to queue. Only value
/// snapshots and encoded images cross back to the main actor.
final class ScannerCamera: NSObject, @unchecked Sendable, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "PaperNest.Scanner")
    private let photos = AVCapturePhotoOutput()
    private var frames: AVCaptureVideoDataOutput?
    private var rotation: CGFloat = 90
    private var device: AVCaptureDevice?
    private var configured = false
    private var capturing = false
    private var intent = ScannerSessionIntent()
    private var automatic = false
    private var capturePolicy = ScannerCapturePolicy()
    private var frame = 0
    private var observers: [NSObjectProtocol] = []
    @MainActor var onOutline: (@MainActor @Sendable ([CGPoint]) -> Void)?
    @MainActor var onAutoCapture: (@MainActor @Sendable () -> Void)?
    @MainActor var onPhoto: (@MainActor @Sendable (Data?) -> Void)?
    @MainActor var onStatus: (@MainActor @Sendable (Bool, Bool) -> Void)?

    func start(waitForNextSheet: Bool = false) {
        queue.async { [self] in
            intent.start()
            if waitForNextSheet { capturePolicy.waitForNextSheet() }
        }
        Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            guard allowed else { await onStatus?(false, false); return }
            queue.async { [self] in
                guard intent.wantsRunning else { return }
                if !configured { configure() }
                guard configured else { report(false); return }
                if !session.isRunning { session.startRunning() }
                report(session.isRunning)
            }
        }
    }

    private func configure() {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(photos) else { return }
        session.addInput(input)
        session.addOutput(photos)
        let frames = AVCaptureVideoDataOutput()
        frames.alwaysDiscardsLateVideoFrames = true
        frames.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(frames) else {
            session.removeOutput(photos)
            session.removeInput(input)
            return
        }
        session.addOutput(frames)
        if let connection = frames.connection(with: .video), connection.isVideoRotationAngleSupported(rotation) {
            connection.videoRotationAngle = rotation
        }
        self.frames = frames
        device = camera
        configured = true
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                self?.queue.async { [weak self] in
                    self?.capturePolicy.reset()
                    if self?.capturing == true {
                        Task { @MainActor [weak self] in self?.onPhoto?(nil) }
                    }
                    self?.capturing = false
                    self?.report(false)
                }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self, self.intent.wantsRunning else { return }
                if !self.session.isRunning { self.session.startRunning() }
                self.report(self.session.isRunning)
            }
        })
    }

    private func report(_ ready: Bool) {
        let torch = device?.hasTorch == true
        Task { @MainActor [weak self] in self?.onStatus?(ready, torch) }
    }

    func stop() {
        queue.async { [self] in
            intent.stop()
            capturePolicy.reset()
            report(false)
            if session.isRunning { session.stopRunning() }
            if let device, device.hasTorch, (try? device.lockForConfiguration()) != nil {
                device.torchMode = .off
                device.unlockForConfiguration()
            }
        }
    }

    func torch(_ enabled: Bool) {
        queue.async { [self] in
            guard let device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
            device.torchMode = enabled ? .on : .off
            device.unlockForConfiguration()
        }
    }

    func setRotation(_ angle: CGFloat) {
        queue.async { [self] in
            guard rotation != angle else { return }
            rotation = angle
            capturePolicy.reset()
            if let connection = frames?.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }

    func setAutomatic(_ enabled: Bool) {
        queue.async { [self] in automatic = enabled; capturePolicy.reset() }
    }

    func capture() {
        queue.async { [self] in
            guard intent.wantsRunning, session.isRunning, !capturing else {
                Task { @MainActor [weak self] in self?.onPhoto?(nil) }
                return
            }
            capturing = true
            if let connection = photos.connection(with: .video), connection.isVideoRotationAngleSupported(rotation) {
                connection.videoRotationAngle = rotation
            }
            photos.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        queue.async { [self] in capturing = false }
        Task { @MainActor [weak self] in self?.onPhoto?(data) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frame += 1
        guard frame % 8 == 0, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 1
        request.minimumConfidence = 0.7
        request.minimumSize = 0.2
        try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
        let points = request.results?.first.map { [$0.topLeft, $0.topRight, $0.bottomRight, $0.bottomLeft].map { CGPoint(x: $0.x, y: 1 - $0.y) } } ?? []
        Task { @MainActor [weak self] in self?.onOutline?(points) }
        if automatic, intent.wantsRunning, !capturing, capturePolicy.observe(points, at: ProcessInfo.processInfo.systemUptime) {
            Task { @MainActor [weak self] in self?.onAutoCapture?() }
            capture()
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}

struct ScannerCameraPreview: UIViewRepresentable {
    let camera: ScannerCamera
    let outline: [CGPoint]
    func makeUIView(context: Context) -> Preview {
        let view = Preview()
        view.camera = camera
        view.preview.session = camera.session
        view.preview.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ view: Preview, context: Context) {
        view.points = outline
        view.setNeedsLayout()
    }
    final class Preview: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var points: [CGPoint] = []
        weak var camera: ScannerCamera?
        private let edge = CAShapeLayer()
        override init(frame: CGRect) {
            super.init(frame: frame)
            edge.strokeColor = UIColor(Theme.accent).cgColor
            edge.fillColor = UIColor(Theme.accent).withAlphaComponent(0.12).cgColor
            edge.lineWidth = 3
            layer.addSublayer(edge)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layoutSubviews() {
            super.layoutSubviews()
            let rotation: CGFloat
            switch window?.windowScene?.interfaceOrientation {
            case .landscapeLeft: rotation = 180
            case .landscapeRight: rotation = 0
            case .portraitUpsideDown: rotation = 270
            default: rotation = 90
            }
            camera?.setRotation(rotation)
            if let connection = preview.connection, connection.isVideoRotationAngleSupported(rotation) { connection.videoRotationAngle = rotation }
            // Vision points describe the rotated portrait buffer. Convert through
            // preview metadata space so aspect-fill cropping is included.
            let converted = points.map { point in
                let capture: CGPoint
                switch rotation {
                case 0: capture = point
                case 180: capture = CGPoint(x: 1 - point.x, y: 1 - point.y)
                case 270: capture = CGPoint(x: 1 - point.y, y: point.x)
                default: capture = CGPoint(x: point.y, y: 1 - point.x)
                }
                return preview.layerPointConverted(fromCaptureDevicePoint: capture)
            }
            let path = UIBezierPath()
            if let first = converted.first {
                path.move(to: first)
                converted.dropFirst().forEach { path.addLine(to: $0) }
                path.close()
            }
            edge.path = path.cgPath
        }
    }
}
#endif

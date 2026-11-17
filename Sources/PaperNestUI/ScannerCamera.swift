#if os(iOS)
@preconcurrency import AVFoundation
import Vision
import UIKit
import SwiftUI
import PaperNestCore
import PaperNestRender

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
    /// What to say about each look and when the automatic shutter fires,
    /// decided together (`ScanCaptureGuide`). Only touched on `queue`.
    private var guide = ScanCaptureGuide(detection: ScanCaptureMode.document.detection)
    /// What the mode looks for in each frame. Nil keeps the whole frame: no outline, no automatic shutter.
    private var detection: ScanDetection? = ScanCaptureMode.document.detection
    private var frame = 0
    private var observers: [NSObjectProtocol] = []
    /// Each look: the outline found and what to tell the person, in one hop
    /// so the two never arrive out of step.
    @MainActor var onObservation: (@MainActor @Sendable ([CGPoint], ScanCaptureFeedback?) -> Void)?
    @MainActor var onAutoCapture: (@MainActor @Sendable () -> Void)?
    @MainActor var onPhoto: (@MainActor @Sendable (Data?) -> Void)?
    @MainActor var onStatus: (@MainActor @Sendable (Bool, Bool) -> Void)?

    func start(waitForNextSheet: Bool = false) {
        queue.async { [self] in
            intent.start()
            if waitForNextSheet { guide.waitForNextSheet() }
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
                    self?.guide.reset()
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
            guide.reset()
            Task { @MainActor [weak self] in self?.onObservation?([], nil) }
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
            guide.reset()
            if let connection = frames?.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }

    func setAutomatic(_ enabled: Bool) {
        queue.async { [self] in automatic = enabled; guide.reset() }
    }

    /// A change of mode. What was held still under the last mode's rule says
    /// nothing under this one, so the automatic shutter starts over.
    func setDetection(_ detection: ScanDetection?) {
        queue.async { [self] in self.detection = detection; guide = ScanCaptureGuide(detection: detection) }
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
        var points: [CGPoint] = []
        if let detection {
            let request = ScanEdgeDetector.request(for: detection)
            try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
            let aspect = Double(CVPixelBufferGetWidth(buffer)) / Double(max(1, CVPixelBufferGetHeight(buffer)))
            points = ScanEdgeDetector.chosen(from: request, for: detection, imageAspect: aspect)?.corners ?? []
        }
        process(ScanFrameObservation(corners: points, luminance: ScanFrameLuminance.mean(of: buffer)),
                at: ProcessInfo.processInfo.systemUptime)
    }

    /// One look: the outline, what to say, and whether to take the picture —
    /// one decision, so the label never says Ready over a page the shutter
    /// will not take. On `queue`.
    private func process(_ look: ScanFrameObservation, at time: Double) {
        let decision = guide.observe(look, at: time, automatic: automatic && intent.wantsRunning && !capturing)
        Task { @MainActor [weak self] in self?.onObservation?(look.corners, decision.feedback) }
        if decision.fire {
            Task { @MainActor [weak self] in self?.onAutoCapture?() }
            capture()
        }
    }

    #if DEBUG
    /// For UI tests on a simulator, which has no camera: a recorded look,
    /// through exactly the processing a real frame gets.
    func debugObserve(_ look: ScanFrameObservation) {
        queue.async { [self] in process(look, at: ProcessInfo.processInfo.systemUptime) }
    }
    #endif

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

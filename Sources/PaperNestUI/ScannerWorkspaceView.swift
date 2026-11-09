#if os(iOS)
import SwiftUI
import PhotosUI

/// Capture and review only. Completion goes through the existing import-location
/// and document naming workflow; it never reports an uncommitted document saved.
struct ScannerWorkspaceView: View {
    var onName: (String) -> Void = { _ in }
    let onFinish: (DocumentCameraView.Outcome) -> Void
    @State private var camera = ScannerCamera()
    @FocusState private var naming: Bool
    @State private var name = L10n.scanName(Date().formatted(date: .abbreviated, time: .shortened))
    @State private var automatic = false
    @State private var previewImage: UIImage?
    @State private var ready = false
    @State private var hasTorch = false
    @State private var torch = false
    @State private var outline: [CGPoint] = []
    @State private var pages: [ScannerPage] = []
    @State private var selected = 0
    @State private var reviewing = false
    @State private var captureReview = ScannerCaptureReview<ScannerPage>()
    @State private var pendingPreview: UIImage?
    @State private var busy = false
    @State private var failed = false
    @State private var native = false
    @State private var cropping = false
    @State private var captureGeneration = UUID()
    @State private var completed = false
    @State private var photoPickerPresented = false
    @State private var photoItems: [PhotosPickerItem] = []
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let pending = captureReview.pending { captureDecision(pending) }
            else if reviewing { review } else { capture }
        }
        .tint(Theme.accent)
        .task {
            camera.onStatus = { available, flash in
                ready = available; hasTorch = flash
                if !available { torch = false }
            }
            camera.onAutoCapture = {
                guard captureReview.pending == nil, !native, !reviewing, !photoPickerPresented, !completed else { return }
                busy = true
            }
            camera.onOutline = { outline = $0 }
            camera.onPhoto = { data in
                guard captureReview.pending == nil, !completed, !native, !reviewing, !photoPickerPresented else { return }
                guard let data else { busy = false; failed = true; return }
                if UIDevice.current.userInterfaceIdiom == .pad { stopCamera(); torch = false }
                let generation = captureGeneration
                Task { await appendCapture(data, generation: generation) }
            }
            #if DEBUG
            if pages.isEmpty, let paths = UserDefaults.standard.string(forKey: "PaperNestDebugScannerImages") {
                pages = paths.split(separator: ";").compactMap { path in
                    guard let data = try? Data(contentsOf: URL(fileURLWithPath: String(path))), UIImage(data: data) != nil else { return nil }
                    return ScannerPage(original: data)
                }
                if UIDevice.current.userInterfaceIdiom == .pad,
                   UserDefaults.standard.bool(forKey: "PaperNestDebugScannerPendingCapture"),
                   let pending = pages.popLast() {
                    _ = captureReview.stage(pending)
                    return
                }
                reviewing = !pages.isEmpty
                if reviewing { return }
            }
            #endif
            if canRunCamera { camera.start() }
        }
        .onDisappear {
            stopCamera()
            camera.onStatus = nil
            camera.onOutline = nil
            camera.onPhoto = nil
            camera.onAutoCapture = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && canRunCamera { camera.start() }
            else { stopCamera(); torch = false }
        }
        .onChange(of: automatic) { _, value in camera.setAutomatic(value) }
        .onChange(of: reviewing) { _, value in
            if value { stopCamera(); torch = false } else if canRunCamera { camera.start() }
        }
        .photosPicker(isPresented: $photoPickerPresented, selection: $photoItems, matching: .images)
        .onChange(of: photoPickerPresented) { _, presented in
            if presented { stopCamera(); torch = false }
            else if canRunCamera && scenePhase == .active { camera.start() }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            busy = true
            Task {
                var imported: [ScannerPage] = []
                for item in items {
                    guard let data = try? await item.loadTransferable(type: Data.self), UIImage(data: data) != nil else {
                        failed = true; busy = false; photoItems = []; return
                    }
                    imported.append(ScannerPage(original: data))
                }
                pages.append(contentsOf: imported)
                selected = pages.count - imported.count
                busy = false; photoItems = []; reviewing = true
            }
        }
        .fullScreenCover(isPresented: $native, onDismiss: { if canRunCamera { camera.start() } }) {
            DocumentCameraView { outcome in
                native = false
                switch outcome {
                case .scanned(let data):
                    pages.append(contentsOf: data.map { ScannerPage(original: $0) })
                    selected = max(0, pages.count - data.count)
                    reviewing = true
                case .failed: failed = true
                case .cancelled: break
                }
            }.ignoresSafeArea()
        }
        .alert(L10n.scanFailed, isPresented: $failed) { Button(L10n.done, role: .cancel) {} }
    }

    private var canRunCamera: Bool {
        #if DEBUG
        if debugCaptureData != nil { return false }
        #endif
        return !busy && !completed && !native && !reviewing && !photoPickerPresented && captureReview.pending == nil
    }

    /// Explicit test-only captured-image injection. Production shutter always
    /// uses AVFoundation; fixture bytes exercise the same detection/review path.
    private var debugCaptureData: Data? {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "PaperNestDebugScannerPendingCapture"),
              let path = UserDefaults.standard.string(forKey: "PaperNestDebugScannerImages")?.split(separator: ";").last
        else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: String(path)))
        #else
        return nil
        #endif
    }

    /// A review is part of capture, not a saved page or a modal text dialog.
    /// The accepted queue remains untouched until the explicit Keep action.
    private func captureDecision(_ page: ScannerPage) -> some View {
        VStack(spacing: 12) {
            Text(L10n.scannerReviewCapture).font(.headline).padding(.top, 12)
            Text(L10n.scannerReviewCaptureHint).font(.subheadline)
                .foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center).padding(.horizontal)
            Group {
                if let image = pendingPreview {
                    ScannerZoomPreview(image: image, accessibilityValue: "")
                } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            .task(id: page.id) {
                pendingPreview = nil
                let data = await Task.detached(priority: .userInitiated) {
                    page.rendered(maxDimension: 1600)?.jpegData(compressionQuality: 0.85)
                }.value
                guard !Task.isCancelled, captureReview.pending?.id == page.id else { return }
                pendingPreview = data.flatMap { UIImage(data: $0) }
                if pendingPreview == nil { failed = true }
            }
        }
        .background(Theme.canvas)
        .safeAreaInset(edge: .bottom) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { captureDecisionButtons }
                VStack(spacing: 12) { captureDecisionButtons }
            }
            .padding(16).frame(maxWidth: .infinity).background(Theme.surface)
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder private var captureDecisionButtons: some View {
        Button(role: .destructive) { resolveCapture(keep: false) } label: {
            Label(L10n.delete, systemImage: "trash").frame(minWidth: 120, minHeight: 44)
        }
        .buttonStyle(.bordered).accessibilityIdentifier("scanner.capture-delete")
        Button { resolveCapture(keep: true) } label: {
            Label(L10n.scannerKeepScan, systemImage: "checkmark").frame(minWidth: 120, minHeight: 44)
        }
        .buttonStyle(.borderedProminent).disabled(pendingPreview == nil)
        .accessibilityIdentifier("scanner.capture-keep")
    }

    private func resolveCapture(keep: Bool) {
        guard captureReview.pending != nil else { return }
        captureGeneration = UUID()
        if keep, let page = captureReview.keep() {
            pages.append(page)
            selected = pages.count - 1
        } else { captureReview.discard() }
        pendingPreview = nil
        if canRunCamera && scenePhase == .active { camera.start(waitForNextSheet: keep) }
    }

    private var capture: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScannerCameraPreview(camera: camera, outline: outline).ignoresSafeArea()
            VStack {
                HStack {
                    icon("xmark", label: L10n.cancel) { completed = true; onFinish(.cancelled) }
                    Spacer()
                    Text(L10n.scan).font(.headline)
                    Button(automatic ? L10n.scannerAuto : L10n.scannerManual) { automatic.toggle() }
                        .font(.caption).buttonStyle(.bordered).disabled(busy)
                        .accessibilityIdentifier("scanner.mode")
                    Spacer()
                    if hasTorch {
                        icon(torch ? "bolt.fill" : "bolt.slash", label: L10n.scannerFlash) { torch.toggle(); camera.torch(torch) }
                            .accessibilityValue(torch ? L10n.scannerOn : L10n.scannerOff)
                    }
                    Menu {
                        if DocumentCameraView.isSupported {
                            Button(L10n.scannerNative) {
                                guard !busy else { return }
                                captureGeneration = UUID(); stopCamera(); native = true
                            }
                        }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel(L10n.more).disabled(busy)
                }
                .padding(.horizontal).background(.black.opacity(0.8))
                Spacer()
                if !ready {
                    VStack(spacing: 12) {
                        Text(L10n.scannerCameraUnavailable).multilineTextAlignment(.center)
                        Button(L10n.scannerRetry) { camera.start() }.buttonStyle(.bordered).disabled(busy)
                    }.padding().background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 16)).padding()
                }
                HStack(spacing: 32) {
                    Button { photoPickerPresented = true } label: {
                        Image(systemName: "photo").frame(width: 48, height: 48)
                    }.accessibilityLabel(L10n.importPhotos).disabled(busy)
                    Spacer(minLength: 0)
                    Button {
                        guard !busy, captureReview.pending == nil else { return }
                        busy = true
                        if let fixture = debugCaptureData {
                            let generation = captureGeneration
                            Task { await appendCapture(fixture, generation: generation) }
                        } else { camera.capture() }
                    } label: {
                        ZStack {
                            Circle().stroke(Theme.accent, lineWidth: 3).frame(width: 76, height: 76)
                            Circle().fill(.white).frame(width: 64, height: 64)
                            if busy { ProgressView().tint(.black) }
                        }
                    }
                    .disabled((!ready && debugCaptureData == nil) || busy).accessibilityLabel(L10n.takePhoto)
                    .accessibilityIdentifier("scanner.shutter")
                    Spacer(minLength: 0)
                    Button { reviewing = true } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "square.stack")
                            Text(verbatim: String(pages.count)).font(.caption.monospacedDigit())
                        }.frame(width: 48, height: 48)
                    }.disabled(pages.isEmpty || busy)
                        .accessibilityLabel(L10n.scannerReview).accessibilityValue(String(pages.count))
                        .accessibilityIdentifier("scanner.review")
                }.padding(24).background(.black.opacity(0.85), in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
            }.foregroundStyle(.white)
        }
    }

    private var review: some View {
        VStack(spacing: 12) {
            HStack {
                icon("chevron.left", label: L10n.scanPages) { guard !busy else { return }; reviewing = false }
                Spacer()
                Text(L10n.scannerEdit).font(.headline)
                Spacer()
                Button(L10n.exportSave) { finish() }.buttonStyle(.borderedProminent)
                    .disabled(pages.isEmpty || busy).accessibilityIdentifier("scanner.finish")
            }.padding(.horizontal)
            TextField(L10n.documentName, text: $name).textFieldStyle(.roundedBorder).padding(.horizontal)
                .focused($naming).submitLabel(.done).onSubmit { naming = false }
                .accessibilityIdentifier("scanner.name")
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        Button { guard !busy else { return }; selected = index } label: {
                            VStack(spacing: 4) {
                                ScannerThumbnail(page: page).frame(width: 56, height: 70)
                                Text(verbatim: String(index + 1)).font(.caption.monospacedDigit())
                            }.padding(5).background(selected == index ? Theme.accent.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected == index ? Theme.accent : Color.secondary.opacity(0.2)))
                        }.accessibilityIdentifier("scanner.page.\(index)")
                            .accessibilityLabel(L10n.scannerReview + " " + String(index + 1))
                            .accessibilityAddTraits(selected == index ? [.isSelected] : [])
                            .contextMenu {
                                Button(L10n.duplicate) { guard !busy else { return }; pages.insert(ScannerPage(original: page.original, quarterTurns: page.quarterTurns, filter: page.filter, enhanced: page.enhanced, corners: page.corners), at: index + 1); selected = index + 1 }
                                Button(L10n.scannerMoveEarlier) { guard !busy else { return }; pages.swapAt(index, index - 1); selected = index - 1 }.disabled(index == 0)
                                Button(L10n.scannerMoveLater) { guard !busy else { return }; pages.swapAt(index, index + 1); selected = index + 1 }.disabled(index == pages.count - 1)
                            }
                    }
                    icon("plus", label: L10n.scanPages) { guard !busy else { return }; reviewing = false }
                }.padding(.horizontal)
            }
            Group {
                if cropping && pages.indices.contains(selected) {
                    ScannerCornerEditor(page: Binding(
                        get: { pages[selected] },
                        set: { if !busy && pages.indices.contains(selected) { pages[selected] = $0 } }
                    ))
                } else if let image = previewImage {
                    ScannerZoomPreview(image: image,
                        accessibilityValue: "\(selected + 1); \(L10n.rotate) \(pages[selected].quarterTurns); \(L10n.filter) \(pages[selected].filter)")
                        .id(pages[selected].id)
                } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            .task(id: previewKey) {
                guard pages.indices.contains(selected), !cropping else { return }
                let page = pages[selected]
                previewImage = nil
                let data = await Task.detached(priority: .userInitiated) { page.rendered(maxDimension: 1600)?.jpegData(compressionQuality: 0.85) }.value
                guard !Task.isCancelled, !completed else { return }
                previewImage = data.flatMap { UIImage(data: $0) }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 20) {
                    reviewTool("crop", label: L10n.crop) { cropping.toggle() }
                    reviewTool("rotate.right", label: L10n.rotate) { pages[selected].quarterTurns = (pages[selected].quarterTurns + 1) % 4 }
                    Menu {
                        Button(L10n.filterOriginal) { guard !busy else { return }; pages[selected].filter = 0 }
                        Button(L10n.filterGrayscale) { guard !busy else { return }; pages[selected].filter = 1 }
                        Button(L10n.filterBlackAndWhite) { guard !busy else { return }; pages[selected].filter = 2 }
                    } label: { VStack(spacing: 4) { Image(systemName: "camera.filters"); Text(L10n.filter).font(.caption) }.frame(minWidth: 44, minHeight: 44) }
                    reviewTool("sparkles", label: L10n.scannerEnhance) { pages[selected].enhanced.toggle() }
                        .foregroundStyle(pages.indices.contains(selected) && pages[selected].enhanced ? Theme.accent : Theme.primaryText)
                        .accessibilityValue(pages.indices.contains(selected) && pages[selected].enhanced ? L10n.selectionOn : L10n.selectionOff)
                    reviewTool("arrow.counterclockwise", label: L10n.cropReset) {
                        pages[selected].quarterTurns = 0; pages[selected].filter = 0; pages[selected].enhanced = false; pages[selected].corners = ScannerPage(original: pages[selected].original).corners
                    }
                    reviewTool("trash", label: L10n.delete) {
                        pages.remove(at: selected); selected = max(0, min(selected, pages.count - 1))
                        if pages.isEmpty { reviewing = false }
                    }
                }.padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal)
            }.disabled(pages.isEmpty || busy)
        }
        .padding(.vertical, 12)
        .background(Theme.canvas)
        .disabled(busy)
        .interactiveDismissDisabled(busy)
        .overlay { if busy { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
    }

    private func icon(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 44, height: 44) }
            .accessibilityLabel(label)
    }

    private func appendCapture(_ data: Data, generation: UUID) async {
        let corners = await Task.detached(priority: .userInitiated) { ScannerPage.detectedCorners(data) }.value
        guard !completed, !native, !reviewing, generation == captureGeneration else { return }
        guard let corners else {
            busy = false; failed = true
            if canRunCamera && scenePhase == .active { camera.start() }
            return
        }
        let page = ScannerPage(original: data, corners: corners)
        if UIDevice.current.userInterfaceIdiom == .pad {
            _ = captureReview.stage(page)
        } else {
            pages.append(page)
            selected = pages.count - 1
        }
        busy = false
    }

    private var previewKey: String {
        guard pages.indices.contains(selected) else { return "empty" }
        let page = pages[selected]
        return "\(page.id)-\(page.quarterTurns)-\(page.filter)-\(page.enhanced)-\(page.corners)-\(cropping)"
    }

    private func reviewTool(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button { guard !busy else { return }; action() } label: {
            VStack(spacing: 5) { Image(systemName: symbol); Text(label).font(.caption) }
                .frame(minWidth: 44, minHeight: 44)
        }.accessibilityLabel(label).accessibilityIdentifier("scanner.tool.\(symbol)")
    }

    private func stopCamera() {
        ready = false
        camera.stop()
    }

    private func finish() {
        guard !busy, !completed else { return }
        busy = true
        let draft = pages
        Task {
            let data = await Task.detached(priority: .userInitiated) {
                ScanCaptureEncoding.pages(count: draft.count, encode: { draft[$0].rendered()?.jpegData(compressionQuality: 0.9) })
            }.value
            busy = false
            guard !completed else { return }
            guard let data else { failed = true; return }
            completed = true
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            onName(trimmed.isEmpty ? L10n.scanName(Date().formatted(date: .abbreviated, time: .shortened)) : trimmed)
            onFinish(.scanned(data))
        }
    }
}
#endif

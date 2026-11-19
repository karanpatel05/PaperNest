#if os(iOS)
import SwiftUI
import PhotosUI
import PaperNestCore

/// Capture and review only. Completion goes through the existing import-location
/// and document naming workflow; it never reports an uncommitted document saved.
struct ScannerWorkspaceView: View {
    var onName: (String) -> Void = { _ in }
    let onFinish: (DocumentCameraView.Outcome) -> Void
    @State private var camera = ScannerCamera()
    @FocusState private var naming: Bool
    @State private var name = L10n.scanName(Date().formatted(date: .abbreviated, time: .shortened))
    /// The automatic shutter: on from the start when the scanner's defaults say so.
    @State private var automatic = ScanSettingsStore.load().automaticOnEntry
    @State private var previewImage: UIImage?
    @State private var ready = false
    @State private var hasTorch = false
    @State private var torch = false
    @State private var outline: [CGPoint] = []
    /// What the camera's last look says to do; nil says nothing.
    @State private var feedback: ScanCaptureFeedback?
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
    /// The scanner's defaults. The mode it opens in comes from them; after
    /// that the mode is whatever the person picks.
    @State private var settings = ScanSettingsStore.load()
    @State private var settingsPresented = false
    @State private var kind = ScanSettingsStore.load().mode
    /// Which side of a card each capture is, in ID / Card mode.
    @State private var cards = ScanCardPairing<UUID>()
    /// The Cleanup sheet, for the page being shown or for the pages picked.
    @State private var cleanupRequest: CleanupRequest?
    /// Picking several pages in the filmstrip, and which are picked.
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var confirmingDelete = false

    private struct CleanupRequest: Identifiable {
        let id = UUID()
        let page: ScannerPage
        let scope: ScannerCleanupSheet.Scope
    }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
            // The camera starts out looking for a document with the shutter
            // manual; tell it what this scanner opened as.
            camera.setDetection(kind.detection)
            camera.setAutomatic(automatic)
            camera.onAutoCapture = {
                guard captureReview.pending == nil, !native, !reviewing, !photoPickerPresented, !completed else { return }
                busy = true
            }
            camera.onObservation = { corners, said in
                outline = corners
                withAnimation(.easeInOut(duration: 0.2)) { feedback = said }
            }
            camera.onPhoto = { data in
                guard captureReview.pending == nil, !completed, !native, !reviewing, !photoPickerPresented else { return }
                guard let data else { busy = false; failed = true; return }
                // Every capture is shown for a decision before it joins the
                // queue, so the camera rests until the answer.
                stopCamera(); torch = false
                let generation = captureGeneration
                Task { await appendCapture(data, generation: generation) }
            }
            #if DEBUG
            if pages.isEmpty, let paths = UserDefaults.standard.string(forKey: "PaperNestDebugScannerImages") {
                pages = paths.split(separator: ";").compactMap { path in
                    guard let data = try? Data(contentsOf: URL(fileURLWithPath: String(path))), UIImage(data: data) != nil else { return nil }
                    return ScannerPage(original: data)
                }
                if UserDefaults.standard.bool(forKey: "PaperNestDebugScannerPendingCapture"),
                   let pending = pages.popLast() {
                    _ = captureReview.stage(pending)
                    return
                }
                reviewing = !pages.isEmpty
                if reviewing { return }
            }
            #endif
            if canRunCamera { camera.start() }
            #if DEBUG
            if let path = UserDefaults.standard.string(forKey: "PaperNestDebugScannerFrames") {
                await playDebugLooks(at: path)
            }
            #endif
        }
        .onDisappear {
            stopCamera()
            camera.onStatus = nil
            camera.onObservation = nil
            camera.onPhoto = nil
            camera.onAutoCapture = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && canRunCamera { camera.start() }
            else { stopCamera(); torch = false }
        }
        .onChange(of: automatic) { _, value in camera.setAutomatic(value) }
        // A photo has no sheet to wait for, so there is nothing to trigger an
        // automatic exposure.
        .onChange(of: kind) { _, value in
            if !value.findsEdges { automatic = false }
            camera.setDetection(value.detection)
            if !value.pairsSides { cards.cancelPending() }
        }
        .onChange(of: reviewing) { _, value in
            if !value { endSelection() }
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
                .foregroundStyle(ScannerChrome.secondaryText).multilineTextAlignment(.center).padding(.horizontal)
            Group {
                if let image = pendingPreview {
                    ScannerZoomPreview(image: image, accessibilityValue: page.spreadGutter == nil ? "" : L10n.scannerBookTwoPages)
                } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            .task(id: page.id) {
                pendingPreview = nil
                let data = await Task.detached(priority: .userInitiated) {
                    page.reviewPicture(maxDimension: 1600)?.jpegData(compressionQuality: 0.85)
                }.value
                guard !Task.isCancelled, captureReview.pending?.id == page.id else { return }
                pendingPreview = data.flatMap { UIImage(data: $0) }
                if pendingPreview == nil { failed = true }
            }
        }
        .foregroundStyle(.white)
        .background(ScannerChrome.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { captureDecisionButtons }
                VStack(spacing: 12) { captureDecisionButtons }
            }
            .padding(16).frame(maxWidth: .infinity).background(ScannerChrome.panel)
        }
        .environment(\.colorScheme, .dark)
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
        .buttonStyle(.borderedProminent).tint(ScannerChrome.purple).disabled(pendingPreview == nil)
        .accessibilityIdentifier("scanner.capture-keep")
    }

    private func resolveCapture(keep: Bool) {
        guard captureReview.pending != nil else { return }
        captureGeneration = UUID()
        if keep, let page = captureReview.keep() {
            // A book's spread becomes its two pages, left then right; the left one is shown.
            if page.spreadGutter != nil {
                pages.append(contentsOf: page.spreadPages())
                selected = pages.count - 2
            // A card's back goes straight after its front, wherever that is by now.
            } else if kind.pairsSides, let front = cards.keep(page.id).front, let index = pages.firstIndex(where: { $0.id == front }) {
                pages.insert(page, at: index + 1)
                selected = index + 1
            } else {
                pages.append(page)
                selected = pages.count - 1
            }
        } else { captureReview.discard() }
        pendingPreview = nil
        if canRunCamera && scenePhase == .active { camera.start(waitForNextSheet: keep) }
    }

    // MARK: - Capture feedback

    /// What the camera sees, in a word or two: under the top bar, clear of
    /// the middle of the page and of the shutter. Ready is in the accent.
    private func feedbackLabel(_ feedback: ScanCaptureFeedback) -> some View {
        Label(Self.feedbackText(feedback), systemImage: Self.feedbackSymbol(feedback))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(feedback == .ready ? ScannerChrome.purple : Color.black.opacity(0.65), in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("scanner.feedback")
            // Language-free, for tests.
            .accessibilityValue(feedback.rawValue)
            .transition(.opacity)
    }

    static func feedbackText(_ feedback: ScanCaptureFeedback) -> String {
        switch feedback {
        case .improveLighting: L10n.scannerFeedbackLighting
        case .moveBack: L10n.scannerFeedbackMoveBack
        case .moveCloser: L10n.scannerFeedbackMoveCloser
        case .holdSteady: L10n.scannerFeedbackHoldSteady
        case .ready: L10n.scannerFeedbackReady
        }
    }

    static func feedbackSymbol(_ feedback: ScanCaptureFeedback) -> String {
        switch feedback {
        case .improveLighting: "lightbulb"
        case .moveBack: "arrow.down.right.and.arrow.up.left"
        case .moveCloser: "arrow.up.left.and.arrow.down.right"
        case .holdSteady: "hand.raised"
        case .ready: "checkmark.circle.fill"
        }
    }

    #if DEBUG
    /// UI tests: a simulator has no camera, so a recorded run of looks is
    /// played through the camera's own processing — the same guide and the
    /// same callback a real frame goes through. The file is JSON:
    /// `{"interval": seconds, "looks": [{"corners": [[x, y], …], "luminance": 0.5}, …]}`.
    private func playDebugLooks(at path: String) async {
        struct Recording: Decodable {
            struct Look: Decodable {
                let corners: [[Double]]
                let luminance: Double?
            }
            let interval: Double
            let looks: [Look]
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let recording = try? JSONDecoder().decode(Recording.self, from: data) else { return }
        for look in recording.looks {
            guard !Task.isCancelled else { return }
            let corners = look.corners.compactMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
            camera.debugObserve(ScanFrameObservation(corners: corners, luminance: look.luminance))
            try? await Task.sleep(for: .seconds(recording.interval))
        }
    }
    #endif

    // MARK: - Capture

    private var capture: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScannerCameraPreview(camera: camera, outline: kind.findsEdges ? outline : []).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    icon("xmark", label: L10n.cancel) { completed = true; onFinish(.cancelled) }
                    Text(L10n.scan).font(.headline).accessibilityAddTraits(.isHeader)
                    Spacer()
                    if hasTorch {
                        icon(torch ? "bolt.fill" : "bolt.slash", label: L10n.scannerFlash) { torch.toggle(); camera.torch(torch) }
                            .accessibilityValue(torch ? L10n.scannerOn : L10n.scannerOff)
                    }
                    Menu {
                        Button { photoPickerPresented = true } label: {
                            Label(L10n.importPhotos, systemImage: "photo")
                        }
                        if DocumentCameraView.isSupported {
                            Button {
                                guard !busy else { return }
                                captureGeneration = UUID(); stopCamera(); native = true
                            } label: { Label(L10n.scannerNative, systemImage: "doc.viewfinder") }
                        }
                        Button { settingsPresented = true } label: {
                            Label(L10n.scannerSettings, systemImage: "gearshape")
                        }
                    } label: { Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44) }
                    .accessibilityLabel(L10n.more).disabled(busy)
                    .accessibilityIdentifier("scanner.more")
                }
                .padding(.horizontal, 8).background(.black.opacity(0.8))
                if let feedback { feedbackLabel(feedback).padding(.top, 14) }
                Spacer()
                if !ready {
                    VStack(spacing: 12) {
                        Text(L10n.scannerCameraUnavailable).multilineTextAlignment(.center)
                        Button(L10n.scannerRetry) { camera.start() }.buttonStyle(.bordered).disabled(busy)
                    }.padding().background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 16)).padding()
                }
                if kind.pairsSides, cards.offer != nil { cardBackOffer.padding(.horizontal).padding(.bottom, 10) }
                ScannerKindSelector(kind: $kind).disabled(busy).padding(.horizontal, 8).padding(.bottom, 12)
                if kind.pairsSides { cardSideLabel.padding(.bottom, 6) }
                HStack(spacing: 16) {
                    reviewStackButton
                    Spacer(minLength: 0)
                    shutter
                    Spacer(minLength: 0)
                    Button { automatic.toggle() } label: {
                        Text(automatic ? L10n.scannerAuto : L10n.scannerManual)
                            .font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            .padding(.horizontal, 12).frame(minWidth: 64, minHeight: 44)
                            .background(automatic ? ScannerChrome.purple : ScannerChrome.raised, in: Capsule())
                            .overlay { Capsule().strokeBorder(ScannerChrome.stroke, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || !kind.findsEdges)
                    .opacity(kind.findsEdges ? 1 : 0.45)
                    .accessibilityValue(automatic ? L10n.scannerOn : L10n.scannerOff)
                    .accessibilityIdentifier("scanner.mode")
                }
                .padding(.horizontal, 24).padding(.vertical, 18)
                .background(.black.opacity(0.85), in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
            }.foregroundStyle(.white)
        }
        .sheet(isPresented: $settingsPresented) { ScannerSettingsSheet(settings: $settings) }
        .onChange(of: settings) { _, value in ScanSettingsStore.save(value) }
    }

    /// Which side of the card the next capture will be.
    private var cardSideLabel: some View {
        let side = cards.nextSide == .front ? L10n.scannerCardFront : L10n.scannerCardBack
        return Text(side).font(.footnote.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(ScannerChrome.raised, in: Capsule())
            .accessibilityIdentifier("scanner.card.side")
    }

    /// Asked once a card's front is kept. Taking another picture instead of
    /// answering starts another card.
    private var cardBackOffer: some View {
        VStack(spacing: 10) {
            Text(L10n.scannerCardFrontSaved).font(.subheadline.weight(.semibold))
            Text(L10n.scannerCardBackPrompt).font(.footnote).multilineTextAlignment(.center)
                .foregroundStyle(ScannerChrome.secondaryText)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { cardBackOfferButtons }
                VStack(spacing: 8) { cardBackOfferButtons }
            }
        }
        .padding(14)
        .frame(maxWidth: 420)
        .background(ScannerChrome.panel.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(ScannerChrome.stroke, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scanner.card.offer")
    }

    @ViewBuilder private var cardBackOfferButtons: some View {
        Button { cards.scanBack() } label: { Text(L10n.scannerCardScanBack).frame(minWidth: 110, minHeight: 36) }
            .buttonStyle(.borderedProminent).tint(ScannerChrome.purple)
            .accessibilityIdentifier("scanner.card.scan-back")
        Button { cards.continueWithFrontOnly() } label: { Text(L10n.scannerCardContinue).frame(minWidth: 110, minHeight: 36) }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("scanner.card.continue")
    }

    /// The pages kept so far: the latest one with a count, and the way into review.
    private var reviewStackButton: some View {
        Button { reviewing = true } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let last = pages.last {
                        ScannerThumbnail(page: last, pages: pages)
                    } else {
                        Image(systemName: "square.stack").font(.title3)
                    }
                }
                .frame(width: 44, height: 56)
                .background(ScannerChrome.raised, in: RoundedRectangle(cornerRadius: 8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(ScannerChrome.stroke, lineWidth: 1) }
                if !pages.isEmpty {
                    Text(verbatim: String(pages.count)).font(.caption2.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 20)
                        .background(ScannerChrome.purple, in: Capsule())
                        .offset(x: 8, y: -8)
                }
            }
            .frame(minWidth: 64, minHeight: 56)
        }
        .buttonStyle(.plain)
        .disabled(pages.isEmpty || busy)
        .opacity(pages.isEmpty ? 0.45 : 1)
        .accessibilityLabel(L10n.scannerReview).accessibilityValue(String(pages.count))
        .accessibilityIdentifier("scanner.review")
    }

    private var shutter: some View {
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
        .buttonStyle(.plain)
        .disabled((!ready && debugCaptureData == nil) || busy).accessibilityLabel(L10n.takePhoto)
        .accessibilityIdentifier("scanner.shutter")
    }

    // MARK: - Review

    /// iPad has room for the pages, the page and its tools side by side.
    /// The phone, and any size at accessibility text sizes, stacks them.
    private var review: some View {
        Group {
            if horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize { wideReview } else { stackedReview }
        }
        .foregroundStyle(.white)
        .background(ScannerChrome.background.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .disabled(busy)
        .interactiveDismissDisabled(busy)
        .overlay { if busy { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .sheet(item: $cleanupRequest) { request in
            ScannerCleanupSheet(page: request.page, scope: request.scope) { cleanup, target in
                applyCleanup(cleanup, to: target, from: request)
            }
        }
        .alert(L10n.scannerDeletePagesTitle(selection.count), isPresented: $confirmingDelete) {
            Button(L10n.delete, role: .destructive) { deleteSelection() }
            Button(L10n.cancel, role: .cancel) {}
        } message: { Text(L10n.scannerDeletePagesMessage) }
    }

    private var stackedReview: some View {
        VStack(spacing: 12) {
            HStack {
                backToCamera
                Spacer()
                Text(L10n.scannerEdit).font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                saveButton
            }.padding(.horizontal, 8)
            nameField.padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    pageThumbnails
                    addPageButton
                }.padding(.horizontal)
            }
            previewArea
            if selecting {
                // While pages are being picked, the bar is about them and
                // not about the one page being shown.
                batchToolbar.padding(.horizontal)
            } else {
                presetStrip.padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        cropTool; rotateTool; filterTool(vertical: false); enhanceTool; cleanupTool
                        batchSelectTool; resetTool; deleteTool
                    }
                    .padding(12)
                    .background(ScannerChrome.panel, in: RoundedRectangle(cornerRadius: 18))
                    .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(ScannerChrome.stroke, lineWidth: 1) }
                    .padding(.horizontal)
                }.disabled(pages.isEmpty || busy)
            }
        }
        .padding(.vertical, 12)
    }

    private var wideReview: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                backToCamera
                Text(L10n.scannerEdit).font(.headline).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                nameField.frame(maxWidth: 360)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(ScannerChrome.panel)
            HStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        pageThumbnails
                        addPageButton
                    }.padding(.vertical, 14).frame(maxWidth: .infinity)
                }
                .frame(width: 104)
                .background(ScannerChrome.panel.opacity(0.6))
                .accessibilityElement(children: .contain)
                .accessibilityLabel(L10n.scannerPages)
                VStack(spacing: 8) {
                    previewArea
                    if !selecting { presetStrip }
                }
                .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        // One page's tools rest while several are being picked.
                        Group { enhanceTool; cropTool; rotateTool; filterTool(vertical: true); cleanupTool }
                            .disabled(selecting)
                        batchSelectTool
                        Group { moveTool(by: -1); moveTool(by: 1); duplicateTool; resetTool; deleteTool }
                            .disabled(selecting)
                    }.padding(12)
                }
                .frame(width: 208)
                .background(ScannerChrome.panel.opacity(0.6))
                .disabled(pages.isEmpty || busy)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(L10n.scannerTools)
            }
            HStack {
                Spacer()
                saveButton
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(ScannerChrome.panel)
            if selecting { batchToolbar.padding(.horizontal, 12).padding(.bottom, 8).background(ScannerChrome.panel) }
        }
        .environment(\.scannerToolsVertical, true)
    }

    private var backToCamera: some View {
        icon("chevron.left", label: L10n.scanPages) { guard !busy else { return }; reviewing = false }
    }

    private var saveButton: some View {
        Button { finish() } label: {
            Text(L10n.exportSave).font(.subheadline.weight(.semibold))
                .padding(.horizontal, 20).frame(minHeight: 44)
                .background(ScannerChrome.purple, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(pages.isEmpty || busy)
        .opacity(pages.isEmpty ? 0.45 : 1)
        .accessibilityIdentifier("scanner.finish")
    }

    private var nameField: some View {
        TextField(L10n.documentName, text: $name)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(ScannerChrome.raised, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(ScannerChrome.stroke, lineWidth: 1) }
            .focused($naming).submitLabel(.done).onSubmit { naming = false }
            .accessibilityIdentifier("scanner.name")
    }

    private var pageThumbnails: some View {
        ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
            // While pages are being picked a tap picks or unpicks; otherwise
            // it shows the page. The outline follows whichever is in force.
            let marked: Bool = selecting ? selection.contains(page.id) : selected == index
            Button {
                guard !busy else { return }
                if selecting {
                    if selection.contains(page.id) { selection.remove(page.id) } else { selection.insert(page.id) }
                } else {
                    selected = index
                }
            } label: {
                pageChip(page, number: index + 1, marked: marked)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("scanner.page.\(index)")
            .accessibilityLabel(pageLabel(page, number: index + 1))
            .accessibilityValue(selecting ? (marked ? L10n.selectionOn : L10n.selectionOff) : "")
            .accessibilityAddTraits(marked ? [.isSelected] : [])
            .contextMenu {
                Button(L10n.duplicate) { duplicatePage(at: index) }
                Button(L10n.scannerMoveEarlier) { movePage(at: index, by: -1) }.disabled(index == 0)
                Button(L10n.scannerMoveLater) { movePage(at: index, by: 1) }.disabled(index == pages.count - 1)
            }
        }
    }

    /// One page in the filmstrip: its picture, its number, and while pages
    /// are being picked, whether this one is.
    private func pageChip(_ page: ScannerPage, number: Int, marked: Bool) -> some View {
        let outline: Color = marked ? Theme.accent : ScannerChrome.stroke
        let fill: Color = marked ? ScannerChrome.purple.opacity(0.28) : Color.clear
        return VStack(spacing: 4) {
            ScannerThumbnail(page: page, pages: pages).frame(width: 56, height: 70)
                .overlay(alignment: .topTrailing) { if selecting { pickMark(marked) } }
            Text(verbatim: String(number)).font(.caption.monospacedDigit())
            // A card's two sides are two pages; this is what says they belong together.
            if let side = sideName(of: page) { Text(side).font(.caption2).foregroundStyle(ScannerChrome.secondaryText) }
        }
        .padding(5)
        .background(fill, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(outline, lineWidth: marked ? 2 : 1))
    }

    /// What a page in the filmstrip is called: its number, its side when it
    /// is a card's, and anything its quality check found (the thumbnail's
    /// mark), the page it repeats included.
    private func pageLabel(_ page: ScannerPage, number: Int) -> String {
        let name: String = L10n.scannerReview + " " + String(number)
        let notes = ScanQualityMemo.shared.notes(for: page, among: pages)
        return ([name] + [sideName(of: page)].compactMap { $0 } + notes).joined(separator: ", ")
    }

    /// "Front" or "Back" for a page scanned as a card's side.
    private func sideName(of page: ScannerPage) -> String? {
        switch cards.side(of: page.id) {
        case .front: L10n.scannerCardFront
        case .back: L10n.scannerCardBack
        case nil: nil
        }
    }

    private func pickMark(_ marked: Bool) -> some View {
        Image(systemName: marked ? "checkmark.circle.fill" : "circle")
            .font(.body.weight(.semibold))
            .foregroundStyle(marked ? Theme.accent : Color.white)
            .background(Circle().fill(Color.black.opacity(0.55)))
            .padding(2)
    }

    private var addPageButton: some View {
        Button { guard !busy else { return }; reviewing = false } label: {
            Image(systemName: "plus").font(.title3)
                .frame(width: 56, height: 56)
                .background(ScannerChrome.raised, in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(ScannerChrome.stroke, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.scanPages)
        .accessibilityIdentifier("scanner.add-page")
    }

    private var previewArea: some View {
        Group {
            if cropping && pages.indices.contains(selected) {
                ScannerCornerEditor(page: Binding(
                    get: { pages[selected] },
                    set: { if !busy && pages.indices.contains(selected) { pages[selected] = $0 } }
                ))
            } else if let image = previewImage, pages.indices.contains(selected) {
                ScannerZoomPreview(image: image, accessibilityValue: previewValue(pages[selected]))
                    .id(pages[selected].id)
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .overlay(alignment: .bottom) { if !cropping, let page = selectedPage { ScanQualityNote(page: page, pages: pages).padding(8) } }
        .task(id: previewKey) {
            guard pages.indices.contains(selected), !cropping else { return }
            let page = pages[selected]
            previewImage = nil
            let data = await Task.detached(priority: .userInitiated) { page.rendered(maxDimension: 1600)?.jpegData(compressionQuality: 0.85) }.value
            guard !Task.isCancelled, !completed else { return }
            previewImage = data.flatMap { UIImage(data: $0) }
        }
    }

    // MARK: - Page tools

    private var selectedPage: ScannerPage? { pages.indices.contains(selected) ? pages[selected] : nil }

    private var cropTool: some View {
        reviewTool("crop", label: L10n.crop, active: cropping) { cropping.toggle() }
    }

    private var rotateTool: some View {
        reviewTool("rotate.right", label: L10n.rotate) { pages[selected].quarterTurns = (pages[selected].quarterTurns + 1) % 4 }
    }

    /// What tests and VoiceOver are told about the page on screen: its
    /// number, its turn, its preset and its three Cleanup amounts.
    private func previewValue(_ page: ScannerPage) -> String {
        "\(selected + 1); \(L10n.rotate) \(page.quarterTurns); \(L10n.filter) \(page.appearance.preset.rawValue); "
            + "\(L10n.scannerCleanup) \(ScannerCleanupSheet.describe(page.appearance.cleanup))"
    }

    private func setPreset(_ preset: ScanPreset) {
        guard !busy, pages.indices.contains(selected) else { return }
        pages[selected].appearance.preset = preset
    }

    /// The same presets as the strip, as a menu: the strip scrolls, and a
    /// menu names them all at once.
    private func filterTool(vertical: Bool) -> some View {
        Menu {
            ForEach(ScanPreset.allCases, id: \.self) { preset in
                Button { setPreset(preset) } label: {
                    if selectedPage?.appearance.preset == preset { Label(preset.title, systemImage: "checkmark") }
                    else { Text(preset.title) }
                }
            }
        } label: {
            ScannerToolLabel(symbol: "camera.filters", title: L10n.filter,
                             active: (selectedPage?.appearance.preset ?? .original) != .original)
                // A menu's label is not told it is disabled, so while pages
                // are being picked it has to be dimmed here like its neighbours.
                .opacity(selecting ? 0.4 : 1)
        }
        .accessibilityLabel(L10n.filter)
        .accessibilityValue(selectedPage?.appearance.preset.title ?? "")
        .accessibilityIdentifier("scanner.tool.camera.filters")
    }

    /// One tap for the Auto preset, which is what Enhance has always applied.
    private var enhanceTool: some View {
        let isAuto = selectedPage?.appearance.preset == .auto
        return reviewTool("sparkles", label: L10n.scannerEnhance, active: isAuto) { setPreset(isAuto ? .original : .auto) }
            .accessibilityValue(isAuto ? L10n.selectionOn : L10n.selectionOff)
    }

    private var cleanupTool: some View {
        let isOn = selectedPage?.appearance.cleanup.isActive ?? false
        return reviewTool("slider.horizontal.3", label: L10n.scannerCleanup, active: isOn) { openCleanup() }
            .accessibilityValue(isOn ? L10n.selectionOn : L10n.selectionOff)
    }

    private var batchSelectTool: some View {
        reviewTool("checklist", label: L10n.scannerSelectPages, active: selecting) {
            if selecting { endSelection() } else { cropping = false; selecting = true }
        }
        .accessibilityValue(selecting ? L10n.selectionOn : L10n.selectionOff)
    }

    private var presetStrip: some View {
        ScannerPresetStrip(selection: selectedPage?.appearance.preset,
                           cleanupActive: selectedPage?.appearance.cleanup.isActive ?? false,
                           onSelect: setPreset, onCleanup: openCleanup)
            .disabled(pages.isEmpty || busy)
    }

    private func openCleanup() {
        guard !busy, let page = selectedPage else { return }
        cleanupRequest = CleanupRequest(page: page, scope: .page(total: pages.count))
    }

    private func applyCleanup(_ cleanup: ScanCleanup, to target: ScannerCleanupSheet.Target, from request: CleanupRequest) {
        switch target {
        case .page: ScanPageBatch.update([request.page.id], in: &pages) { $0.appearance.cleanup = cleanup }
        case .allPages: for index in pages.indices { pages[index].appearance.cleanup = cleanup }
        case .selection: ScanPageBatch.update(selection, in: &pages) { $0.appearance.cleanup = cleanup }
        }
    }

    // MARK: - Several pages at once

    private var batchToolbar: some View {
        ScannerBatchToolbar(
            count: selection.count,
            canMoveEarlier: ScanPageBatch.canMove(selection, .earlier, in: pages),
            canMoveLater: ScanPageBatch.canMove(selection, .later, in: pages),
            onClose: endSelection,
            onFilter: { preset in ScanPageBatch.update(selection, in: &pages) { $0.appearance.preset = preset } },
            onCleanup: {
                // The first picked page stands for the rest in the sheet's preview.
                guard let page = pages.first(where: { selection.contains($0.id) }) else { return }
                cleanupRequest = CleanupRequest(page: page, scope: .selection(count: selection.count))
            },
            onDuplicate: {
                let result = ScanPageBatch.duplicate(selection, in: pages, focus: selected) { $0.copy() }
                pages = result.pages; selected = result.focus
            },
            onMove: { direction in
                let result = ScanPageBatch.move(selection, direction, in: pages, focus: selected)
                pages = result.pages; selected = result.focus
            },
            // One page goes at once, as the single-page Delete does. More
            // than one is asked about first.
            onDelete: { if selection.count > 1 { confirmingDelete = true } else { deleteSelection() } })
            .disabled(busy)
    }

    private func deleteSelection() {
        let result = ScanPageBatch.delete(selection, from: pages, focus: selected)
        pages = result.pages; selected = result.focus
        cards.forget(selection)
        selection.removeAll()
        if pages.isEmpty { reviewing = false }
    }

    private func endSelection() {
        selecting = false
        selection.removeAll()
    }

    private var resetTool: some View {
        reviewTool("arrow.counterclockwise", label: L10n.cropReset) { pages[selected].reset() }
    }

    private var deleteTool: some View {
        reviewTool("trash", label: L10n.delete) {
            cards.forget([pages[selected].id])
            pages.remove(at: selected); selected = max(0, min(selected, pages.count - 1))
            if pages.isEmpty { reviewing = false }
        }
    }

    private var duplicateTool: some View {
        reviewTool("plus.square.on.square", label: L10n.duplicate) { duplicatePage(at: selected) }
    }

    private func moveTool(by offset: Int) -> some View {
        reviewTool(offset < 0 ? "arrow.up" : "arrow.down",
                   label: offset < 0 ? L10n.scannerMoveEarlier : L10n.scannerMoveLater) { movePage(at: selected, by: offset) }
            .disabled(!pages.indices.contains(selected + offset))
    }

    private func duplicatePage(at index: Int) {
        guard !busy, pages.indices.contains(index) else { return }
        pages.insert(pages[index].copy(), at: index + 1)
        selected = index + 1
    }

    private func movePage(at index: Int, by offset: Int) {
        guard !busy, pages.indices.contains(index), pages.indices.contains(index + offset) else { return }
        pages.swapAt(index, index + offset)
        selected = index + offset
    }

    private func icon(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 44, height: 44) }
            .accessibilityLabel(label)
    }

    private func appendCapture(_ data: Data, generation: UUID) async {
        // A document is cropped to the edges found in it. A photo keeps the
        // whole frame, so it only has to be an image that decodes.
        // What is looked for, and the look the page starts with, are the
        // mode's as it was when the shutter was pressed.
        let detection = kind.detection
        let look = kind.startingAppearance(defaultPreset: settings.preset)
        let book = kind == .book
        let found = await Task.detached(priority: .userInitiated) { () -> (corners: [CGPoint], gutter: Double?)? in
            let corners = detection.map { ScannerPage.detectedCorners(data, detection: $0) }
                ?? (UIImage(data: data) == nil ? nil : ScannerPage.wholeFrame)
            // A book's spread is split at its fold when kept; where, is decided now, from the mode at the shutter.
            return corners.map { ($0, book ? ScannerPage.spreadGutter(data, corners: $0) : nil) }
        }.value
        guard !completed, !native, !reviewing, generation == captureGeneration else { return }
        guard let (corners, gutter) = found else {
            busy = false; failed = true
            if canRunCamera && scenePhase == .active { camera.start() }
            return
        }
        // On iPhone as on iPad, a capture is not kept until the person says
        // so: it is staged, shown, and joins the queue only on Keep.
        _ = captureReview.stage(ScannerPage(original: data, appearance: look, corners: corners, mode: kind, spreadGutter: gutter))
        busy = false
    }

    private var previewKey: String {
        guard pages.indices.contains(selected) else { return "empty" }
        return "\(pages[selected].drawKey)-\(cropping)"
    }

    private func reviewTool(_ symbol: String, label: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button { guard !busy, pages.indices.contains(selected) else { return }; action() } label: {
            ScannerToolLabel(symbol: symbol, title: label, active: active)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label).accessibilityIdentifier("scanner.tool.\(symbol)")
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

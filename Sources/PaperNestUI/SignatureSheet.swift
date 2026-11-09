import Observation
import PaperNestCore
import PaperNestStore
import SwiftUI

/// An unsaved drawing and placement preview. SQLite remains the authority for
/// reusable signatures; a failed write never clears this transient buffer.
@MainActor @Observable final class SignatureDraft {
    let model: DocumentModel
    private(set) var page: Page
    private(set) var signatures: [SavedSignature] = []
    private(set) var selectedID: String?
    var name = ""
    var strokes: [InkStroke] = []
    var capturePoints: [InkPoint] = []
    var capturedStroke: [InkStroke] {
        capturePoints.isEmpty ? [] : [InkStroke(tool: .pen, color: .black, width: 2, points: capturePoints)]
    }
    func finishCapture() {
        strokes.append(contentsOf: capturedStroke)
        capturePoints = []
    }
    var drawing = true
    var target = NormalizedRect(x: 0.55, y: 0.72, width: 0.32, height: 0.14)
    private(set) var busy = false
    private var loaded = false
    var hasUnsavedChanges: Bool { drawing && (!strokes.isEmpty || !capturePoints.isEmpty) }
    var failed = false
    private(set) var pageChanged = false

    init(model: DocumentModel, page: Page) { self.model = model; self.page = page }
    var selected: SavedSignature? { signatures.first { $0.id == selectedID } }
    var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (!strokes.isEmpty || !capturePoints.isEmpty) }
    private var store: LibraryStore? { model.session.environment?.store }

    func load() async {
        guard !busy, !loaded else { return }
        busy = true
        defer { busy = false }
        do {
            guard let store else { throw StoreError.pageNotFound }
            signatures = try await store.signatures()
            if let first = signatures.first { select(first) }
            loaded = true
        } catch { failed = true }
    }

    func select(_ signature: SavedSignature) { selectedID = signature.id; drawing = false }
    func beginDrawing() { selectedID = nil; drawing = true; name = ""; strokes = []; capturePoints = [] }

    @discardableResult func saveReusable() async -> Bool {
        guard !busy, canSave else { return false }
        // Save the same ink the user can see, even after an interrupted drag.
        // This also makes a late release harmless and preserves ink on failure.
        finishCapture()
        guard let signature = SavedSignature(name: name.trimmingCharacters(in: .whitespacesAndNewlines), capturing: strokes)
        else { return false }
        busy = true
        defer { busy = false }
        do {
            try SubscriptionStore.shared.requirePremiumOperation()
            guard let store else { throw StoreError.pageNotFound }
            try await store.saveSignature(signature)
            signatures.append(signature)
            select(signature)
            failed = false
            model.session.didChange()
            return true
        } catch { failed = true; return false }
    }

    @discardableResult func remove(_ signature: SavedSignature) async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            guard let store else { throw StoreError.pageNotFound }
            try await store.deleteSignature(signature.id)
            signatures.removeAll { $0.id == signature.id }
            if selectedID == signature.id {
                selectedID = signatures.first?.id
                drawing = selectedID == nil
            }
            failed = false
            model.session.didChange()
            return true
        } catch { failed = true; return false }
    }

    @discardableResult func place(undoManager: UndoManager?) async -> Bool {
        guard !busy, let selected else { return false }
        busy = true
        defer { busy = false }
        do {
            try await model.placeSignature(selected, on: page, target: target, undoManager: undoManager)
            failed = false
            return true
        } catch StoreError.pageObjectsChanged {
            pageChanged = true
            failed = true
            return false
        } catch { failed = true; return false }
    }

    func refreshPreview() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            guard let store, let latest = try await store.page(page.id), latest.itemID == model.itemID else {
                throw StoreError.pageNotFound
            }
            page = latest
            pageChanged = false
            failed = false
        } catch { failed = true }
    }

    func resize(width: Double? = nil, height: Double? = nil) {
        let w = min(max(width ?? target.width, 0.1), 1)
        let h = min(max(height ?? target.height, 0.05), 1)
        target = .init(x: min(target.x, 1 - w), y: min(target.y, 1 - h), width: w, height: h)
    }
}

struct SignatureSheet: View {
    let isEmbedded: Bool
    let onClose: (() -> Void)?
    let beforeAction: (() async -> Bool)?
    let undoManager: UndoManager?
    @State private var draft: SignatureDraft
    @State private var showPro = false
    @GestureState private var isCapturing = false
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(model: DocumentModel, page: Page, undoManager: UndoManager?,
         isEmbedded: Bool = false, onClose: (() -> Void)? = nil,
         beforeAction: (() async -> Bool)? = nil, retainedDraft: SignatureDraft? = nil) {
        self.beforeAction = beforeAction
        self.isEmbedded = isEmbedded
        self.onClose = onClose
        self.undoManager = undoManager
        _draft = State(initialValue: retainedDraft ?? SignatureDraft(model: model, page: page))
    }

    var body: some View {
        EditorToolNavigation(isEmbedded: isEmbedded, title: L10n.signatureTitle) {
            Form {
                savedSection
                if draft.drawing { captureSection }
                if let signature = draft.selected { placementSection(signature) }
            }
            .formStyle(.grouped)
            .disabled(draft.busy)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .safeAreaInset(edge: .top, spacing: 0) {
                if isEmbedded {
                    VStack(spacing: 8) {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L10n.signatureTitle).font(.headline)
                                    .fixedSize(horizontal: false, vertical: true)
                                cancelButton
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            HStack {
                                Text(L10n.signatureTitle).font(.headline)
                                Spacer()
                                cancelButton
                            }
                        }
                        placeButton.frame(maxWidth: .infinity, alignment: .trailing)
                    }.padding(12).background(Theme.surface)
                }
            }
            #if os(iOS)
            .safeAreaInset(edge: .bottom) {
                if !isEmbedded {
                    placeButton
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.bar)
                }
            }
            #endif
            .toolbar {
                if !isEmbedded {
                    ToolbarItem(placement: .cancellationAction) { cancelButton }
                    #if os(macOS)
                    ToolbarItem(placement: .confirmationAction) { placeButton }
                    #endif
                }
            }
            .interactiveDismissDisabled(draft.busy || (draft.drawing && (!draft.strokes.isEmpty || !draft.capturePoints.isEmpty)))
            .alert(L10n.genericErrorTitle, isPresented: $draft.failed) {
                if draft.pageChanged {
                    Button(L10n.signatureRefreshPreview) { Task { await draft.refreshPreview() } }
                }
                Button(L10n.ok) {}
            } message: {
                Text(draft.pageChanged ? L10n.markupChanged : L10n.signatureSaveFailed)
            }
            .task { await draft.load() }
        }
        .sheet(isPresented: $showPro) { ProPaywallView(store: .shared) }
        #if os(macOS)
        .frame(minWidth: isEmbedded ? nil : 460, idealWidth: isEmbedded ? nil : 560,
               minHeight: isEmbedded ? nil : 600, idealHeight: isEmbedded ? nil : 720)
        #endif
    }

    private var cancelButton: some View {
        Button(L10n.cancel) { close() }
            .disabled(draft.busy).accessibilityIdentifier("signature-cancel")
    }

    private var placeButton: some View {
        Button(L10n.signaturePlace) {
            guard SubscriptionStore.shared.allowsPremiumOperations else { showPro = true; return }
            nameFocused = false
            Task {
                guard await beforeAction?() ?? true else { return }
                if await draft.place(undoManager: undoManager) { close() }
            }
        }
        .disabled(draft.busy || draft.selected == nil || draft.model.isChangingNotebookPage)
        .accessibilityIdentifier("signature-place")
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private var savedSection: some View {
        Section {
            if draft.signatures.isEmpty {
                Text(L10n.signatureNoSaved).foregroundStyle(Theme.secondaryText)
            }
            ForEach(draft.signatures) { signature in
                HStack(spacing: 12) {
                    Button { draft.select(signature) } label: {
                        HStack(spacing: 12) {
                            SignatureInkPreview(strokes: signature.placed(in: .full, on: CGSize(width: 90, height: 36)),
                                                sourceSize: CGSize(width: 90, height: 36))
                                .frame(width: 90, height: 44)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                                .accessibilityHidden(true)
                            Text(verbatim: signature.name).foregroundStyle(Theme.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            if draft.selectedID == signature.id {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(draft.selectedID == signature.id ? L10n.selectionOn : L10n.selectionOff)
                    .accessibilityIdentifier("signature-select-\(signature.id)")
                    Button(role: .destructive) { Task {
                        guard await beforeAction?() ?? true else { return }
                        await draft.remove(signature)
                    } } label: {
                        Image(systemName: "trash").frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.signatureDeleteNamed(signature.name))
                    .accessibilityIdentifier("signature-delete-\(signature.id)")
                }
            }
            Button { draft.capturePoints = []; draft.beginDrawing() } label: {
                Label(L10n.signatureNew, systemImage: "signature")
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("signature-new")
        } header: { Text(L10n.signatureSaved) }
          footer: { Text(L10n.signatureHelp).fixedSize(horizontal: false, vertical: true) }
    }

    private var captureSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                TextField(L10n.signatureName, text: $draft.name)
                    .focused($nameFocused)
                    .onSubmit { nameFocused = false }
                    .accessibilityIdentifier("signature-name")
                if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(L10n.signatureNameRequired)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("signature-name-required")
                }
            }
            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color.white)
                    Path { path in
                        path.move(to: CGPoint(x: 16, y: geometry.size.height * 0.72))
                        path.addLine(to: CGPoint(x: geometry.size.width - 16, y: geometry.size.height * 0.72))
                    }.stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                    SignatureInkPreview(strokes: draft.strokes + currentStroke, sourceSize: nil)
                    if draft.strokes.isEmpty && draft.capturePoints.isEmpty {
                        Text(L10n.signatureDrawHint).font(.callout).foregroundStyle(Color.gray)
                            .multilineTextAlignment(.center).padding(20).allowsHitTesting(false)
                    }
                }
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.separator) }
                .contentShape(Rectangle())
                .highPriorityGesture(DragGesture(minimumDistance: 0)
                    .updating($isCapturing) { _, active, _ in active = true }
                    .onChanged { value in
                        let point = InkPoint(x: min(max(value.location.x, 0), geometry.size.width),
                                             y: min(max(value.location.y, 0), geometry.size.height))
                        draft.capturePoints.append(point)
                    }
                    .onEnded { _ in
                        draft.finishCapture()
                    })
                .onChange(of: isCapturing) { _, active in
                    // GestureState resets on cancellation as well as normal lift.
                    if !active { draft.finishCapture() }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.signatureDraw)
                .accessibilityHint(L10n.signatureDrawHint)
                .accessibilityValue(L10n.strokeCount(draft.strokes.count))
                .accessibilityIdentifier("signature-canvas")
            }
            .frame(height: 170)
            Button(L10n.signatureClear) { draft.strokes = []; draft.capturePoints = [] }
                .disabled(draft.strokes.isEmpty && draft.capturePoints.isEmpty)
                .accessibilityIdentifier("signature-clear")
            Button(L10n.signatureSave) {
                guard SubscriptionStore.shared.allowsPremiumOperations else { showPro = true; return }
                nameFocused = false
                Task {
                    guard await beforeAction?() ?? true else { return }
                    await draft.saveReusable()
                }
            }
                .buttonStyle(.borderedProminent)
                .disabled(!draft.canSave)
                .accessibilityIdentifier("signature-save")
        } header: { Text(L10n.signatureDraw) }
    }

    private var currentStroke: [InkStroke] {
        draft.capturedStroke
    }

    private func placementSection(_ signature: SavedSignature) -> some View {
        Section {
            placementPreview(signature).frame(height: 260)
            DisclosureGroup(L10n.signaturePosition) {
                positionSlider(L10n.signatureHorizontal, value: $draft.target.x, range: 0...max(0, 1 - draft.target.width), id: "x")
                positionSlider(L10n.signatureVertical, value: $draft.target.y, range: 0...max(0, 1 - draft.target.height), id: "y")
                positionSlider(L10n.signatureWidth, value: Binding(get: { draft.target.width }, set: { draft.resize(width: $0) }), range: 0.1...1, id: "width")
                positionSlider(L10n.signatureHeight, value: Binding(get: { draft.target.height }, set: { draft.resize(height: $0) }), range: 0.05...1, id: "height")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("signature-position")
        } header: { Text(L10n.signaturePreview) }
          footer: { Text(L10n.signatureDrag).fixedSize(horizontal: false, vertical: true) }
    }

    private func positionSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(verbatim: value.wrappedValue.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit().foregroundStyle(Theme.secondaryText)
            }
            Slider(value: value, in: range)
                .accessibilityLabel(title)
                .accessibilityValue(value.wrappedValue.formatted(.percent.precision(.fractionLength(0))))
                .accessibilityIdentifier("signature-position-\(id)")
        }.padding(.vertical, 4)
    }

    private func placementPreview(_ signature: SavedSignature) -> some View {
        GeometryReader { container in
            let size = draft.page.geometry.pageSize
            let scale = min(container.size.width / size.width, container.size.height / size.height)
            let frame = CGSize(width: size.width * scale, height: size.height * scale)
            let target = draft.target.denormalized(in: frame)
            ZStack(alignment: .topLeading) {
                PageImageView(page: draft.page, pixelSize: 700)
                SignatureInkPreview(strokes: signature.placed(in: draft.target, on: size), sourceSize: size)
                RoundedRectangle(cornerRadius: 4).stroke(Theme.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: target.width, height: target.height)
                    .position(x: target.midX, y: target.midY)
            }
            .frame(width: frame.width, height: frame.height)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { value in
                let x = (value.location.x - (container.size.width - frame.width) / 2) / frame.width
                let y = (value.location.y - (container.size.height - frame.height) / 2) / frame.height
                draft.target.x = min(max(x - draft.target.width / 2, 0), 1 - draft.target.width)
                draft.target.y = min(max(y - draft.target.height / 2, 0), 1 - draft.target.height)
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.signaturePreview)
            .accessibilityHint(L10n.signatureDrag)
            .accessibilityValue(L10n.shapeCoordinates(Int(draft.target.x * 100), Int(draft.target.y * 100),
                Int((draft.target.x + draft.target.width) * 100), Int((draft.target.y + draft.target.height) * 100)))
            .accessibilityIdentifier("signature-preview")
        }
    }
}

private struct SignatureInkPreview: View {
    let strokes: [InkStroke]
    let sourceSize: CGSize?

    var body: some View {
        Canvas { context, size in
            let scale = sourceSize.map { min(size.width / $0.width, size.height / $0.height) } ?? 1
            for stroke in strokes {
                guard let first = stroke.points.first else { continue }
                if stroke.points.count == 1 {
                    let width = stroke.width(at: first) * scale
                    context.fill(Path(ellipseIn: CGRect(x: first.x * scale - width / 2,
                        y: first.y * scale - width / 2, width: width, height: width)), with: .color(stroke.color.swiftUIColor))
                } else {
                    var path = Path()
                    path.move(to: CGPoint(x: first.x * scale, y: first.y * scale))
                    for point in stroke.points.dropFirst() { path.addLine(to: CGPoint(x: point.x * scale, y: point.y * scale)) }
                    context.stroke(path, with: .color(stroke.color.swiftUIColor),
                        style: StrokeStyle(lineWidth: stroke.width * scale, lineCap: .round, lineJoin: .round))
                }
            }
        }.allowsHitTesting(false)
    }
}

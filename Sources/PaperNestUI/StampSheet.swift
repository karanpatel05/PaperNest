import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import PaperNestCore
import PaperNestImport
import PaperNestRender
import PaperNestStore

/// The colours offered for a stamp of one's own words: the presets' four
/// and a grey.
enum StampColor: String, CaseIterable, Identifiable {
    case green, blue, red, purple, gray

    var id: String { rawValue }

    var rgba: RGBAColor {
        switch self {
        case .green: StampPreset.approved.color
        case .blue: StampPreset.received.color
        case .red: StampPreset.rejected.color
        case .purple: StampPreset.draft.color
        case .gray: RGBAColor(red: 0.30, green: 0.32, blue: 0.38)
        }
    }

    var name: String {
        switch self {
        case .green: L10n.colorGreen
        case .blue: L10n.colorBlue
        case .red: L10n.colorRed
        case .purple: L10n.colorPurple
        case .gray: L10n.colorGray
        }
    }
}

/// The stamp being set up in the stamp sheet: a preset, a saved stamp, the
/// person's own words or a saved image, with a date or not, a size and a
/// corner. Nothing is placed until Place; an image is kept when it is added.
@MainActor @Observable
final class StampModel {
    enum Choice: Hashable {
        case preset(StampPreset)
        case saved(SavedStampID)
        case custom
        case picture(SavedPictureStampID)
    }

    let document: DocumentModel
    let page: Page
    var choice: Choice = .preset(.approved)
    var customText = ""
    var customStyle: StampStyle = .outlined
    var customColor: StampColor = .blue
    var includesDate = false
    /// Keep the person's own words in Your Stamps when it is placed.
    var keepsCustom = false
    var size: StampSize = .medium
    var placement: StampPlacement = .topRight
    private(set) var saved: [SavedStamp] = []
    private(set) var pictures: [SavedPictureStamp] = []
    private(set) var thumbnails: [SavedPictureStampID: CGImage] = [:]
    private(set) var isPlacing = false

    init(document: DocumentModel, page: Page) {
        self.document = document
        self.page = page
    }

    private var store: LibraryStore? { document.session.environment?.store }

    func loadSaved() async {
        saved = (try? await store?.savedStamps()) ?? saved
        pictures = (try? await store?.savedPictureStamps()) ?? pictures
        guard let store else { return }
        for picture in pictures where thumbnails[picture.id] == nil {
            let url = store.assets.url(for: picture.assetID, kind: picture.kind)
            thumbnails[picture.id] = await Task.detached(priority: .userInitiated) { Self.thumbnail(of: url) }.value
        }
    }

    /// A small upright picture of a saved image, read from its file.
    nonisolated static func thumbnail(of url: URL, maxPixelSize: Int = 240) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary)
    }

    var chosenPicture: SavedPictureStamp? {
        if case .picture(let id) = choice { return pictures.first { $0.id == id } }
        return nil
    }

    /// Whether Place has something to place.
    var canPlace: Bool { design != nil || chosenPicture != nil }

    /// Keeps an image as a picture stamp and chooses it. Refused unless the
    /// bytes are an image that can be placed. Stamps are markup, so Pro.
    func addPicture(_ data: Data) async throws {
        try SubscriptionStore.shared.require(.markup)
        guard let store else { throw StampSheetError.notKept }
        guard let kind = FileTypeSniffer.kind(of: data), kind.isDrawableImage,
              let size = DocumentModel.pixelSize(of: data), size.width > 0, size.height > 0 else {
            throw StampSheetError.notAnImage
        }
        do {
            let staged = try store.assets.store(data, kind: kind, originalFilename: nil)
            let stamp = try await store.savePictureStamp(staged, pixelSize: size)
            await loadSaved()
            choice = .picture(stamp.id)
        } catch {
            throw StampSheetError.notKept
        }
    }

    /// Deletes a saved image. Copies placed on pages stay.
    func deletePicture(_ stamp: SavedPictureStamp) async {
        do {
            try await store?.deleteSavedPictureStamp(stamp.id)
            if choice == .picture(stamp.id) { choice = .preset(.approved) }
            thumbnails[stamp.id] = nil
            await loadSaved()
        } catch {
            document.presentedError = .saveFailed()
        }
    }

    func choose(_ choice: Choice) {
        self.choice = choice
        // A saved stamp brings its own date setting with it.
        if case .saved(let id) = choice, let stamp = saved.first(where: { $0.id == id }) {
            includesDate = stamp.design.includesDate
        }
    }

    /// What Place would put on the page, or nil when there is nothing to
    /// place (one's own words, none typed yet).
    var design: StampDesign? {
        let design: StampDesign? = switch choice {
        case .preset(let preset):
            StampDesign(text: Self.word(for: preset), style: preset.style, color: preset.color, includesDate: includesDate)
        case .saved(let id):
            saved.first { $0.id == id }.map {
                StampDesign(text: $0.design.text, style: $0.design.style, color: $0.design.color, includesDate: includesDate)
            }
        case .custom:
            StampDesign(text: customText, style: customStyle, color: customColor.rgba, includesDate: includesDate)
        case .picture:
            nil
        }
        return design?.isEmpty == false ? design : nil
    }

    /// Exactly the text box Place writes, for the preview.
    var previewBox: TextBox? {
        design.map { DocumentModel.stampBox($0, size: size, placement: placement, on: page, date: .now) }
    }

    /// Places the stamp, keeping one's own words first when asked. True when
    /// it is on the page. Stamps are markup: a free user is asked to upgrade
    /// before anything is kept or placed.
    func place(undoManager: UndoManager?) async throws -> Bool {
        guard canPlace, !isPlacing else { return false }
        try SubscriptionStore.shared.require(.markup)
        isPlacing = true
        defer { isPlacing = false }
        if let picture = chosenPicture {
            try await document.placePictureStamp(picture, size: size, placement: placement, on: page, undoManager: undoManager)
            return true
        }
        guard let design else { return false }
        if choice == .custom, keepsCustom {
            do { _ = try await store?.saveStamp(design) } catch { throw StampSheetError.notKept }
        }
        try await document.placeStamp(design, size: size, placement: placement, on: page, undoManager: undoManager)
        return true
    }

    /// Deletes a saved stamp. Stamps already placed from it stay on their pages.
    func deleteSaved(_ stamp: SavedStamp) async {
        do {
            try await store?.deleteSavedStamp(stamp.id)
            if choice == .saved(stamp.id) { choice = .preset(.approved) }
            await loadSaved()
        } catch {
            document.presentedError = .saveFailed()
        }
    }

    /// The word a preset stamps, in the reader's language.
    static func word(for preset: StampPreset) -> String {
        switch preset {
        case .approved: L10n.exportWatermarkWordApproved
        case .paid: L10n.textStampWordPaid
        case .received: L10n.textStampWordReceived
        case .reviewed: L10n.textStampWordReviewed
        case .rejected: L10n.textStampWordRejected
        case .draft: L10n.exportWatermarkWordDraft
        case .confidential: L10n.exportWatermarkWordConfidential
        }
    }

    static func name(of size: StampSize) -> String {
        switch size {
        case .small: L10n.textStampSmall
        case .medium: L10n.textStampMedium
        case .large: L10n.textStampLarge
        }
    }

    static func name(of placement: StampPlacement) -> String {
        switch placement {
        case .topRight: L10n.exportWatermarkPlacementTopRight
        case .bottomRight: L10n.exportWatermarkPlacementBottomRight
        case .center: L10n.exportWatermarkPlacementCenter
        }
    }

    static func name(of style: StampStyle) -> String {
        switch style {
        case .outlined: L10n.textStampOutlined
        case .filled: L10n.textStampFilled
        }
    }
}

enum StampSheetError: Error { case notKept, notAnImage }

/// Places a text stamp — Approved, Paid, a saved one or one's own words —
/// on the page as an editable text box. Inline option rows throughout, so
/// French and Spanish are never cut short in a pop-up menu.
struct StampSheet: View {
    @State private var model: StampModel
    @State private var proFeature: ProFeature?
    @State private var failure: String?
    @State private var photo: PhotosPickerItem?
    @State private var isPickingFile = false
    let undoManager: UndoManager?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    init(document: DocumentModel, page: Page, undoManager: UndoManager?) {
        _model = State(initialValue: StampModel(document: document, page: page))
        self.undoManager = undoManager
    }

    var body: some View {
        NavigationStack {
            Form {
                preview
                presets
                if !model.saved.isEmpty { savedStamps }
                custom
                pictures
                options
            }
            .navigationTitle(L10n.textStampTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
            .task { await model.loadSaved() }
            .proPaywall($proFeature)
            .alert(failure ?? "", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button(L10n.ok, role: .cancel) {}
            }
            .task(id: photo) { await addPhoto() }
            .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.image]) { addFile($0) }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 600)
        #endif
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(L10n.cancel) { dismiss() }.accessibilityIdentifier("text-stamp-cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(L10n.textStampPlace) { place() }
                .disabled(!model.canPlace || model.isPlacing)
                .accessibilityIdentifier("text-stamp-place")
        }
    }

    private func place() {
        Task {
            do {
                if try await model.place(undoManager: undoManager) { dismiss() }
            } catch let error as ProAccessError {
                proFeature = error.feature
            } catch StampSheetError.notKept {
                failure = L10n.textStampKeepFailed
            } catch {
                failure = L10n.textStampFailed
            }
        }
    }

    private func addPhoto() async {
        guard let photo else { return }
        defer { self.photo = nil }
        do {
            guard let data = try await photo.loadTransferable(type: Data.self) else { failure = L10n.stampPictureFailed; return }
            try await model.addPicture(data)
        } catch is CancellationError {
        } catch {
            report(error)
        }
    }

    private func addFile(_ result: Result<URL, any Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { failure = L10n.stampPictureFailed; return }
        Task {
            do { try await model.addPicture(data) } catch { report(error) }
        }
    }

    private func report(_ error: any Error) {
        switch error {
        case let error as ProAccessError: proFeature = error.feature
        case StampSheetError.notAnImage: failure = L10n.stampPictureNotImage
        default: failure = L10n.stampPictureFailed
        }
    }

    // MARK: - Sections

    /// The stamp as it will be drawn, by the renderer that draws it on the page.
    private var preview: some View {
        Section {
            HStack {
                Spacer(minLength: 0)
                if let chosen = model.chosenPicture {
                    if let thumbnail = model.thumbnails[chosen.id] {
                        Image(decorative: thumbnail, scale: 1).resizable().scaledToFit().frame(maxWidth: 280, maxHeight: 96)
                    }
                } else if let box = model.previewBox, let picture = picture(of: box) {
                    Image(decorative: picture, scale: displayScale)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280, maxHeight: 96)
                } else {
                    Text(L10n.textStampMissing).font(.app(.callout)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            // Paper is white in dark mode too: a stamp is seen on the page.
            .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.stampPreview)
            .accessibilityValue(previewValue)
            .accessibilityIdentifier("text-stamp-preview")
        }
    }

    private var previewValue: String {
        if let chosen = model.chosenPicture, let index = model.pictures.firstIndex(of: chosen) {
            return L10n.stampPictureRow(index + 1)
        }
        return model.previewBox?.text.replacingOccurrences(of: "\n", with: ", ") ?? L10n.textStampMissing
    }

    private func picture(of box: TextBox) -> CGImage? {
        // Drawn at the size it is shown, so the preview is sharp and light.
        let scale = min(4, 280 / max(1, box.frame.width)) * displayScale
        return try? PageRenderer.stampPicture(box, scale: scale)
    }

    private var presets: some View {
        Section(L10n.textStampPresets) {
            ForEach(StampPreset.allCases, id: \.self) { preset in
                optionRow(StampModel.word(for: preset), selected: model.choice == .preset(preset),
                          id: "text-stamp-preset-\(preset.rawValue)", swatch: preset.color) {
                    model.choose(.preset(preset))
                }
            }
        }
    }

    private var savedStamps: some View {
        Section(L10n.textStampSaved) {
            ForEach(Array(model.saved.enumerated()), id: \.element.id) { index, stamp in
                optionRow(stamp.design.text, selected: model.choice == .saved(stamp.id),
                          id: "text-stamp-saved-\(index + 1)", swatch: stamp.design.color) {
                    model.choose(.saved(stamp.id))
                }
                .swipeActions {
                    Button(L10n.delete, role: .destructive) { Task { await model.deleteSaved(stamp) } }
                }
                .contextMenu {
                    Button(L10n.delete, role: .destructive) { Task { await model.deleteSaved(stamp) } }
                }
            }
        }
    }

    @ViewBuilder
    private var custom: some View {
        Section(L10n.textStampCustom) {
            optionRow(L10n.textStampCustomRow, selected: model.choice == .custom, id: "text-stamp-custom", swatch: nil) {
                model.choose(.custom)
            }
            if model.choice == .custom {
                TextField(L10n.textStampCustomPlaceholder, text: $model.customText)
                    .accessibilityIdentifier("text-stamp-custom-text")
                ForEach(StampStyle.allCases, id: \.self) { style in
                    optionRow(StampModel.name(of: style), selected: model.customStyle == style,
                              id: "text-stamp-style-\(style.rawValue)", swatch: nil) { model.customStyle = style }
                }
                ForEach(StampColor.allCases) { color in
                    optionRow(color.name, selected: model.customColor == color,
                              id: "text-stamp-color-\(color.rawValue)", swatch: color.rgba) { model.customColor = color }
                }
                Toggle(L10n.textStampKeep, isOn: $model.keepsCustom)
                    .accessibilityIdentifier("text-stamp-keep")
            }
        }
    }

    /// Images kept to place again, and adding one from Photos or Files.
    private var pictures: some View {
        Section {
            ForEach(Array(model.pictures.enumerated()), id: \.element.id) { index, picture in
                Button { model.choose(.picture(picture.id)) } label: {
                    HStack(spacing: 12) {
                        Group {
                            if let thumbnail = model.thumbnails[picture.id] {
                                Image(decorative: thumbnail, scale: 1).resizable().scaledToFit()
                            } else {
                                Color.secondary.opacity(0.15)
                            }
                        }
                        .frame(width: 56, height: 40)
                        Text(verbatim: L10n.stampPictureRow(index + 1)).foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        if model.choice == .picture(picture.id) {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("text-stamp-picture-\(index + 1)")
                .accessibilityValue(model.choice == .picture(picture.id) ? L10n.selectionOn : L10n.selectionOff)
                .swipeActions {
                    Button(L10n.delete, role: .destructive) { Task { await model.deletePicture(picture) } }
                }
                .contextMenu {
                    Button(L10n.delete, role: .destructive) { Task { await model.deletePicture(picture) } }
                }
            }
            PhotosPicker(selection: $photo, matching: .images, preferredItemEncoding: .compatible) {
                Label(L10n.stampPictureFromPhotos, systemImage: "photo.on.rectangle")
            }
            .accessibilityIdentifier("text-stamp-add-photo")
            Button { isPickingFile = true } label: {
                Label(L10n.stampPictureFromFiles, systemImage: "folder")
            }
            .accessibilityIdentifier("text-stamp-add-file")
        } header: {
            Text(L10n.stampPictureSection)
        } footer: {
            Text(L10n.stampPictureNote).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var options: some View {
        Section {
            if model.chosenPicture == nil {
                Toggle(L10n.textStampDate, isOn: $model.includesDate)
                    .accessibilityIdentifier("text-stamp-date")
            }
            Text(L10n.textStampSize).font(.app(.headline)).accessibilityAddTraits(.isHeader)
            ForEach(StampSize.allCases, id: \.self) { size in
                optionRow(StampModel.name(of: size), selected: model.size == size,
                          id: "text-stamp-size-\(size.rawValue)", swatch: nil) { model.size = size }
            }
            Text(L10n.textStampPlacement).font(.app(.headline)).accessibilityAddTraits(.isHeader)
            ForEach(StampPlacement.allCases, id: \.self) { placement in
                optionRow(StampModel.name(of: placement), selected: model.placement == placement,
                          id: "text-stamp-placement-\(placement.rawValue)", swatch: nil) { model.placement = placement }
            }
        } footer: {
            Text(L10n.textStampNote).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One choice in a list: its words, a dot of its colour when it has one,
    /// and a tick when chosen.
    private func optionRow(_ title: String, selected: Bool, id: String, swatch: RGBAColor?,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let swatch {
                    Circle().fill(Color(.sRGB, red: swatch.red, green: swatch.green, blue: swatch.blue))
                        .frame(width: 12, height: 12)
                }
                Text(verbatim: title).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityValue(selected ? L10n.selectionOn : L10n.selectionOff)
    }
}

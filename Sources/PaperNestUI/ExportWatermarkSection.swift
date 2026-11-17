import CoreGraphics
import Foundation
import PaperNestCore
import PaperNestExport
import SwiftUI

/// The watermark being set up in the export sheet. It lives as long as the
/// sheet does: closing the sheet forgets it, and nothing about it is stored.
/// Each export turns it into a `Watermark` on that export's options, so Save,
/// Copy and Share all draw the same one.
struct WatermarkDraft: Equatable {
    /// Nil is None, the default.
    private(set) var preset: WatermarkPreset?
    var text = ""
    var placement: WatermarkPlacement = .center
    /// 0…1.
    var opacity = 0.18
    /// Degrees, clockwise on the page.
    var rotation = 0.0
    var includesDate = false

    /// Starts again from `preset`'s own look and words. A switch of preset is
    /// a new watermark, so nothing typed for the last one is carried over.
    mutating func choose(_ preset: WatermarkPreset?) {
        // Tapping the chosen tile again keeps what was typed and set.
        guard preset != self.preset else { return }
        self.preset = preset
        includesDate = false
        guard let preset else { return }
        text = Self.word(for: preset)
        placement = preset.defaultPlacement
        opacity = preset.defaultOpacity
        rotation = preset.defaultRotation
    }

    /// The word a preset stamps, in the reader's language. Custom has none.
    static func word(for preset: WatermarkPreset) -> String {
        switch preset {
        case .confidential: L10n.exportWatermarkWordConfidential
        case .draft: L10n.exportWatermarkWordDraft
        case .approved: L10n.exportWatermarkWordApproved
        case .custom: ""
        }
    }

    /// Why this watermark cannot be exported yet, or nil. A watermark chosen
    /// with no words would export as no watermark at all, which is not what
    /// was asked for.
    var problem: String? {
        guard let preset else { return nil }
        let watermark = Watermark(preset: preset, text: text)
        if watermark.isVisible { return nil }
        // Text, but nothing that draws: a colour emoji has no outline.
        return watermark.drawnText.isEmpty ? L10n.exportWatermarkTextMissing : L10n.exportWatermarkTextUndrawable
    }

    /// What to draw, dated `date` when the date is on. Nil for None.
    func watermark(on date: Date = Date(), locale: Locale = .current) -> Watermark? {
        guard let preset else { return nil }
        let dateLine = includesDate ? date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)) : nil
        return Watermark(preset: preset, text: text, placement: placement, opacity: opacity, rotation: rotation,
                         dateLine: dateLine)
    }

    static func name(of preset: WatermarkPreset?) -> String {
        switch preset {
        case nil: L10n.exportWatermarkNone
        case .confidential: L10n.exportWatermarkConfidential
        case .draft: L10n.exportWatermarkDraft
        case .approved: L10n.exportWatermarkApproved
        case .custom: L10n.exportWatermarkCustom
        }
    }

    static func name(of placement: WatermarkPlacement) -> String {
        switch placement {
        case .center: L10n.exportWatermarkPlacementCenter
        case .topRight: L10n.exportWatermarkPlacementTopRight
        case .bottomRight: L10n.exportWatermarkPlacementBottomRight
        case .tiled: L10n.exportWatermarkPlacementTiled
        }
    }

    static func percent(_ opacity: Double) -> String {
        opacity.formatted(.percent.precision(.fractionLength(0)))
    }

    static func degrees(_ rotation: Double, width: Measurement<UnitAngle>.FormatStyle.UnitWidth) -> String {
        Measurement(value: rotation.rounded(), unit: UnitAngle.degrees)
            .formatted(.measurement(width: width, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    /// What the preview says to VoiceOver and to tests: the preset, where it
    /// is and how strongly it shows, as one sentence in the reader's language.
    var previewDescription: String {
        guard let preset else { return L10n.exportWatermarkNone }
        return L10n.exportWatermarkPreviewValue(Self.name(of: preset), Self.name(of: placement), Self.percent(opacity))
    }
}

/// The export sheet's Watermark section: presets, then — once one is chosen —
/// a live preview of the first page being exported and the controls that
/// shape the mark.
struct ExportWatermarkSection: View {
    @Binding var draft: WatermarkDraft
    /// The first page being exported, drawn in the preview.
    let previewPage: Page?
    /// The paper the export lays pages on: a PDF's choice, or the page's
    /// own size for a picture.
    let paper: PaperSize
    let isPDF: Bool

    private static let presets: [WatermarkPreset?] = [nil, .confidential, .draft, .approved, .custom]

    var body: some View {
        Section {
            ForEach(Array(Self.presets.chunked3().enumerated()), id: \.offset) { _, row in
                WatermarkTileRow {
                    ForEach(row, id: \.self) { preset in
                        ChoiceTile(title: WatermarkDraft.name(of: preset), systemImage: Self.symbol(for: preset),
                                   iconColor: preset.map { Color(watermark: $0.color) } ?? .secondary,
                                   isSelected: draft.preset == preset,
                                   identifier: "export-watermark-\(preset?.rawValue ?? "none")") {
                            draft.choose(preset)
                        }
                        // Said outright, as the design asks: the selected trait
                        // alone was seen to linger on a tile in these rows.
                        .accessibilityValue(draft.preset == preset ? L10n.selectedPage : L10n.selectionOff)
                    }
                }
            }
            if draft.preset != nil { controls }
        } header: {
            Text(L10n.exportWatermarkTitle)
        } footer: {
            if draft.preset != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.exportWatermarkNote)
                    if isPDF { Text(L10n.exportWatermarkPDFNote) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("export-watermark-note")
            }
        }
    }

    @ViewBuilder private var controls: some View {
        WatermarkPreview(page: previewPage, paper: paper, watermark: draft.watermark(),
                         description: draft.previewDescription)
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .listRowBackground(Color.clear)

        VStack(alignment: .leading, spacing: 6) {
            TextField(L10n.exportWatermarkText, text: $draft.text, prompt: Text(L10n.exportWatermarkTextPlaceholder))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .onChange(of: draft.text) { _, typed in
                    if typed.count > Watermark.maxTextLength { draft.text = String(typed.prefix(Watermark.maxTextLength)) }
                }
                .accessibilityLabel(L10n.exportWatermarkText)
                .accessibilityIdentifier("export-watermark-text")
            if let problem = draft.problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("export-watermark-text-missing")
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.exportWatermarkPlacement).font(.subheadline)
            ForEach(Array(WatermarkPlacement.allCases.chunked2().enumerated()), id: \.offset) { _, row in
                WatermarkTileRow(insetRow: false) {
                    ForEach(row, id: \.self) { placement in
                        ChoiceTile(title: WatermarkDraft.name(of: placement), systemImage: Self.symbol(for: placement),
                                   isSelected: draft.placement == placement,
                                   identifier: "export-watermark-placement-\(placement.rawValue)") {
                            draft.placement = placement
                        }
                        .accessibilityValue(draft.placement == placement ? L10n.selectedPage : L10n.selectionOff)
                    }
                }
            }
        }

        LabeledContent {
            Slider(value: $draft.opacity, in: Watermark.opacityRange)
                .frame(minWidth: 140)
                .accessibilityLabel(L10n.exportWatermarkOpacity)
                .accessibilityValue(WatermarkDraft.percent(draft.opacity))
                .accessibilityIdentifier("export-watermark-opacity")
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.exportWatermarkOpacity)
                Text(verbatim: WatermarkDraft.percent(draft.opacity)).font(.caption).foregroundStyle(.secondary)
            }
        }

        LabeledContent {
            Slider(value: $draft.rotation, in: Watermark.rotationRange, step: 1)
                .frame(minWidth: 140)
                .accessibilityLabel(L10n.exportWatermarkRotation)
                .accessibilityValue(WatermarkDraft.degrees(draft.rotation, width: .wide))
                .accessibilityIdentifier("export-watermark-rotation")
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.exportWatermarkRotation)
                Text(verbatim: WatermarkDraft.degrees(draft.rotation, width: .narrow))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }

        Toggle(L10n.exportWatermarkIncludeDate, isOn: $draft.includesDate)
            .accessibilityIdentifier("export-watermark-date")
    }

    static func symbol(for preset: WatermarkPreset?) -> String {
        switch preset {
        case nil: "circle.slash"
        case .confidential: "lock.doc"
        case .draft: "pencil.and.outline"
        case .approved: "checkmark.seal"
        case .custom: "textformat"
        }
    }

    static func symbol(for placement: WatermarkPlacement) -> String {
        switch placement {
        case .center: "rectangle.center.inset.filled"
        case .topRight: "rectangle.inset.topright.filled"
        case .bottomRight: "rectangle.inset.bottomright.filled"
        case .tiled: "square.grid.3x3"
        }
    }
}

/// Tiles side by side, or stacked when their labels do not fit — the export
/// sheet's own rule for its format and page tiles.
private struct WatermarkTileRow<Tiles: View>: View {
    var insetRow = true
    @ViewBuilder let tiles: () -> Tiles
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        #if os(macOS)
        HStack(spacing: 10) { tiles() }
            .fixedSize(horizontal: false, vertical: true)
            .modifier(TileRowInsets(enabled: insetRow))
        #else
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) { tiles() }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { tiles() }
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 8) { tiles() }
                }
            }
        }
        .modifier(TileRowInsets(enabled: insetRow))
        #endif
    }
}

private struct TileRowInsets: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8))
        } else {
            content
        }
    }
}

/// The first page being exported, on its paper, with the watermark drawn by
/// the same function the export uses (`WatermarkDrawing`). Never a picture of
/// what a watermark might look like: this is the export's own drawing.
struct WatermarkPreview: View {
    let page: Page?
    let paper: PaperSize
    let watermark: Watermark?
    let description: String

    @Environment(LibrarySession.self) private var session
    /// The page's picture, with the page and revision it was made from, so
    /// a picture of the last page is never laid out at this page's size.
    @State private var picture: Picture?
    @State private var composed: CGImage?

    private struct Picture {
        let page: PageID
        let revision: Int
        let image: CGImage
    }

    private struct PageKey: Equatable {
        let page: PageID?
        let revision: Int?
    }

    private struct Request: Equatable {
        let page: PageID?
        let revision: Int?
        let paper: PaperSize
        let watermark: Watermark?
        let picturePage: PageID?
        let pictureRevision: Int?
    }

    private var paperSize: CGSize {
        guard let page else { return CGSize(width: 612, height: 792) }
        return PaperLayout(pageSize: page.geometry.pageSize, paper: paper).paperSize
    }

    var body: some View {
        ZStack {
            if let composed {
                Image(decorative: composed, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .shadow(color: Theme.paperShadow, radius: 4, y: 2)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.exportWatermarkPreview)
        .accessibilityValue(description)
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("export-watermark-preview")
        .task(id: PageKey(page: page?.id, revision: page?.revision)) { await loadPage() }
        .task(id: Request(page: page?.id, revision: page?.revision, paper: paper, watermark: watermark,
                          picturePage: picture?.page, pictureRevision: picture?.revision)) {
            await compose()
        }
    }

    private func loadPage() async {
        guard let page, let renderer = session.environment?.renderer else { return }
        if picture?.page != page.id || picture?.revision != page.revision { composed = nil }
        guard let image = try? await session.thumbnails.image(for: page, pixelSize: 520, renderer: renderer),
              !Task.isCancelled else { return }
        picture = Picture(page: page.id, revision: page.revision, image: image)
    }

    /// The page on its paper, then the mark over the paper — where the
    /// export puts it. Off the main actor: a few hundred thousand pixels.
    private func compose() async {
        guard let page, let picture, picture.page == page.id, picture.revision == page.revision else { return }
        let pageImage = picture.image
        let pageSize = page.geometry.pageSize
        let layout = PaperLayout(pageSize: pageSize, paper: paper)
        let watermark = watermark
        let image = await Task.detached(priority: .userInitiated) {
            Self.draw(pageImage, layout: layout, watermark: watermark)
        }.value
        guard !Task.isCancelled else { return }
        composed = image
    }

    nonisolated static func draw(_ pageImage: CGImage, layout: PaperLayout, watermark: Watermark?) -> CGImage? {
        let longest: CGFloat = 520
        let scale = longest / max(layout.paperSize.width, layout.paperSize.height)
        let width = max(1, Int((layout.paperSize.width * scale).rounded()))
        let height = max(1, Int((layout.paperSize.height * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Page space (y-down, points of paper) onto the bitmap (y-up, pixels).
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)
        let content = layout.contentRect
        ctx.saveGState()
        // An image is drawn y-up: flip within its own rectangle.
        ctx.translateBy(x: content.minX, y: content.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(pageImage, in: CGRect(origin: .zero, size: content.size))
        ctx.restoreGState()
        if let watermark { WatermarkDrawing.draw(watermark, pageSize: layout.paperSize, in: ctx) }
        return ctx.makeImage()
    }
}

private extension Color {
    init(watermark color: RGBAColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}

private extension Array {
    func chunked3() -> [[Element]] { chunked(by: 3) }
    func chunked2() -> [[Element]] { chunked(by: 2) }
    func chunked(by size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

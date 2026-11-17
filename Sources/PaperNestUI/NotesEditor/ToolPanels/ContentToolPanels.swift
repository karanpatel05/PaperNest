import PaperNestCore
import SwiftUI

extension TextToolDefaults {
    init(box: TextBox) {
        self.init()
        fontFamily = box.fontFamily
        fontSize = box.fontSize
        color = box.color
        isBold = box.isBold
        isItalic = box.isItalic
        alignment = box.alignment
    }

    func apply(to box: inout TextBox) {
        box.fontFamily = fontFamily
        box.fontSize = fontSize
        box.color = color
        box.isBold = isBold
        box.isItalic = isItalic
        box.alignment = alignment
    }

    /// The PostScript name the page renderer will use for this style, so the
    /// panel's sample is set in the face the page will be.
    var postScriptFontName: String {
        var box = TextBox(frame: .zero, text: "")
        apply(to: &box)
        return box.postScriptFontName
    }
}

/// Type settings for the text box in hand, or for the next one placed.
///
/// With a box selected, every control changes that box — through the inline
/// session, so the change saves and undoes like any other edit to it — and
/// becomes the starting style for the next box as well.
struct TextSettingsPanel: View {
    let store: EditorToolSettingsStore
    let session: InlineTextSession
    let place: () -> Void
    let close: () -> Void

    private var current: TextToolDefaults {
        session.box.map(TextToolDefaults.init(box:)) ?? store.settings.text
    }

    private func apply(_ change: (inout TextToolDefaults) -> Void) {
        var style = current
        change(&style)
        store.update { $0.text = style }
        session.change { style.apply(to: &$0) }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<TextToolDefaults, Value> & Sendable) -> Binding<Value> {
        Binding(get: { current[keyPath: keyPath] }, set: { value in apply { $0[keyPath: keyPath] = value } })
    }

    var body: some View {
        let style = current
        ToolPanelContainer(tool: .text, mode: session.isSelected ? L10n.textSelectedBox : L10n.textNewBoxes,
                           restore: { apply { $0 = TextToolDefaults() } }, close: close) {
            PanelSection(title: L10n.inlineFont) {
                PaperPreviewCard(height: 60) {
                    Text(verbatim: Brand.displayName)
                        .font(.custom(style.postScriptFontName, size: min(style.fontSize * 1.2, 34)))
                        .foregroundStyle(style.color.swiftUIColor)
                        .frame(maxWidth: .infinity,
                               alignment: style.alignment == .center ? .center : style.alignment == .trailing ? .trailing : .leading)
                        .padding(.horizontal, 14)
                        .accessibilityHidden(true)
                }
                PanelSegmented(options: TextBox.FontFamily.allCases.map {
                    .init(value: $0, title: $0.label, id: "text-font-\($0.rawValue)")
                }, selection: binding(\.fontFamily))
                StrokeWidthControl(title: L10n.textBoxSize, value: binding(\.fontSize), range: 8...72, step: 1,
                                   presets: [12, 18, 24, 36], sliderID: "text-size-slider", presetIDPrefix: "text-size")
                HStack(spacing: 8) {
                    styleToggle(L10n.inlineBold, symbol: "bold", isOn: binding(\.isBold), id: "text-bold")
                    styleToggle(L10n.inlineItalic, symbol: "italic", isOn: binding(\.isItalic), id: "text-italic")
                }
            }
            PanelSection(title: L10n.textBoxAlignment) {
                PanelSegmented(options: [
                    .init(value: TextBox.Alignment.leading, title: L10n.textBoxAlignLeft, id: "text-align-leading"),
                    .init(value: TextBox.Alignment.center, title: L10n.textBoxAlignCenter, id: "text-align-center"),
                    .init(value: TextBox.Alignment.trailing, title: L10n.textBoxAlignRight, id: "text-align-trailing"),
                ], selection: binding(\.alignment))
            }
            PanelSection(title: L10n.markupColor) {
                EditorColorPalette(color: binding(\.color), swatches: PaletteSwatch.pen, store: store)
            }
            if !session.isSelected {
                Button { place(); close() } label: {
                    Label { Text(L10n.textPlace) } icon: { Image(systemName: "plus") }
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(Color.white)
                        .background(EditorChrome.selection, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("text-place")
            }
        }
    }

    private func styleToggle(_ title: String, symbol: String, isOn: Binding<Bool>, id: String) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Label { Text(verbatim: title) } icon: { Image(systemName: symbol) }
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(isOn.wrappedValue ? Color.white : EditorChrome.navy)
                .background {
                    let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                    if isOn.wrappedValue { shape.fill(EditorChrome.selection) } else { shape.fill(EditorChrome.lavender) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn.wrappedValue ? L10n.selectionOn : L10n.selectionOff)
        .accessibilityIdentifier(id)
    }
}

/// Where a picture can come from. Each closure closes the panel itself once
/// it has started the picker, which has to be on screen alone.
struct ImageToolActions {
    var photos: () -> Void
    var files: () -> Void
    /// Nil where there is no camera to offer (the Mac).
    var camera: (() -> Void)?
    var cameraSupported = false
}

struct ImageSettingsPanel: View {
    let actions: ImageToolActions
    let close: () -> Void

    var body: some View {
        ToolPanelContainer(tool: .image, close: close) {
            PanelSection(title: L10n.insertImage) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: actions.camera == nil ? 2 : 3),
                          spacing: 8) {
                    PanelTile(title: L10n.importPhotos, systemImage: "photo.on.rectangle", id: "editor-image-photos",
                              action: actions.photos)
                    if let camera = actions.camera {
                        PanelTile(title: L10n.takePhoto, systemImage: "camera", id: "editor-image-camera", action: camera)
                            .disabled(!actions.cameraSupported)
                            .accessibilityValue(actions.cameraSupported ? L10n.takePhoto : L10n.scanUnsupported)
                    }
                    PanelTile(title: L10n.importFiles, systemImage: "folder", id: "editor-image-files",
                              action: actions.files)
                }
            }
            PanelSection(title: L10n.imageOnPage) {
                PanelNote(text: L10n.imageOnPageDetail)
            }
        }
    }
}

/// Sticker bitmaps for the grid, drawn once each.
@MainActor
enum StickerThumbnails {
    private static var cache: [String: CGImage] = [:]

    static func image(for sticker: Sticker) -> CGImage? {
        if let cached = cache[sticker.id] { return cached }
        let image = StickerLibrary.image(for: sticker, pixels: 160)
        cache[sticker.id] = image
        return image
    }
}

struct StickerSettingsPanel: View {
    let store: EditorToolSettingsStore
    let insert: (Sticker) -> Void
    let close: () -> Void
    @State private var query = ""
    @State private var filter: Filter = .all

    enum Filter: Hashable {
        case all, favorites
        case category(StickerCategory)

        var title: String {
            switch self {
            case .all: L10n.stickerAll
            case .favorites: L10n.colorFavorites
            case .category(let category): category.title
            }
        }

        var id: String {
            switch self {
            case .all: "all"
            case .favorites: "favorites"
            case .category(let category): category.rawValue
            }
        }
    }

    private var filters: [Filter] { [.all, .favorites] + StickerCategory.allCases.map(Filter.category) }

    private var shown: [Sticker] {
        let favorites = store.settings.favoriteStickers
        let pool: [Sticker]
        switch filter {
        case .all: pool = StickerLibrary.all
        case .favorites: pool = StickerLibrary.all.filter { favorites.contains($0.id) }
        case .category(let category): pool = StickerLibrary.all.filter { $0.category == category }
        }
        return StickerLibrary.search(query, in: pool)
    }

    var body: some View {
        let recents = store.settings.recentStickers.compactMap(StickerLibrary.sticker)
        ToolPanelContainer(tool: .sticker, mode: filter.title, close: close) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(EditorChrome.secondaryText).accessibilityHidden(true)
                TextField(L10n.stickerSearch, text: $query)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("sticker-search")
            }
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(EditorChrome.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(EditorChrome.border, lineWidth: 0.75)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(filters, id: \.self) { candidate in
                        let selected = candidate == filter
                        Button { filter = candidate } label: {
                            Text(verbatim: candidate.title)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14).frame(minHeight: 36)
                                .foregroundStyle(selected ? Color.white : EditorChrome.navy)
                                .background {
                                    if selected { Capsule().fill(EditorChrome.selection) }
                                    else { Capsule().fill(EditorChrome.lavender) }
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(selected ? L10n.selectionOn : L10n.selectionOff)
                        .accessibilityIdentifier("sticker-filter-\(candidate.id)")
                    }
                }
            }
            if filter == .all, query.isEmpty, !recents.isEmpty {
                PanelSection(title: L10n.colorRecent) { grid(recents, prefix: "sticker-recent") }
            }
            PanelSection(title: filter.title) {
                if shown.isEmpty {
                    PanelNote(text: filter == .favorites && query.isEmpty ? L10n.stickerNoFavorites : L10n.stickerNoMatches)
                } else {
                    grid(shown, prefix: "sticker")
                }
            }
            PanelNote(text: L10n.stickerHint)
        }
    }

    private func grid(_ stickers: [Sticker], prefix: String) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 6)], spacing: 6) {
            ForEach(stickers) { sticker in
                let favorite = store.settings.favoriteStickers.contains(sticker.id)
                let toggleTitle = favorite ? L10n.colorRemoveFavorite : L10n.colorAddFavorite
                Button { insert(sticker) } label: {
                    Group {
                        if let image = StickerThumbnails.image(for: sticker) {
                            Image(decorative: image, scale: 1).resizable().scaledToFit()
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 44, height: 44)
                    .frame(minWidth: 60, minHeight: 60)
                    .background(EditorChrome.secondaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if favorite {
                            Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(EditorChrome.purple)
                                .padding(5)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { store.update { $0.toggleFavoriteSticker(sticker.id) } } label: {
                        Label { Text(verbatim: toggleTitle) } icon: { Image(systemName: favorite ? "star.slash" : "star") }
                    }
                }
                .accessibilityLabel(sticker.name)
                .accessibilityValue(favorite ? L10n.colorFavorites : "")
                .accessibilityAction(named: Text(verbatim: toggleTitle)) {
                    store.update { $0.toggleFavoriteSticker(sticker.id) }
                }
                .accessibilityIdentifier("\(prefix)-\(sticker.id)")
            }
        }
    }
}

/// Everything the Insert tool can add. A nil action is one this document or
/// this device cannot do, and its tile is left out rather than greyed.
struct InsertToolActions {
    var addPage: ((PageTemplate) -> Void)?
    var importPages: () -> Void
    var textBox: () -> Void
    var image: () -> Void
    var dateAndTime: () -> Void
    var divider: () -> Void
    var duplicatePage: () -> Void
    var organizePages: () -> Void
}

/// A small sheet of paper showing a page template's ruling.
struct PageTemplateGlyph: View {
    let template: PageTemplate

    var body: some View {
        Canvas { context, size in
            let page = CGRect(x: (size.width - size.height * 0.74) / 2, y: 1, width: size.height * 0.74, height: size.height - 2)
            let sheet = Path(roundedRect: page, cornerRadius: 3)
            context.fill(sheet, with: .color(.white))
            var ruling = Path()
            switch template {
            case .blank: break
            case .lined:
                for row in 1...5 {
                    let y = page.minY + page.height * Double(row) / 6
                    ruling.move(to: CGPoint(x: page.minX + 3, y: y)); ruling.addLine(to: CGPoint(x: page.maxX - 3, y: y))
                }
            case .grid:
                for row in 1...5 {
                    let y = page.minY + page.height * Double(row) / 6
                    ruling.move(to: CGPoint(x: page.minX, y: y)); ruling.addLine(to: CGPoint(x: page.maxX, y: y))
                }
                for column in 1...3 {
                    let x = page.minX + page.width * Double(column) / 4
                    ruling.move(to: CGPoint(x: x, y: page.minY)); ruling.addLine(to: CGPoint(x: x, y: page.maxY))
                }
            case .dotted:
                for row in 1...5 {
                    for column in 1...3 {
                        let dot = CGPoint(x: page.minX + page.width * Double(column) / 4, y: page.minY + page.height * Double(row) / 6)
                        ruling.addEllipse(in: CGRect(x: dot.x - 0.9, y: dot.y - 0.9, width: 1.8, height: 1.8))
                    }
                }
            case .cornell:
                let cue = page.minX + page.width * 0.32, top = page.minY + page.height * 0.18, foot = page.minY + page.height * 0.78
                line(&ruling, page.minX, page.maxX, top)
                ruling.move(to: CGPoint(x: cue, y: top)); ruling.addLine(to: CGPoint(x: cue, y: foot))
                line(&ruling, page.minX, page.maxX, foot)
                for row in 1...3 { line(&ruling, cue + 2, page.maxX - 3, top + (foot - top) * Double(row) / 4) }
            case .checklist:
                for row in 1...4 { checkRow(&ruling, page, page.minY + page.height * Double(row) / 5) }
            case .meeting:
                line(&ruling, page.minX + 3, page.maxX - 3, page.minY + page.height * 0.16)
                line(&ruling, page.minX + 3, page.midX - 2, page.minY + page.height * 0.3)
                line(&ruling, page.midX + 2, page.maxX - 3, page.minY + page.height * 0.3)
                line(&ruling, page.minX + 3, page.maxX - 3, page.minY + page.height * 0.45)
                line(&ruling, page.minX + 3, page.maxX - 3, page.minY + page.height * 0.57)
                checkRow(&ruling, page, page.minY + page.height * 0.74)
                checkRow(&ruling, page, page.minY + page.height * 0.88)
            case .planner:
                let cellWidth = (page.width - 6) / 2, cellHeight = (page.height - 9) / 4
                for index in 0..<8 {
                    ruling.addRect(CGRect(x: page.minX + 2 + Double(index % 2) * (cellWidth + 2),
                                          y: page.minY + 2 + Double(index / 2) * (cellHeight + 1.5),
                                          width: cellWidth, height: cellHeight))
                }
            case .form:
                for row in 1...5 {
                    let y = page.minY + page.height * Double(row) / 6
                    line(&ruling, page.minX + 3, page.minX + page.width * 0.35, y)
                    line(&ruling, page.minX + page.width * 0.42, page.maxX - 3, y)
                }
            }
            context.stroke(ruling, with: .color(EditorChrome.purple.opacity(0.45)), lineWidth: 0.75)
            context.stroke(sheet, with: .color(EditorChrome.border), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private func line(_ path: inout Path, _ x0: Double, _ x1: Double, _ y: Double) {
        path.move(to: CGPoint(x: x0, y: y)); path.addLine(to: CGPoint(x: x1, y: y))
    }

    private func checkRow(_ path: inout Path, _ page: CGRect, _ y: Double) {
        path.addRect(CGRect(x: page.minX + 3, y: y - 3, width: 3, height: 3))
        line(&path, page.minX + 8, page.maxX - 3, y)
    }
}

struct InsertSettingsPanel: View {
    let actions: InsertToolActions
    let close: () -> Void

    var body: some View {
        ToolPanelContainer(tool: .insert, close: close) {
            if let addPage = actions.addPage {
                PanelSection(title: L10n.addNotebookPage) {
                    // One row that scrolls sideways: nine papers in a grid
                    // pushed the panel's other tools below the fold.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(PageTemplate.allCases, id: \.self) { template in
                                ToolPresetCard(title: template.notebookTitle, selected: false,
                                               id: "insert-page-\(template.rawValue)") {
                                    addPage(template)
                                } preview: {
                                    PageTemplateGlyph(template: template)
                                }
                                .frame(width: 96)
                            }
                        }
                    }
                    .accessibilityIdentifier("insert-page-papers")
                    PanelNote(text: L10n.insertPageDetail)
                }
            }
            PanelSection(title: L10n.insertOnPage) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    PanelTile(title: L10n.textBox, systemImage: "character.textbox", id: "insert-text-box",
                              action: actions.textBox)
                    PanelTile(title: L10n.insertImage, systemImage: "photo", id: "insert-image", action: actions.image)
                    PanelTile(title: L10n.insertDateTime, systemImage: "calendar.badge.clock", id: "insert-date-time",
                              action: actions.dateAndTime)
                    PanelTile(title: L10n.insertDivider, systemImage: "minus", id: "insert-divider",
                              action: actions.divider)
                }
            }
            PanelSection(title: L10n.pages) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    PanelTile(title: L10n.insertFromFiles, systemImage: "doc.badge.plus", id: "insert-import-pages",
                              action: actions.importPages)
                    PanelTile(title: L10n.insertDuplicatePage, systemImage: "plus.square.on.square",
                              id: "insert-duplicate-page", action: actions.duplicatePage)
                    PanelTile(title: L10n.insertOrganize, systemImage: "square.grid.2x2", id: "insert-organize-pages",
                              action: actions.organizePages)
                }
            }
        }
    }
}

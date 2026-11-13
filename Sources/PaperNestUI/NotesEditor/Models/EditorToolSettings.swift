import Foundation
import Observation
import PaperNestCore

/// The tools on the notes editor's main toolbar, in the order it shows them.
enum EditorTool: String, CaseIterable, Identifiable, Sendable {
    case pen, highlighter, eraser, lasso, shape, text, image, sticker, insert

    var id: String { rawValue }

    /// The drawing mode this tool arms on the page. Text, Image, Sticker and
    /// Insert place things rather than draw them, so they arm nothing.
    var markupTool: MacMarkupTool? {
        switch self {
        case .pen: .pen
        case .highlighter: .highlighter
        case .eraser: .eraser
        case .lasso: .lasso
        case .shape: .shape
        case .text, .image, .sticker, .insert: nil
        }
    }

    var title: String {
        switch self {
        case .pen: L10n.inkPen
        case .highlighter: L10n.inkHighlighter
        case .eraser: L10n.inkEraser
        case .lasso: L10n.inkLasso
        case .shape: L10n.toolShapes
        case .text: L10n.toolText
        case .image: L10n.toolImage
        case .sticker: L10n.toolSticker
        case .insert: L10n.toolInsert
        }
    }
}

/// A highlighter is chosen by what it is for, not by a row of numbers.
///
/// Each style is a starting width, strength and tip; the sliders then tune
/// that style and the tuning is remembered for it alone.
enum HighlighterStyle: String, Codable, CaseIterable, Sendable {
    /// Round-tipped band behind a line of text.
    case standard
    /// The same band with square ends, like a chisel tip drawn flat.
    case flat
    /// A thin, stronger line for under the words.
    case underline
    /// A broad freehand marker.
    case marker
    /// Always drawn dead straight from where it starts to where it ends.
    case straight

    var defaultWidth: Double {
        switch self {
        case .standard, .flat, .straight: 20
        case .underline: 4
        case .marker: 30
        }
    }

    /// Highlighter ink is always drawn translucent and multiplied onto the
    /// page (`InkStroke.highlighterOpacity`), which is what keeps text under
    /// it readable. This is the user's share of that, 0.1...1.
    var defaultStrength: Double {
        switch self {
        case .standard, .flat, .straight: 0.8
        case .underline, .marker: 1
        }
    }

    var cap: InkStroke.Cap? { self == .flat ? .flat : nil }
    var straightens: Bool { self == .straight || self == .underline }
}

/// What the eraser is allowed to touch.
enum EraserTarget: String, Codable, CaseIterable, Sendable {
    case all, handwriting, highlights

    func allows(_ ink: InkStroke) -> Bool {
        switch self {
        case .all: true
        case .handwriting: ink.tool == .pen
        case .highlights: ink.tool == .highlighter
        }
    }

    /// The ink on a page this eraser may remove. Text boxes, placed images
    /// and the page itself are never in the answer: the eraser only ever
    /// receives ink, which is how an imported PDF behind the page stays safe
    /// whatever the eraser is dragged across.
    func erasable(in objects: [PageObject]) -> [PageObject] {
        objects.filter { object in
            if case .ink(let ink) = object.payload { return allows(ink) }
            return false
        }
    }
}

/// What a lasso loop is allowed to pick up.
enum LassoContent: String, Codable, CaseIterable, Sendable {
    case handwriting, highlights, textBoxes, images

    static func kind(of object: PageObject) -> LassoContent? {
        switch object.payload {
        case .ink(let ink): ink.tool == .highlighter ? .highlights : .handwriting
        case .text: .textBoxes
        case .image: .images
        case .comment: nil
        }
    }
}

extension InkEraserMode: Codable {}
extension PageSelectionMode: Codable {}

/// One pen's own width and colour. The colour's alpha is its opacity.
struct PenSetting: Codable, Equatable, Sendable {
    var width: Double
    var color: RGBAColor

    init(preset: PenPreset) {
        width = preset.defaultWidth
        color = RGBAColor(red: 0, green: 0, blue: 0, alpha: preset.defaultOpacity)
    }
}

struct HighlighterSetting: Codable, Equatable, Sendable {
    var width: Double
    var strength: Double

    init(style: HighlighterStyle) {
        width = style.defaultWidth
        strength = style.defaultStrength
    }
}

struct TextToolDefaults: Codable, Equatable, Sendable {
    var fontFamily: TextBox.FontFamily = .sans
    var fontSize: Double = 18
    var color: RGBAColor = .black
    var isBold = false
    var isItalic = false
    var alignment: TextBox.Alignment = .leading
}

/// Everything the toolbar remembers between sessions.
///
/// This is a preference about the *tools*, not about any document, which is
/// why it lives in `UserDefaults` and not in `LibraryStore`: nothing here is
/// metadata of a page, and a document opened on another device should not
/// change which pen is in the hand.
struct EditorToolSettings: Codable, Equatable, Sendable {
    static let recentColorLimit = 8
    static let favoriteColorLimit = 10
    static let recentStickerLimit = 12

    var penPreset: PenPreset = .gel
    /// Keyed by `PenPreset.rawValue`. A dictionary keyed by the enum itself
    /// encodes as an array of alternating keys and values, which no later
    /// version could add a pen to without breaking what was saved.
    private var pens: [String: PenSetting] = [:]
    var usesPressure = true
    /// 0...1. Only the Mac canvas shapes its own strokes; see `PenSettingsPanel`.
    var smoothing = 0.5
    /// Pause at the end of a stroke to turn it into a clean line or shape.
    var snapsOnHold = true

    var highlighterStyle: HighlighterStyle = .standard
    private var highlighters: [String: HighlighterSetting] = [:]
    var highlighterColor = RGBAColor(red: 1, green: 0.82, blue: 0)

    var eraserMode: InkEraserMode = .precision
    var eraserSize = 36.0
    var eraserTarget: EraserTarget = .all

    var lassoMode: PageSelectionMode = .freehand
    var lassoContent: Set<LassoContent> = Set(LassoContent.allCases)

    private var shapeKindName = ShapeAnnotation.rectangle.rawValue
    var shapeWidth = 2.0
    var shapeColor = RGBAColor(red: 0.1, green: 0.3, blue: 0.9)
    /// Holds a dragged shape to a square box: a circle, not an oval.
    var shapeLocksAspect = false

    var text = TextToolDefaults()

    var recentColors: [RGBAColor] = []
    var favoriteColors: [RGBAColor] = []
    var recentStickers: [String] = []
    var favoriteStickers: [String] = []

    init() {}

    // Every key is optional on the way in. A settings blob written by an
    // older build is missing whatever has been added since, and failing the
    // whole decode over one absent key would silently hand the user factory
    // defaults for everything they had set up.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? values.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        let fresh = EditorToolSettings()
        penPreset = read(.penPreset, fresh.penPreset)
        pens = read(.pens, fresh.pens)
        usesPressure = read(.usesPressure, fresh.usesPressure)
        smoothing = min(max(read(.smoothing, fresh.smoothing), 0), 1)
        snapsOnHold = read(.snapsOnHold, fresh.snapsOnHold)
        highlighterStyle = read(.highlighterStyle, fresh.highlighterStyle)
        highlighters = read(.highlighters, fresh.highlighters)
        highlighterColor = read(.highlighterColor, fresh.highlighterColor)
        eraserMode = read(.eraserMode, fresh.eraserMode)
        eraserSize = min(max(read(.eraserSize, fresh.eraserSize), 8), 64)
        eraserTarget = read(.eraserTarget, fresh.eraserTarget)
        lassoMode = read(.lassoMode, fresh.lassoMode)
        lassoContent = read(.lassoContent, fresh.lassoContent)
        shapeKindName = read(.shapeKindName, fresh.shapeKindName)
        shapeWidth = min(max(read(.shapeWidth, fresh.shapeWidth), 0.5), 20)
        shapeColor = read(.shapeColor, fresh.shapeColor)
        shapeLocksAspect = read(.shapeLocksAspect, fresh.shapeLocksAspect)
        text = read(.text, fresh.text)
        recentColors = read(.recentColors, fresh.recentColors)
        favoriteColors = read(.favoriteColors, fresh.favoriteColors)
        recentStickers = read(.recentStickers, fresh.recentStickers)
        favoriteStickers = read(.favoriteStickers, fresh.favoriteStickers)
    }

    // MARK: Pens

    func pen(_ preset: PenPreset) -> PenSetting {
        var setting = pens[preset.rawValue] ?? PenSetting(preset: preset)
        setting.width = min(max(setting.width, preset.widthRange.lowerBound), preset.widthRange.upperBound)
        setting.color.alpha = min(max(setting.color.alpha, 0.1), 1)
        return setting
    }

    mutating func setPen(_ setting: PenSetting, for preset: PenPreset) {
        pens[preset.rawValue] = setting
    }

    var currentPen: PenSetting {
        get { pen(penPreset) }
        set { setPen(newValue, for: penPreset) }
    }

    // MARK: Highlighters

    func highlighter(_ style: HighlighterStyle) -> HighlighterSetting {
        var setting = highlighters[style.rawValue] ?? HighlighterSetting(style: style)
        setting.width = min(max(setting.width, 2), 40)
        setting.strength = min(max(setting.strength, 0.1), 1)
        return setting
    }

    mutating func setHighlighter(_ setting: HighlighterSetting, for style: HighlighterStyle) {
        highlighters[style.rawValue] = setting
    }

    var currentHighlighter: HighlighterSetting {
        get { highlighter(highlighterStyle) }
        set { setHighlighter(newValue, for: highlighterStyle) }
    }

    /// The highlighter colour as it is handed to the canvas: the chosen hue
    /// at the current style's strength.
    var highlighterInk: RGBAColor {
        var color = highlighterColor
        color.alpha = currentHighlighter.strength
        return color
    }

    // MARK: Shapes

    var shapeKind: ShapeAnnotation {
        get { ShapeAnnotation(rawValue: shapeKindName) ?? .rectangle }
        set { shapeKindName = newValue.rawValue }
    }

    // MARK: What the canvases read

    /// Width in source points for the armed drawing tool.
    func width(for tool: MacMarkupTool) -> Double {
        switch tool {
        case .pen: currentPen.width
        case .highlighter: currentHighlighter.width
        case .eraser: eraserSize
        case .shape: shapeWidth
        case .lasso: 0
        }
    }

    func color(for tool: MacMarkupTool) -> RGBAColor {
        switch tool {
        case .pen: currentPen.color
        case .highlighter: highlighterInk
        case .shape: shapeColor
        case .eraser, .lasso: .black
        }
    }

    // MARK: Colour and sticker history

    /// Moves a colour to the front of the recents. Compared without alpha:
    /// the same blue at two opacities is one colour in a palette.
    mutating func noteColorUsed(_ color: RGBAColor) {
        var opaque = color
        opaque.alpha = 1
        recentColors.removeAll { $0 == opaque }
        recentColors.insert(opaque, at: 0)
        if recentColors.count > Self.recentColorLimit { recentColors.removeLast(recentColors.count - Self.recentColorLimit) }
    }

    func isFavorite(_ color: RGBAColor) -> Bool {
        var opaque = color
        opaque.alpha = 1
        return favoriteColors.contains(opaque)
    }

    mutating func toggleFavorite(_ color: RGBAColor) {
        var opaque = color
        opaque.alpha = 1
        if let index = favoriteColors.firstIndex(of: opaque) {
            favoriteColors.remove(at: index)
        } else if favoriteColors.count < Self.favoriteColorLimit {
            favoriteColors.append(opaque)
        }
    }

    mutating func noteStickerUsed(_ id: String) {
        recentStickers.removeAll { $0 == id }
        recentStickers.insert(id, at: 0)
        if recentStickers.count > Self.recentStickerLimit {
            recentStickers.removeLast(recentStickers.count - Self.recentStickerLimit)
        }
    }

    mutating func toggleFavoriteSticker(_ id: String) {
        if let index = favoriteStickers.firstIndex(of: id) { favoriteStickers.remove(at: index) }
        else { favoriteStickers.append(id) }
    }

    /// Puts one tool back to how it ships, leaving every other tool — and the
    /// colour history, which belongs to all of them — alone.
    mutating func restoreDefaults(for tool: EditorTool) {
        let fresh = EditorToolSettings()
        switch tool {
        case .pen:
            pens[penPreset.rawValue] = nil
            usesPressure = fresh.usesPressure
            smoothing = fresh.smoothing
            snapsOnHold = fresh.snapsOnHold
        case .highlighter:
            highlighters[highlighterStyle.rawValue] = nil
            highlighterColor = fresh.highlighterColor
        case .eraser:
            eraserMode = fresh.eraserMode
            eraserSize = fresh.eraserSize
            eraserTarget = fresh.eraserTarget
        case .lasso:
            lassoMode = fresh.lassoMode
            lassoContent = fresh.lassoContent
        case .shape:
            shapeKindName = fresh.shapeKindName
            shapeWidth = fresh.shapeWidth
            shapeColor = fresh.shapeColor
            shapeLocksAspect = fresh.shapeLocksAspect
        case .text:
            text = fresh.text
        case .image, .sticker, .insert:
            break
        }
    }
}

/// Holds the toolbar's settings and writes every change through to disk.
///
/// A change is saved before the setter returns, so a tool never looks set up
/// in a way that would not survive the app being closed a moment later.
@MainActor @Observable
final class EditorToolSettingsStore {
    static let key = "notesEditor.toolSettings.v1"
    static let shared = EditorToolSettingsStore(defaults: standardStorage())

    private(set) var settings: EditorToolSettings
    @ObservationIgnored private let defaults: UserDefaults?

    /// `defaults: nil` keeps settings in memory only.
    init(defaults: UserDefaults?) {
        self.defaults = defaults
        settings = Self.load(from: defaults)
    }

    /// Where the running app keeps its settings.
    ///
    /// A launch pointed at a throwaway library — every UI test and every
    /// `run-mac-app.sh` session — starts from the shipped tools and writes
    /// nothing, so one test's thick red pen cannot become the next test's
    /// starting state. `-PaperNestDebugPersistToolSettings YES` opts back in
    /// for a test that is about persistence itself.
    static func standardStorage(_ defaults: UserDefaults = .standard) -> UserDefaults? {
        let throwaway = !(defaults.string(forKey: "PaperNestLibraryPath") ?? "").isEmpty
            || defaults.string(forKey: "PaperNestDebugTemporaryLibrary") != nil
        if throwaway && !defaults.bool(forKey: "PaperNestDebugPersistToolSettings") { return nil }
        return defaults
    }

    static func load(from defaults: UserDefaults?) -> EditorToolSettings {
        guard let data = defaults?.data(forKey: key),
              let stored = try? JSONDecoder().decode(EditorToolSettings.self, from: data) else {
            return EditorToolSettings()
        }
        return stored
    }

    func update(_ change: (inout EditorToolSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        if let defaults, let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: Self.key)
        }
        settings = next
    }
}

/// How the armed drawing tool should shape and save what is drawn: the part
/// of the settings a canvas needs, and nothing it does not.
struct InkDrawingStyle: Equatable, Sendable {
    var preset: PenPreset = .gel
    var usesPressure = true
    var smoothing = 0.0
    var snapsOnHold = false
    var cap: InkStroke.Cap?
    /// Every stroke is saved as the straight line between its two ends.
    var straightens = false
    var eraserTarget: EraserTarget = .all
}

extension EditorToolSettings {
    func drawingStyle(for tool: MacMarkupTool) -> InkDrawingStyle {
        var style = InkDrawingStyle(preset: penPreset, usesPressure: usesPressure, smoothing: smoothing,
                                    snapsOnHold: snapsOnHold, eraserTarget: eraserTarget)
        if tool == .highlighter {
            style.cap = highlighterStyle.cap
            style.straightens = highlighterStyle.straightens
            // A highlighter has no pen preset; it is one even band.
            style.preset = .marker
            style.smoothing = 0
        }
        return style
    }
}

extension InkDrawingStyle {
    /// One freehand drag as the stroke to save, in the samples' own space.
    ///
    /// `endTime` is when the pointer lifted, on the samples' clock; `grip` is
    /// how far it may wander while still counting as resting, in the same
    /// units as the samples. Nil only when there is nothing to save.
    func stroke(from samples: [PenSample], endTime: Double, grip: Double, tool: InkStroke.Tool,
                color: RGBAColor, width: Double) -> InkStroke? {
        guard !samples.isEmpty else { return nil }
        let path = samples.map { CGPoint(x: $0.x, y: $0.y) }
        var snapped: SnappedShape?
        if straightens {
            snapped = StrokeSnapping.line(path)
        } else if snapsOnHold,
                  StrokeSnapping.dwell(samples, endTime: endTime, radius: grip) >= StrokeSnapping.holdDuration {
            snapped = StrokeSnapping.recognize(path)
        }
        if let snapped {
            return InkStroke(tool: tool, color: color, width: width,
                             points: snapped.outline.map { InkPoint(x: $0.x, y: $0.y) }, cap: cap)
        }
        if tool == .highlighter {
            return InkStroke(tool: tool, color: color, width: width,
                             points: samples.map { InkPoint(x: $0.x, y: $0.y, time: $0.time) }, cap: cap)
        }
        let smoothed = StrokeSmoothing.smooth(samples, amount: smoothing)
        return InkStroke(tool: tool, color: color, width: width,
                         points: PenDynamics.points(from: smoothed, preset: preset, usesPressure: usesPressure))
    }
}

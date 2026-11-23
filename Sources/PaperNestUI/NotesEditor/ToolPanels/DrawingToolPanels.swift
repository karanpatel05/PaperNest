import PaperNestCore
import SwiftUI

extension EditorToolSettingsStore {
    /// A binding that writes through `update`, so every control in a panel
    /// saves as it is moved.
    func binding<Value>(_ keyPath: WritableKeyPath<EditorToolSettings, Value> & Sendable) -> Binding<Value> {
        Binding(get: { self.settings[keyPath: keyPath] },
                set: { value in self.update { $0[keyPath: keyPath] = value } })
    }
}

extension PenPreset {
    var title: String {
        switch self {
        case .fountain: L10n.penFountain
        case .ballpoint: L10n.penBallpoint
        case .gel: L10n.penGel
        case .pencil: L10n.penPencil
        case .marker: L10n.penMarker
        case .brush: L10n.penBrush
        }
    }

    /// Dots to jump to, spread across this pen's own range.
    var widthPresets: [Double] {
        switch self {
        case .marker, .brush: [1, 3, 5, 8, 12]
        case .fountain, .ballpoint, .gel, .pencil: [0.5, 1, 2, 4, 8]
        }
    }
}

extension HighlighterStyle {
    var title: String {
        switch self {
        case .standard: L10n.highlighterStandard
        case .flat: L10n.highlighterFlat
        case .underline: L10n.highlighterUnderline
        case .marker: L10n.highlighterMarker
        case .straight: L10n.highlighterStraight
        }
    }
}

/// "Draw with finger", where a finger can draw at all.
struct FingerDrawingRow: View {
    @Binding var isOn: Bool

    var body: some View {
        #if os(iOS)
        PanelToggleRow(title: L10n.drawWithFinger, systemImage: "hand.draw", isOn: $isOn,
                       id: "studio-finger-drawing", detail: L10n.toolFingerDetail)
        #endif
    }
}

struct PenSettingsPanel: View {
    let store: EditorToolSettingsStore
    @Binding var fingerDrawing: Bool
    let close: () -> Void

    private var width: Binding<Double> {
        Binding(get: { store.settings.currentPen.width }, set: { value in store.update { $0.currentPen.width = value } })
    }

    private var opacity: Binding<Double> {
        Binding(get: { store.settings.currentPen.color.alpha },
                set: { value in store.update { $0.currentPen.color.alpha = value } })
    }

    private var color: Binding<RGBAColor> {
        Binding(get: { store.settings.currentPen.color }, set: { value in
            store.update {
                var next = value
                next.alpha = $0.currentPen.color.alpha
                $0.currentPen.color = next
            }
        })
    }

    var body: some View {
        let settings = store.settings
        let preset = settings.penPreset
        let pen = settings.currentPen
        ToolPanelContainer(tool: .pen, mode: preset.title,
                           restore: { store.update { $0.restoreDefaults(for: .pen) } }, close: close) {
            PanelSection(title: L10n.penType) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(PenPreset.allCases, id: \.self) { candidate in
                        let own = settings.pen(candidate)
                        ToolPresetCard(title: candidate.title, selected: candidate == preset,
                                       id: "pen-preset-\(candidate.rawValue)") {
                            store.update { $0.penPreset = candidate }
                        } preview: {
                            // Scaled into the card, so a 12-point marker is
                            // still recognisably a stroke and not a blot.
                            StrokePreview(preset: candidate, width: min(max(own.width * 1.3, 1.5), 8), color: own.color)
                        }
                    }
                }
            }
            PanelSection(title: L10n.penStrokeAndSize) {
                PaperPreviewCard { StrokePreview(preset: preset, width: pen.width, color: pen.color) }
                StrokeWidthControl(title: L10n.shapeWidth, value: width, range: preset.widthRange,
                                   presets: preset.widthPresets)
                OpacityControl(title: L10n.studioOpacity, value: opacity)
            }
            PanelSection(title: L10n.markupColor) {
                EditorColorPalette(color: color, swatches: PaletteSwatch.pen, store: store)
            }
            PanelSection(title: L10n.toolAdvanced) {
                #if os(iOS)
                if preset.respondsToPressure {
                    PanelToggleRow(title: L10n.penPressure, systemImage: "scribble.variable",
                                   isOn: store.binding(\.usesPressure), id: "pen-pressure",
                                   detail: L10n.penPressureDetail)
                }
                #else
                smoothing(settings.smoothing)
                #endif
                PanelToggleRow(title: L10n.penSnap, systemImage: "triangle",
                               isOn: store.binding(\.snapsOnHold), id: "pen-snap", detail: L10n.penSnapDetail)
                FingerDrawingRow(isOn: $fingerDrawing)
            }
        }
    }

    /// The Mac shapes its own strokes, so it can smooth them. On iPad the
    /// line comes from PencilKit already smoothed, and a slider that changed
    /// nothing there would be decoration.
    private func smoothing(_ value: Double) -> some View {
        let text = value.formatted(.percent.precision(.fractionLength(0)))
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .frame(width: 24).foregroundStyle(EditorChrome.purple).accessibilityHidden(true)
                Text(L10n.penSmoothing).font(.app(.subheadline))
                Spacer()
                Text(verbatim: text).font(.app(.subheadline).weight(.medium).monospacedDigit()).accessibilityHidden(true)
            }
            Slider(value: store.binding(\.smoothing), in: 0...1) { Text(L10n.penSmoothing) }
                .accessibilityValue(text)
                .accessibilityIdentifier("pen-smoothing")
        }
    }
}

struct HighlighterSettingsPanel: View {
    let store: EditorToolSettingsStore
    @Binding var fingerDrawing: Bool
    /// Opens the recognised-text marker, which lays a highlight exactly along
    /// a line of text. Nil where there is nothing to open it on.
    var highlightText: (() -> Void)?
    let close: () -> Void

    private var width: Binding<Double> {
        Binding(get: { store.settings.currentHighlighter.width },
                set: { value in store.update { $0.currentHighlighter.width = value } })
    }

    private var strength: Binding<Double> {
        Binding(get: { store.settings.currentHighlighter.strength },
                set: { value in store.update { $0.currentHighlighter.strength = value } })
    }

    private static func ink(_ color: RGBAColor, strength: Double) -> RGBAColor {
        var value = color
        value.alpha = strength
        return value
    }

    var body: some View {
        let settings = store.settings
        let style = settings.highlighterStyle
        let current = settings.currentHighlighter
        ToolPanelContainer(tool: .highlighter, mode: style.title,
                           restore: { store.update { $0.restoreDefaults(for: .highlighter) } }, close: close) {
            PanelSection(title: L10n.highlighterStyle) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(HighlighterStyle.allCases, id: \.self) { candidate in
                        let own = settings.highlighter(candidate)
                        let ink = Self.ink(settings.highlighterColor, strength: own.strength)
                        ToolPresetCard(title: candidate.title, selected: candidate == style,
                                       id: "highlighter-style-\(candidate.rawValue)") {
                            store.update { $0.highlighterStyle = candidate }
                        } preview: {
                            StrokePreview(tool: .highlighter, width: min(max(own.width * 0.55, 3), 16), color: ink,
                                          cap: candidate.cap, straight: candidate.straightens)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
            PanelSection(title: L10n.highlighterPreview) {
                PaperPreviewCard(height: 64) {
                    ZStack {
                        Text(L10n.highlighterSample)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.black)
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .padding(.horizontal, 18)
                        Canvas { context, size in
                            let y = style == .underline ? size.height / 2 + 14 : size.height / 2
                            let points = [InkPoint(x: 22, y: y), InkPoint(x: size.width - 22, y: y)]
                            InkPainter.draw(points, width: current.width, color: settings.highlighterInk,
                                            tool: .highlighter, cap: style.cap, in: &context)
                        }
                        .blendMode(.multiply)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.highlighterPreview)
                }
                PanelNote(text: L10n.highlighterReadable)
            }
            PanelSection(title: L10n.shapeWidth) {
                StrokeWidthControl(title: L10n.shapeWidth, value: width, range: 2...40, step: 1,
                                   presets: [4, 12, 20, 30])
                OpacityControl(title: L10n.highlighterStrength, value: strength)
            }
            PanelSection(title: L10n.markupColor) {
                EditorColorPalette(color: store.binding(\.highlighterColor), swatches: PaletteSwatch.highlighter,
                                   store: store)
            }
            PanelSection(title: L10n.toolAdvanced) {
                if let highlightText {
                    Button(action: highlightText) {
                        HStack(spacing: 10) {
                            Image(systemName: "text.viewfinder").frame(width: 24).foregroundStyle(EditorChrome.purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.highlighterSnapToText).font(.app(.subheadline))
                                PanelNote(text: L10n.highlighterSnapToTextDetail)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                .foregroundStyle(EditorChrome.secondaryText)
                        }
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("highlighter-snap-to-text")
                }
                FingerDrawingRow(isOn: $fingerDrawing)
            }
        }
    }
}

struct EraserSettingsPanel: View {
    let store: EditorToolSettingsStore
    @Binding var fingerDrawing: Bool
    let close: () -> Void

    /// PencilKit's stroke eraser has no size: it takes whatever stroke the
    /// tip touches. The Mac's own canvas sizes both modes.
    private var isResizable: Bool {
        #if os(iOS)
        store.settings.eraserMode == .precision
        #else
        true
        #endif
    }

    /// The circle the preview draws, in points on screen.
    private func previewDiameter(_ size: Double) -> Double {
        #if os(iOS)
        InkCanvas.eraser(mode: .precision, size: size).width
        #else
        size
        #endif
    }

    var body: some View {
        let settings = store.settings
        let size = settings.eraserSize
        let sizeText = ((size - 8) / 56).formatted(.percent.precision(.fractionLength(0)))
        ToolPanelContainer(tool: .eraser,
                           mode: settings.eraserMode == .precision ? L10n.eraserPrecision : L10n.eraserStroke,
                           restore: { store.update { $0.restoreDefaults(for: .eraser) } }, close: close) {
            PanelSection(title: L10n.eraserMode) {
                PanelSegmented(options: [
                    .init(value: InkEraserMode.precision, title: L10n.eraserPrecision, id: "studio-eraser-mode-precision"),
                    .init(value: InkEraserMode.stroke, title: L10n.eraserStroke, id: "studio-eraser-mode-stroke"),
                ], selection: store.binding(\.eraserMode))
                PanelNote(text: settings.eraserMode == .precision ? L10n.eraserPrecisionDetail : L10n.studioEraserDetail)
            }
            if isResizable {
                PanelSection(title: L10n.eraserSize) {
                    let diameter = min(previewDiameter(size), 84)
                    Circle().strokeBorder(EditorChrome.purple, lineWidth: 2)
                        .background(Circle().fill(EditorChrome.lavender))
                        .frame(width: diameter, height: diameter)
                        .frame(maxWidth: .infinity, minHeight: 88)
                        .accessibilityHidden(true)
                    HStack(spacing: 10) {
                        Slider(value: store.binding(\.eraserSize), in: 8...64) { Text(L10n.eraserSize) }
                            .accessibilityValue(sizeText)
                            .accessibilityIdentifier("studio-eraser-size")
                        Text(verbatim: sizeText).font(.app(.subheadline).weight(.medium).monospacedDigit())
                            .frame(minWidth: 48, alignment: .trailing).accessibilityHidden(true)
                    }
                    PanelSegmented(options: [
                        .init(value: 8.0, title: L10n.eraserSmall, id: "studio-eraser-size-8"),
                        .init(value: 36.0, title: L10n.eraserMedium, id: "studio-eraser-size-36"),
                        .init(value: 64.0, title: L10n.eraserLarge, id: "studio-eraser-size-64"),
                    ], selection: store.binding(\.eraserSize))
                }
            }
            PanelSection(title: L10n.eraserTarget) {
                PanelSegmented(options: [
                    .init(value: EraserTarget.all, title: L10n.eraserTargetAll, id: "eraser-target-all"),
                    .init(value: EraserTarget.handwriting, title: L10n.eraserTargetHandwriting, id: "eraser-target-handwriting"),
                    .init(value: EraserTarget.highlights, title: L10n.eraserTargetHighlights, id: "eraser-target-highlights"),
                ], selection: store.binding(\.eraserTarget))
                PanelNote(text: L10n.eraserProtected)
            }
            #if os(iOS)
            PanelSection(title: L10n.toolAdvanced) { FingerDrawingRow(isOn: $fingerDrawing) }
            #endif
        }
    }
}

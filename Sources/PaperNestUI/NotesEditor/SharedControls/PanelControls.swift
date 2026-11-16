import PaperNestCore
import SwiftUI

extension EditorTool {
    var icon: NotebookToolIcon.Kind {
        switch self {
        case .pen: .pen
        case .highlighter: .highlighter
        case .eraser: .eraser
        case .lasso: .lasso
        case .shape: .shapes
        case .text: .text
        case .image: .image
        case .sticker: .sticker
        case .insert: .insert
        }
    }
}

/// The frame every tool's settings share: who it is, which mode it is in, a
/// way out, the controls, and a way back to how the tool shipped.
struct ToolPanelContainer<Content: View>: View {
    let tool: EditorTool
    var mode: String?
    var restore: (() -> Void)?
    let close: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                NotebookToolIcon(kind: tool.icon, onAccent: true)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(EditorChrome.selection, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: tool.title).font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    if let mode {
                        Text(verbatim: mode).font(.caption).foregroundStyle(EditorChrome.secondaryText)
                            .accessibilityIdentifier("tool-panel-mode")
                    }
                }
                Spacer(minLength: 8)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(EditorChrome.lavender, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(L10n.done)
                .accessibilityIdentifier("studio-settings-done")
            }
            .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 8)
            .background(EditorChrome.surface)
            Divider().overlay(EditorChrome.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content()
                    if let restore {
                        Button(action: restore) {
                            Label { Text(L10n.toolRestoreDefaults) } icon: { Image(systemName: "arrow.counterclockwise") }
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(EditorChrome.purple)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("tool-restore-defaults")
                    }
                }
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 16)
            }
            .accessibilityIdentifier("tool-panel-scroll")
        }
        .foregroundStyle(EditorChrome.navy)
        .tint(EditorChrome.purple)
        // A popover takes the ideal size. A sheet is whatever width the
        // device is, and the panel fills it rather than sitting to one side.
        .frame(minWidth: 300, idealWidth: 384, maxWidth: .infinity, minHeight: 300, idealHeight: 580)
        .toolPanelAppearance()
    }
}

/// A titled group of controls on its own card.
struct PanelSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(EditorChrome.secondaryText)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(EditorChrome.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(EditorChrome.border, lineWidth: 0.75)
                }
        }
    }
}

/// A row of mutually exclusive choices. Falls back to a column when the
/// labels do not fit side by side, which French and Spanish regularly manage.
struct PanelSegmented<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
        let id: String
    }
    let options: [Option]
    @Binding var selection: Value

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) { segments }
            VStack(spacing: 4) { segments }
        }
        .padding(4)
        .background(EditorChrome.lavender, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var segments: some View {
        ForEach(options, id: \.value) { option in
            let selected = option.value == selection
            Button { selection = option.value } label: {
                Text(verbatim: option.title)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .foregroundStyle(selected ? Color.white : EditorChrome.navy)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(EditorChrome.selection)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(selected ? L10n.selectionOn : L10n.selectionOff)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier(option.id)
        }
    }
}

/// A slider with a − and + either side, the exact value, and a row of dots to
/// jump to.
struct StrokeWidthControl: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step = 0.1
    var presets: [Double] = []
    var sliderID = "studio-width-slider"
    var presetIDPrefix = "studio-width"

    private var number: String { value.formatted(.number.precision(.fractionLength(step < 1 ? 1 : 0))) }
    /// Spoken in full; shown short, because "2.5 points" does not fit a pill.
    private var valueText: String { L10n.studioWidthValue(number) }

    /// Rounded here, not with the slider's own `step:`, which on a Mac draws
    /// a tick for every step and turns a fine control into a comb.
    private var rounded: Binding<Double> {
        Binding(get: { value }, set: { value = clamp(($0 / step).rounded() * step) })
    }

    private func clamp(_ candidate: Double) -> Double { min(max(candidate, range.lowerBound), range.upperBound) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                stepButton("minus", by: -1, label: L10n.toolDecrease(title))
                Slider(value: rounded, in: range) { Text(verbatim: title) }
                    .accessibilityValue(valueText)
                    .accessibilityIdentifier(sliderID)
                stepButton("plus", by: 1, label: L10n.toolIncrease(title))
                Text(verbatim: L10n.toolPointsShort(number))
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .lineLimit(1)
                    .frame(minWidth: 62, minHeight: 32)
                    .background(EditorChrome.secondaryBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(EditorChrome.border, lineWidth: 0.75)
                    }
                    .accessibilityHidden(true)
            }
            if !presets.isEmpty {
                HStack(spacing: 2) {
                    ForEach(presets, id: \.self) { preset in
                        let selected = abs(value - preset) < step / 2
                        let dot = 4 + 16 * (preset - range.lowerBound) / max(range.upperBound - range.lowerBound, 0.001)
                        Button { value = preset } label: {
                            Circle().fill(EditorChrome.navy)
                                .frame(width: dot, height: dot)
                                .frame(width: 30, height: 30)
                                .overlay { Circle().strokeBorder(selected ? EditorChrome.purple : .clear, lineWidth: 2) }
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.studioWidthValue(preset.formatted(.number.precision(.fractionLength(step < 1 ? 1 : 0)))))
                        .accessibilityValue(selected ? L10n.selectionOn : L10n.selectionOff)
                        .accessibilityIdentifier("\(presetIDPrefix)-\(Int((preset * 10).rounded()))")
                    }
                }
            }
        }
    }

    private func stepButton(_ symbol: String, by direction: Double, label: String) -> some View {
        Button { value = clamp(((value + direction * step) / step).rounded() * step) } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 28, height: 28)
                .background(EditorChrome.lavender, in: Circle())
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct OpacityControl: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0.1...1
    var sliderID = "studio-opacity-slider"

    private var valueText: String { value.formatted(.percent.precision(.fractionLength(0))) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.lefthalf.filled").frame(width: 24).accessibilityHidden(true)
            Text(verbatim: title).font(.subheadline).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            Slider(value: $value, in: range) { Text(verbatim: title) }
                .accessibilityValue(valueText)
                .accessibilityIdentifier(sliderID)
            Text(verbatim: valueText)
                .font(.subheadline.weight(.medium).monospacedDigit())
                .frame(minWidth: 48, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
    }
}

/// A named colour the palette offers.
@MainActor
struct PaletteSwatch: Identifiable {
    let id: String
    let name: String
    let color: RGBAColor

    /// Ink colours. The five that `MarkupColorPicker` already offered keep
    /// their exact values and identifiers, so marks made before this palette
    /// existed still match a swatch.
    static var pen: [PaletteSwatch] {
        let known = Dictionary(uniqueKeysWithValues: MarkupColorPicker.presets.map { ($0.id, $0) })
        func existing(_ id: String) -> PaletteSwatch {
            let preset = known[id]!
            return PaletteSwatch(id: id, name: preset.name, color: preset.color)
        }
        return [PaletteSwatch(id: "black", name: L10n.colorBlack, color: .black),
                PaletteSwatch(id: "gray", name: L10n.colorGray, color: .init(red: 0.36, green: 0.39, blue: 0.47)),
                existing("purple"), existing("blue"),
                PaletteSwatch(id: "sky", name: L10n.colorSky, color: .init(red: 0.2, green: 0.67, blue: 0.95)),
                existing("green"), existing("yellow"),
                PaletteSwatch(id: "orange", name: L10n.colorOrange, color: .init(red: 0.98, green: 0.55, blue: 0.1)),
                existing("red"),
                PaletteSwatch(id: "pink", name: L10n.colorPink, color: .init(red: 0.96, green: 0.36, blue: 0.68))]
    }

    static var highlighter: [PaletteSwatch] {
        [PaletteSwatch(id: "yellow", name: L10n.colorYellow, color: .init(red: 1, green: 0.82, blue: 0)),
         PaletteSwatch(id: "green", name: L10n.colorGreen, color: .init(red: 0.35, green: 0.85, blue: 0.3)),
         PaletteSwatch(id: "sky", name: L10n.colorSky, color: .init(red: 0.2, green: 0.67, blue: 0.95)),
         PaletteSwatch(id: "pink", name: L10n.colorPink, color: .init(red: 0.98, green: 0.4, blue: 0.7)),
         PaletteSwatch(id: "orange", name: L10n.colorOrange, color: .init(red: 0.98, green: 0.55, blue: 0.1)),
         PaletteSwatch(id: "purple", name: L10n.colorPurple, color: .init(red: 0.6, green: 0.4, blue: 0.95))]
    }
}

/// Swatches, the colours used lately, the ones kept as favourites, and a way
/// to any other colour.
///
/// The binding carries hue only. Opacity belongs to the slider beside it, and
/// choosing a colour must not put a faded pen back to full strength.
struct EditorColorPalette: View {
    @Binding var color: RGBAColor
    let swatches: [PaletteSwatch]
    let store: EditorToolSettingsStore

    private var opaque: RGBAColor {
        var value = color
        value.alpha = 1
        return value
    }

    private func matches(_ other: RGBAColor) -> Bool {
        abs(other.red - color.red) < 0.004 && abs(other.green - color.green) < 0.004 && abs(other.blue - color.blue) < 0.004
    }

    private func choose(_ value: RGBAColor) {
        var next = value
        next.alpha = color.alpha
        color = next
    }

    var body: some View {
        let settings = store.settings
        VStack(alignment: .leading, spacing: 10) {
            // Rows of five, laid out eagerly. A lazy grid leaves a swatch out
            // of the hierarchy until it has been scrolled to, and a colour
            // that is not there cannot be found by VoiceOver's rotor, by a
            // keyboard, or by a test.
            Grid(alignment: .leading, horizontalSpacing: 2, verticalSpacing: 2) {
                ForEach(Array(stride(from: 0, to: swatches.count, by: 5)), id: \.self) { start in
                    GridRow {
                        ForEach(swatches[start..<min(start + 5, swatches.count)]) { swatch in
                            swatchButton(swatch.color, name: swatch.name, id: "markup-color-\(swatch.id)")
                        }
                    }
                }
            }
            if !settings.recentColors.isEmpty {
                row(L10n.colorRecent, colors: settings.recentColors, prefix: "recent-color")
            }
            if !settings.favoriteColors.isEmpty {
                row(L10n.colorFavorites, colors: settings.favoriteColors, prefix: "favorite-color")
            }
            HStack(spacing: 8) {
                ColorPicker(selection: Binding(get: { opaque.swiftUIColor }, set: { value in
                    #if os(iOS)
                    var picked = InkConversion.rgba(UIColor(value))
                    #else
                    var picked = InkConversion.rgba(NSColor(value))
                    #endif
                    picked.alpha = color.alpha
                    color = picked
                }), supportsOpacity: false) {
                    Label { Text(L10n.markupCustomColor) } icon: { Image(systemName: "paintpalette") }
                        .font(.subheadline)
                }
                .accessibilityIdentifier("markup-custom-color")
                let favorite = settings.isFavorite(color)
                Button { store.update { $0.toggleFavorite(color) } } label: {
                    Image(systemName: favorite ? "star.fill" : "star")
                        .foregroundStyle(favorite ? EditorChrome.purple : EditorChrome.secondaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(favorite ? L10n.colorRemoveFavorite : L10n.colorAddFavorite)
                .accessibilityIdentifier("markup-color-favorite")
            }
        }
        // Recents are for colours that are not a tap away already, so a
        // swatch never goes in. A colour dialled in on the system picker
        // passes through dozens of values on the way; only the one it comes
        // to rest on is "used".
        .task(id: opaque) {
            try? await Task.sleep(for: .milliseconds(900))
            let settled = opaque
            guard !Task.isCancelled, !swatches.contains(where: { $0.color == settled }) else { return }
            store.update { $0.noteColorUsed(settled) }
        }
    }

    private func row(_ title: String, colors: [RGBAColor], prefix: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title).font(.caption).foregroundStyle(EditorChrome.secondaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { index, value in
                        swatchButton(value, name: L10n.colorCustomNumbered(index + 1), id: "\(prefix)-\(index)")
                    }
                }
            }
        }
    }

    private func swatchButton(_ value: RGBAColor, name: String, id: String) -> some View {
        let selected = matches(value)
        return Button { choose(value) } label: {
            ZStack {
                Circle().fill(value.swiftUIColor).frame(width: 26, height: 26)
                    .overlay { Circle().strokeBorder(EditorChrome.border, lineWidth: 0.75) }
                Circle().strokeBorder(selected ? EditorChrome.purple : .clear, lineWidth: 2.5)
                    .frame(width: 36, height: 36)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityValue(selected ? L10n.selectionOn : L10n.selectionOff)
        .accessibilityIdentifier(id)
    }
}

/// A selectable card: a small picture of what the choice does, and its name.
struct ToolPresetCard<Preview: View>: View {
    let title: String
    let selected: Bool
    let id: String
    let action: () -> Void
    @ViewBuilder let preview: () -> Preview

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                preview().frame(height: 34).frame(maxWidth: .infinity)
                Text(verbatim: title)
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 6).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(selected ? EditorChrome.lavender : EditorChrome.secondaryBackground,
                        in: RoundedRectangle(cornerRadius: EditorChrome.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EditorChrome.controlRadius, style: .continuous)
                    .strokeBorder(selected ? EditorChrome.purple : EditorChrome.border, lineWidth: selected ? 1.5 : 0.75)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? L10n.selectionOn : L10n.selectionOff)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

/// A sample stroke drawn by the same code that shapes real ones.
struct StrokePreview: View {
    var preset: PenPreset?
    var tool: InkStroke.Tool = .pen
    let width: Double
    let color: RGBAColor
    var cap: InkStroke.Cap?
    var straight = false

    var body: some View {
        Canvas { context, size in
            let samples = straight
                ? [PenSample(x: 14, y: size.height / 2), PenSample(x: size.width - 14, y: size.height / 2)]
                : Self.wave(in: size)
            let points = preset.map { PenDynamics.points(from: samples, preset: $0, usesPressure: false) }
                ?? samples.map { InkPoint(x: $0.x, y: $0.y) }
            InkPainter.draw(points, width: width, color: color, tool: tool, cap: cap, in: &context)
        }
        .accessibilityHidden(true)
    }

    /// An S-curve drawn the way a hand draws one: slowly into and out of it,
    /// quickly through the middle, so a pen that reacts to speed shows it.
    static func wave(in size: CGSize, inset: CGFloat = 14) -> [PenSample] {
        let count = 72
        var samples: [PenSample] = []
        var time = 0.0
        var previous: CGPoint?
        for index in 0...count {
            let u = Double(index) / Double(count)
            let point = CGPoint(x: inset + (size.width - inset * 2) * u,
                                y: size.height / 2 - sin(u * 2 * .pi) * (size.height / 2 - inset * 0.9))
            if let previous {
                let speed = 160 + 760 * pow(sin(.pi * u), 2)
                time += hypot(point.x - previous.x, point.y - previous.y) / speed
            }
            samples.append(PenSample(x: point.x, y: point.y, time: time))
            previous = point
        }
        return samples
    }
}

/// White, because paper is white in both appearances and ink is judged
/// against the paper it will land on.
struct PaperPreviewCard<Content: View>: View {
    var height: CGFloat = 72
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity).frame(height: height)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(EditorChrome.border, lineWidth: 0.75)
            }
    }
}

struct PanelToggleRow: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool
    let id: String
    var detail: String?

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                Image(systemName: systemImage).frame(width: 24).foregroundStyle(EditorChrome.purple)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).font(.subheadline)
                    if let detail {
                        Text(verbatim: detail).font(.caption).foregroundStyle(EditorChrome.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .toggleStyle(.switch)
        .frame(minHeight: 44)
        .accessibilityIdentifier(id)
    }
}

/// A square button with a symbol and a caption, for grids of things to add.
struct PanelTile: View {
    let title: String
    let systemImage: String
    let id: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 20)).frame(height: 26)
                    .foregroundStyle(EditorChrome.purple)
                Text(verbatim: title).font(.caption).multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(EditorChrome.secondaryBackground,
                        in: RoundedRectangle(cornerRadius: EditorChrome.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EditorChrome.controlRadius, style: .continuous)
                    .strokeBorder(EditorChrome.border, lineWidth: 0.75)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }
}

/// A note under a control, in the panel's quiet voice.
struct PanelNote: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.caption)
            .foregroundStyle(EditorChrome.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}


/// Shared presentation chrome. It deliberately owns no action or editing state.
/// Native forms retain their focus, scrolling and accessibility semantics.
private struct ToolPanelAppearance: ViewModifier {
    var isEmbedded: Bool

    func body(content: Content) -> some View {
        let styled = content.tint(EditorChrome.purple).background(EditorChrome.secondaryBackground)
        #if os(iOS)
        if isEmbedded {
            styled
        } else {
            styled
                .presentationBackground(EditorChrome.secondaryBackground)
                .presentationCornerRadius(24)
                .presentationDragIndicator(.visible)
                .presentationDetents([.large])
        }
        #else
        styled
        #endif
    }
}

extension View {
    func toolPanelAppearance(isEmbedded: Bool = false) -> some View {
        modifier(ToolPanelAppearance(isEmbedded: isEmbedded))
    }
}

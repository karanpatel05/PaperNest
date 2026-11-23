import PaperNestCore
import SwiftUI

extension LassoContent {
    var title: String {
        switch self {
        case .handwriting: L10n.lassoHandwriting
        case .highlights: L10n.lassoHighlights
        case .textBoxes: L10n.lassoTextBoxes
        case .images: L10n.lassoImages
        }
    }

    var symbol: String {
        switch self {
        case .handwriting: "scribble"
        case .highlights: "highlighter"
        case .textBoxes: "textformat"
        case .images: "photo"
        }
    }
}

struct LassoSettingsPanel: View {
    let store: EditorToolSettingsStore
    let selectAll: () -> Void
    let close: () -> Void

    private func includes(_ content: LassoContent) -> Binding<Bool> {
        Binding(get: { store.settings.lassoContent.contains(content) }, set: { isOn in
            store.update {
                if isOn { $0.lassoContent.insert(content) } else { $0.lassoContent.remove(content) }
            }
        })
    }

    var body: some View {
        let settings = store.settings
        ToolPanelContainer(tool: .lasso,
                           mode: settings.lassoMode == .freehand ? L10n.selectionFreehand : L10n.selectionRectangle,
                           restore: { store.update { $0.restoreDefaults(for: .lasso) } }, close: close) {
            PanelSection(title: L10n.selectionMode) {
                PanelSegmented(options: [
                    .init(value: PageSelectionMode.freehand, title: L10n.selectionFreehand, id: "studio-lasso-freehand"),
                    .init(value: PageSelectionMode.rectangle, title: L10n.selectionRectangle, id: "studio-lasso-rectangle"),
                ], selection: store.binding(\.lassoMode))
                PanelNote(text: L10n.lassoInkHint)
            }
            PanelSection(title: L10n.lassoContent) {
                ForEach(LassoContent.allCases, id: \.self) { content in
                    PanelToggleRow(title: content.title, systemImage: content.symbol, isOn: includes(content),
                                   id: "lasso-content-\(content.rawValue)")
                }
            }
            PanelSection(title: L10n.lassoActions) {
                Button(action: selectAll) {
                    Label { Text(L10n.selectAll) } icon: { Image(systemName: "checkmark.circle") }
                        .font(.app(.subheadline).weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(Color.white)
                        .background(EditorChrome.selection, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("studio-lasso-select-all")
                PanelNote(text: L10n.lassoActionsDetail)
            }
        }
    }
}

/// A shape's outline, drawn small.
struct ShapeGlyph: View {
    let kind: ShapeAnnotation
    var lineWidth: CGFloat = 1.8

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height) - lineWidth * 2
            let rect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
            let points = kind.previewOutline(in: rect)
            guard let first = points.first else { return }
            var path = Path()
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            context.stroke(path, with: .foreground,
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

struct ShapeSettingsPanel: View {
    let store: EditorToolSettingsStore
    let close: () -> Void

    private var opacity: Binding<Double> {
        Binding(get: { store.settings.shapeColor.alpha }, set: { value in store.update { $0.shapeColor.alpha = value } })
    }

    private var color: Binding<RGBAColor> {
        Binding(get: { store.settings.shapeColor }, set: { value in
            store.update {
                var next = value
                next.alpha = $0.shapeColor.alpha
                $0.shapeColor = next
            }
        })
    }

    var body: some View {
        let settings = store.settings
        let kind = settings.shapeKind
        ToolPanelContainer(tool: .shape, mode: kind.title,
                           restore: { store.update { $0.restoreDefaults(for: .shape) } }, close: close) {
            PanelSection(title: L10n.toolShapes) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(ShapeAnnotation.library, id: \.self) { candidate in
                        ToolPresetCard(title: candidate.title, selected: candidate == kind,
                                       id: "shape-kind-\(candidate.rawValue)") {
                            store.update { $0.shapeKind = candidate }
                        } preview: {
                            ShapeGlyph(kind: candidate).foregroundStyle(EditorChrome.navy)
                        }
                    }
                }
                PanelNote(text: L10n.shapeDragToDraw)
            }
            PanelSection(title: L10n.shapeStyle) {
                PaperPreviewCard(height: 84) {
                    ShapeGlyph(kind: kind, lineWidth: CGFloat(min(settings.shapeWidth * 1.5, 14)))
                        .foregroundStyle(settings.shapeColor.swiftUIColor)
                        .padding(8)
                }
                StrokeWidthControl(title: L10n.shapeWidth, value: store.binding(\.shapeWidth), range: 0.5...12,
                                   presets: [1, 2, 4, 8])
                OpacityControl(title: L10n.studioOpacity, value: opacity)
                if kind.isClosed {
                    PanelToggleRow(title: L10n.shapeLockAspect, systemImage: "aspectratio",
                                   isOn: store.binding(\.shapeLocksAspect), id: "shape-lock-aspect",
                                   detail: L10n.shapeLockAspectDetail)
                }
            }
            PanelSection(title: L10n.markupColor) {
                EditorColorPalette(color: color, swatches: PaletteSwatch.pen, store: store)
            }
        }
    }
}

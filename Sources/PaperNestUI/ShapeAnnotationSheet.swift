import PaperNestCore
import SwiftUI

struct ShapeAnnotationSheet: View {
    let model: DocumentModel
    let page: Page
    let undoManager: UndoManager?
    @Environment(\.dismiss) private var dismiss
    @State private var kind = ShapeAnnotation.rectangle
    @State private var start = CGPoint(x: 0.25, y: 0.25)
    @State private var end = CGPoint(x: 0.75, y: 0.75)
    @State private var color = RGBAColor(red: 0.1, green: 0.3, blue: 0.9)
    @State private var width = 2.0
    @State private var saving = false
    @State private var failed = false

    private var stroke: InkStroke? {
        try? kind.stroke(from: start, to: end, geometry: page.geometry, color: color, width: width)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(ShapeAnnotation.allCases, id: \.self) { shape in
                        Button { kind = shape } label: {
                            HStack {
                                Label(shape.title, systemImage: shape.symbol)
                                Spacer()
                                if kind == shape { Image(systemName: "checkmark") }
                            }.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("shape-kind-\(shape.rawValue)")
                        .accessibilityValue(kind == shape ? L10n.selectionOn : L10n.selectionOff)
                    }
                }
                Section {
                    preview.frame(height: 240)
                    DisclosureGroup(L10n.shapePosition) {
                        positionSlider(L10n.shapeStartX, value: $start.x, id: "start-x")
                        positionSlider(L10n.shapeStartY, value: $start.y, id: "start-y")
                        positionSlider(L10n.shapeEndX, value: $end.x, id: "end-x")
                        positionSlider(L10n.shapeEndY, value: $end.y, id: "end-y")
                    }
                } footer: { Text(stroke == nil ? L10n.shapeInvalid : L10n.shapeDrag) }
                Section {
                    Picker(L10n.shapeWidth, selection: $width) {
                        Text(L10n.shapeThin).tag(1.0)
                        Text(L10n.shapeMedium).tag(2.0)
                        Text(L10n.shapeThick).tag(4.0)
                    }.pickerStyle(.segmented)
                    MarkupColorPicker(color: $color)
                } header: { Text(L10n.shapeStyle) }
                  footer: { Text(L10n.shapeHelp) }
            }
            .formStyle(.grouped)
            .disabled(saving)
            .navigationTitle(L10n.shapeTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }.disabled(saving)
                        .accessibilityIdentifier("shape-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.shapeAdd) { Task { await save() } }
                        .disabled(saving || stroke == nil || model.isChangingNotebookPage)
                        .accessibilityIdentifier("shape-save")
                }
            }
            .interactiveDismissDisabled(saving)
            .alert(L10n.genericErrorTitle, isPresented: $failed) {
                Button(L10n.ok) {}
            } message: { Text(L10n.shapeSaveFailed) }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 650)
        #endif
    }

    private func positionSlider(_ title: String, value: Binding<CGFloat>, id: String) -> some View {
        VStack(alignment: .leading) {
            Text(title)
            Slider(value: value, in: 0...1)
                .accessibilityLabel(title)
                .accessibilityIdentifier("shape-position-\(id)")
        }
    }

    private var preview: some View {
        GeometryReader { container in
            let size = page.geometry.pageSize
            let scale = min(container.size.width / size.width, container.size.height / size.height)
            let frame = CGSize(width: size.width * scale, height: size.height * scale)
            ZStack {
                PageImageView(page: page, pixelSize: 700)
                if let stroke {
                    Path { path in
                        for (index, point) in stroke.points.enumerated() {
                            let p = CGPoint(x: point.x, y: point.y).applying(page.geometry.sourceToPage)
                            let displayed = CGPoint(x: p.x * scale, y: p.y * scale)
                            if index == 0 { path.move(to: displayed) } else { path.addLine(to: displayed) }
                        }
                    }.stroke(color.swiftUIColor, style: StrokeStyle(lineWidth: width * scale, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(width: frame.width, height: frame.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 2).onChanged { value in
                func normalized(_ p: CGPoint) -> CGPoint {
                    CGPoint(x: min(max((p.x - (container.size.width - frame.width) / 2) / frame.width, 0), 1),
                            y: min(max((p.y - (container.size.height - frame.height) / 2) / frame.height, 0), 1))
                }
                start = normalized(value.startLocation)
                end = normalized(value.location)
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.shapePreview)
            .accessibilityValue(L10n.shapeCoordinates(Int(start.x * 100), Int(start.y * 100), Int(end.x * 100), Int(end.y * 100)))
            .accessibilityIdentifier("shape-preview")
        }
    }

    private func save() async {
        guard !saving, stroke != nil else { return }
        saving = true
        defer { saving = false }
        do {
            try await model.addShape(to: page, kind: kind, start: start, end: end, color: color, width: width, undoManager: undoManager)
            dismiss()
        } catch { failed = true }
    }
}

private extension ShapeAnnotation {
    var title: String {
        switch self {
        case .rectangle: L10n.shapeRectangle
        case .ellipse: L10n.shapeEllipse
        case .line: L10n.shapeLine
        case .arrow: L10n.shapeArrow
        }
    }
    var symbol: String {
        switch self {
        case .rectangle: "rectangle"
        case .ellipse: "oval"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        }
    }
}

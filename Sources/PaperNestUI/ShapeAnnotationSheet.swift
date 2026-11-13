import PaperNestCore
import SwiftUI

struct ShapeAnnotationSheet: View {
    let model: DocumentModel
    let page: Page
    let undoManager: UndoManager?
    let stampsOnly: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var kind = ShapeAnnotation.rectangle
    @State private var start = CGPoint(x: 0.25, y: 0.25)
    @State private var end = CGPoint(x: 0.75, y: 0.75)
    @State private var color = RGBAColor(red: 0.1, green: 0.3, blue: 0.9)
    @State private var width = 2.0
    @State private var saving = false
    @State private var failed = false

    init(model: DocumentModel, page: Page, undoManager: UndoManager?, stampsOnly: Bool = false) {
        self.model = model
        self.page = page
        self.undoManager = undoManager
        self.stampsOnly = stampsOnly
        _kind = State(initialValue: stampsOnly ? .checkmark : .rectangle)
        if stampsOnly {
            _start = State(initialValue: CGPoint(x: 0.35, y: 0.35))
            _end = State(initialValue: CGPoint(x: 0.65, y: 0.65))
        }
    }

    private var prefix: String { stampsOnly ? "stamp" : "shape" }

    private var stroke: InkStroke? {
        try? kind.stroke(from: start, to: end, geometry: page.geometry, color: color, width: width)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if dynamicTypeSize.isAccessibilitySize {
                        ForEach(stampsOnly ? ShapeAnnotation.stamps : ShapeAnnotation.shapes, id: \.self) { shape in
                            kindButton(shape)
                        }
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(stampsOnly ? ShapeAnnotation.stamps : ShapeAnnotation.shapes, id: \.self) { shape in
                                kindButton(shape)
                                    .padding(.horizontal, 10)
                                    .background(kind == shape ? Theme.accent.opacity(0.12) : Color.primary.opacity(0.04),
                                                in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(.vertical, 4)
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
                } footer: { Text(stroke == nil ? (stampsOnly ? L10n.stampInvalid : L10n.shapeInvalid) : (stampsOnly ? L10n.stampDrag : L10n.shapeDrag))
                    .font(.callout).foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true) }
                Section {
                    if dynamicTypeSize.isAccessibilitySize {
                        Text(L10n.shapeWidth).font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        ForEach([1.0, 2.0, 4.0], id: \.self) { value in
                            Button { width = value } label: {
                                HStack {
                                    Text(widthTitle(value)).fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 12)
                                    if width == value {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(width == value ? L10n.selectionOn : L10n.selectionOff)
                            .accessibilityIdentifier("shape-width-\(Int(value))")
                        }
                    } else {
                        Picker(L10n.shapeWidth, selection: $width) {
                            Text(L10n.shapeThin).tag(1.0)
                            Text(L10n.shapeMedium).tag(2.0)
                            Text(L10n.shapeThick).tag(4.0)
                        }.pickerStyle(.segmented)
                    }
                    MarkupColorPicker(color: $color)
                } header: { Text(L10n.shapeStyle).foregroundStyle(Color.primary) }
                  footer: { Text(stampsOnly ? L10n.stampHelp : L10n.shapeHelp)
                      .font(.callout).foregroundStyle(Color.primary)
                      .fixedSize(horizontal: false, vertical: true) }
            }
            .formStyle(.grouped)
            .disabled(saving)
            .navigationTitle(stampsOnly ? L10n.stampTitle : L10n.shapeTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(uiColor: .secondarySystemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }.disabled(saving)
                        .accessibilityIdentifier("\(prefix)-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.shapeAdd) { Task { await save() } }
                        .disabled(saving || stroke == nil || model.isChangingNotebookPage)
                        .accessibilityIdentifier("\(prefix)-save")
                }
            }
            .interactiveDismissDisabled(saving)
            .alert(L10n.genericErrorTitle, isPresented: $failed) {
                Button(L10n.ok) {}
            } message: { Text(stampsOnly ? L10n.stampSaveFailed : L10n.shapeSaveFailed) }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 650)
        #endif
    }

    private func kindButton(_ shape: ShapeAnnotation) -> some View {
        Button { kind = shape } label: {
            HStack(spacing: 8) {
                Image(systemName: shape.symbol).foregroundStyle(Theme.accent)
                Text(shape.title).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if kind == shape { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(prefix)-kind-\(shape.rawValue)")
        .accessibilityValue(kind == shape ? L10n.selectionOn : L10n.selectionOff)
    }

    private func widthTitle(_ value: Double) -> String {
        switch value {
        case 1: L10n.shapeThin
        case 4: L10n.shapeThick
        default: L10n.shapeMedium
        }
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
            .accessibilityLabel(stampsOnly ? L10n.stampPreview : L10n.shapePreview)
            .accessibilityValue(L10n.shapeCoordinates(Int(start.x * 100), Int(start.y * 100), Int(end.x * 100), Int(end.y * 100)))
            .accessibilityIdentifier("\(prefix)-preview")
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

extension ShapeAnnotation {
    var title: String {
        switch self {
        case .rectangle: L10n.shapeRectangle
        case .ellipse: L10n.shapeEllipse
        case .line: L10n.shapeLine
        case .arrow: L10n.shapeArrow
        case .checkmark: L10n.stampCheckmark
        case .cross: L10n.stampCross
        case .star: L10n.stampStar
        case .roundedRectangle: L10n.shapeRoundedRectangle
        case .triangle: L10n.shapeTriangle
        case .diamond: L10n.shapeDiamond
        case .pentagon: L10n.shapePentagon
        case .hexagon: L10n.shapeHexagon
        case .speechBubble: L10n.shapeSpeechBubble
        }
    }
    var symbol: String {
        switch self {
        case .rectangle: "rectangle"
        case .ellipse: "oval"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .checkmark: "checkmark"
        case .cross: "xmark"
        case .star: "star"
        case .roundedRectangle: "app"
        case .triangle: "triangle"
        case .diamond: "diamond"
        case .pentagon: "pentagon"
        case .hexagon: "hexagon"
        case .speechBubble: "bubble.left"
        }
    }
}

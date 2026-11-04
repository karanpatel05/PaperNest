import PaperNestCore
import PaperNestStore
import SwiftUI

/// Operates on real saved ink, including marks created before this manager
/// existed. Selecting rows or colors never writes until an action is pressed.
struct MarkupManagerSheet: View {
    @Bindable var model: DocumentModel
    let pageID: PageID
    let undoManager: UndoManager?
    @Environment(\.dismiss) private var dismiss
    @State private var page: Page?
    @State private var objects: [PageObject] = []
    @State private var selected: Set<PageObjectID> = []
    @State private var color = TextMarkupStyle.highlight.defaultColor
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var loadID = UUID()

    private var busy: Bool { isLoading || isSaving }

    var body: some View {
        NavigationStack {
            Form {
                if let page {
                    Section {
                        MarkupSelectionPreview(page: page, objects: objects.filter { selected.contains($0.id) })
                            .frame(height: 180).accessibilityHidden(true)
                    }
                }
                Section {
                    if isLoading {
                        ProgressView()
                    } else if objects.isEmpty {
                        Text(L10n.markupEmpty).foregroundStyle(Color.primary).accessibilityIdentifier("markup-empty")
                    } else {
                        ForEach(Array(objects.enumerated()), id: \.element.id) { index, object in
                            Button { toggle(object) } label: {
                                HStack(spacing: 12) {
                                    MarkSwatch(object: object).frame(width: 60, height: 32).accessibilityHidden(true)
                                    Text(Self.describe(object, number: index + 1))
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                    Image(systemName: selected.contains(object.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(Theme.accent)
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("markup-row-\(object.id.rawValue)")
                            .accessibilityLabel(Self.describe(object, number: index + 1))
                            .accessibilityValue(Self.state(of: object, selected: selected.contains(object.id)))
                        }
                    }
                } header: {
                    Text(L10n.markupSaved).foregroundStyle(Color.primary)
                } footer: {
                    Text(L10n.markupHelp).foregroundStyle(Color.primary)
                }
                if !objects.isEmpty {
                    Section(L10n.markupColor) {
                        MarkupColorPicker(color: $color)
                        // Only ink has an ink colour. The store refuses the
                        // rest outright, so offering the button for a text
                        // box or an image would only promise a refusal.
                        Button(L10n.markupRecolor) { Task { await apply(.recolor(color)) } }
                            .disabled(selected.isEmpty || !selectionIsAllInk)
                            .accessibilityIdentifier("markup-recolor")
                    }
                    Section {
                        Button(L10n.markupRemove, role: .destructive) { Task { await apply(.remove) } }
                            .disabled(selected.isEmpty)
                            .accessibilityIdentifier("markup-remove")
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(busy)
            .navigationTitle(L10n.manageMarkup)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.done) { dismiss() }.disabled(busy).accessibilityIdentifier("markup-done")
                }
            }
            .interactiveDismissDisabled(isSaving)
            .task(id: model.session.changeToken) { await load() }
            .alert(L10n.genericErrorTitle, isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button(L10n.ok) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 520, minHeight: 360, idealHeight: 620, maxHeight: 680)
        #endif
    }

    private func toggle(_ object: PageObject) {
        let wasEmpty = selected.isEmpty
        if !selected.insert(object.id).inserted { selected.remove(object.id) }
        if wasEmpty, case .ink(let stroke) = object.payload { color = stroke.color }
    }

    private var selectionIsAllInk: Bool {
        objects.filter { selected.contains($0.id) }.allSatisfy { object in
            if case .ink = object.payload { return true }
            return false
        }
    }

    /// A text box says what it says; everything else is numbered, because a
    /// stroke has no name and two of them look alike in a list.
    private static func describe(_ object: PageObject, number: Int) -> String {
        switch object.payload {
        case .text(let box) where !box.text.isEmpty: box.text
        case .image: L10n.markupImage
        case .text, .ink, .comment: L10n.markupMark(number)
        }
    }

    private static func state(of object: PageObject, selected: Bool) -> String {
        let selection = selected ? L10n.selectionOn : L10n.selectionOff
        guard case .ink(let stroke) = object.payload else { return selection }
        return "\(selection), \(stroke.color.hexLabel)"
    }

    private func load() async {
        let requestID = UUID()
        loadID = requestID
        isLoading = true
        defer { if loadID == requestID { isLoading = false } }
        do {
            guard let store = model.session.environment?.store, let latest = try await store.page(pageID) else { throw StoreError.pageNotFound }
            // Everything painted on the page, which is what this manager is
            // for. A comment is not painted on it and is not removable here.
            let latestObjects = try await store.objects(on: pageID).filter { object in
                switch object.payload {
                case .ink, .text, .image: true
                case .comment: false
                }
            }
            guard !Task.isCancelled, loadID == requestID else { return }
            if latest != page || latestObjects != objects {
                selected = []
                page = latest
                objects = latestObjects
            }
        } catch {
            guard !Task.isCancelled, loadID == requestID else { return }
            selected = []
            page = nil
            objects = []
            errorMessage = L10n.saveFailed
        }
    }

    private func apply(_ edit: InkEdit) async {
        guard !busy, let page, !selected.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await model.editInk(on: page, objects: objects.filter { selected.contains($0.id) }, edit: edit, undoManager: undoManager)
            await load()
        } catch StoreError.pageObjectsChanged {
            await load()
            errorMessage = L10n.markupChanged
        } catch { errorMessage = L10n.saveFailed }
    }
}

private struct MarkupSelectionPreview: View {
    let page: Page
    let objects: [PageObject]

    /// Where a mark sits in source points, whatever kind it is.
    static func bounds(of object: PageObject) -> CGRect? {
        switch object.payload {
        case .ink(let stroke): stroke.sourceBounds
        case .text(let box): box.frame
        case .image(let image): image.frame
        case .comment: nil
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let pageSize = page.geometry.pageSize
            let scale = min(proxy.size.width / pageSize.width, proxy.size.height / pageSize.height)
            PageImageView(page: page, pixelSize: 600)
                .overlay {
                    Canvas { context, _ in
                        for object in objects {
                            guard let bounds = Self.bounds(of: object) else { continue }
                            let rect = bounds.applying(page.geometry.sourceToPage)
                                .intersection(CGRect(origin: .zero, size: pageSize))
                            guard !rect.isNull else { continue }
                            let scaled = rect.applying(CGAffineTransform(scaleX: scale, y: scale)).insetBy(dx: -2, dy: -2)
                            context.stroke(Path(roundedRect: scaled, cornerRadius: 2), with: .color(Theme.accent),
                                           style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        }
                    }.clipped()
                }
                .frame(width: pageSize.width * scale, height: pageSize.height * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The little picture at the start of a row.
private struct MarkSwatch: View {
    let object: PageObject

    var body: some View {
        switch object.payload {
        case .ink(let stroke): InkSwatch(stroke: stroke)
        case .text: Image(systemName: "character.textbox").foregroundStyle(Color.secondary)
        case .image: Image(systemName: "photo").foregroundStyle(Color.secondary)
        case .comment: EmptyView()
        }
    }
}

private struct InkSwatch: View {
    let stroke: InkStroke
    var body: some View {
        Canvas { context, size in
            guard let bounds = stroke.sourceBounds, let first = stroke.points.first else { return }
            let scale = min((size.width - 4) / max(bounds.width, 1), (size.height - 4) / max(bounds.height, 1))
            let transform = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
                .concatenating(.init(scaleX: scale, y: scale))
                .concatenating(.init(translationX: (size.width - bounds.width * scale) / 2, y: (size.height - bounds.height * scale) / 2))
            var path = Path()
            path.move(to: CGPoint(x: first.x, y: first.y).applying(transform))
            for point in stroke.points.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y).applying(transform)) }
            if stroke.points.count == 1 { path.addLine(to: CGPoint(x: first.x, y: first.y).applying(transform)) }
            context.stroke(path, with: .color(stroke.color.swiftUIColor.opacity(stroke.tool == .highlighter ? InkStroke.highlighterOpacity : 1)),
                           style: StrokeStyle(lineWidth: max(1, stroke.width * scale), lineCap: .round, lineJoin: .round))
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.gray.opacity(0.25)))
    }
}

private extension InkStroke {
    var sourceBounds: CGRect? {
        guard let first = points.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        var maxWidth = width(at: first)
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
            maxWidth = max(maxWidth, width(at: p))
        }
        guard [minX, maxX, minY, maxY, maxWidth].allSatisfy(\.isFinite) else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -maxWidth / 2, dy: -maxWidth / 2)
    }
}

extension RGBAColor {
    var hexLabel: String {
        func channel(_ value: Double) -> Int { value.isFinite ? Int((min(1, max(0, value)) * 255).rounded()) : 0 }
        return String(format: "#%02X%02X%02X", channel(red), channel(green), channel(blue))
    }
}

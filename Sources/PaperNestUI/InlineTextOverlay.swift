import PaperNestCore
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Text owns its native editing surface; only explicit handles own drags.
struct InlineTextOverlay: View {
    @Bindable var session: InlineTextSession
    let page: Page
    let sourceToView: CGAffineTransform
    let visible: CGRect
    let zoom: CGFloat
    let undoManager: UndoManager?
    @State private var gestureFrame: CGRect?
    /// Night mode turns everything drawn over the page, this overlay included.
    @Environment(\.pageNightMode) private var isNight

    private var selectedBox: TextBox? { session.page?.id == page.id ? session.box : nil }
    private var marks: [PageObject] {
        session.model.selectedPageObjects.filter {
            guard $0.pageID == page.id, $0.id != session.original?.id else { return false }
            if case .text = $0.payload { return true }; return false
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if session.isPlacing || selectedBox != nil {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { point in
                        if session.isPlacing {
                            session.beginNew(on: page, at: point, sourceToView: sourceToView, zoom: zoom)
                        } else { Task { await session.finish(undoManager: undoManager) } }
                    }
                    .accessibilityIdentifier("inline-text-placement")
                    .accessibilityLabel(session.isPlacing ? L10n.inlinePlace : L10n.done)
                    .accessibilityAction {
                        if session.isPlacing {
                            session.beginNew(on: page, at: CGPoint(x: visible.midX, y: visible.midY), sourceToView: sourceToView, zoom: zoom)
                        } else { Task { await session.finish(undoManager: undoManager) } }
                    }
            }
            ForEach(marks, id: \.id) { object in
                if case .text(let box) = object.payload {
                    let rect = box.frame.applying(sourceToView)
                    Button {
                        Task {
                            if await session.finish(undoManager: undoManager) { session.select(object, on: page, sourceToView: sourceToView, zoom: zoom) }
                        }
                    } label: { Color.clear.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .frame(width: max(rect.width, 24), height: max(rect.height, 24))
                    .position(x: rect.midX, y: rect.midY)
                    .accessibilityLabel(L10n.textBox)
                    .accessibilityValue(box.text)
                    .accessibilityIdentifier("inline-text-object")
                }
            }
            if let box = selectedBox {
                selectedText(box)
                let rect = box.frame.applying(sourceToView)
                Rectangle().stroke(Theme.accent, lineWidth: 1.5)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
                if !visible.isNull && !visible.isEmpty {
                handle(symbol: "arrow.up.and.down.and.arrow.left.and.right", name: L10n.moveObject,
                       id: "inline-text-move", box: box, resizing: false)
                    .position(x: max(visible.minX + 22, rect.minX - 22), y: rect.midY)
                handle(symbol: "arrow.up.left.and.arrow.down.right", name: L10n.resizeObject,
                       id: "inline-text-resize", box: box, resizing: true)
                    .position(x: min(visible.maxX - 22, rect.maxX + 16), y: min(visible.maxY - 22, rect.maxY + 16))
                let bar = InlineTextLayout.toolbarFrame(box: rect, visible: visible,
                    size: CGSize(width: 420, height: session.hasFailure ? 100 : 52))
                InlineTextToolbar(session: session, sourceToView: sourceToView, undoManager: undoManager)
                    // The bar is controls, not part of the page, and night mode
                    // leaves controls as they are. It sits under the page's night
                    // filter, which is its own opposite, so the same filter here
                    // gives it back its day colours — without it the colour swatch
                    // for black text showed white.
                    .nightFilter(isNight)
                    .frame(width: max(1, bar.width), height: bar.height)
                    .position(x: bar.midX, y: bar.midY)
                }
            }
        }
        .onChange(of: session.box) { session.scheduleSave(undoManager: undoManager) }
    }

    @ViewBuilder private func selectedText(_ box: TextBox) -> some View {
        Group {
            if session.isEditing {
                InlineNativeTextView(session: session, box: box, focusRequest: session.focusRequest) { value in
                    session.change { $0.text = value }
                }
            } else {
                Text(box.text)
                    .font(.custom(box.postScriptFontName, fixedSize: box.fontSize))
                    .foregroundStyle(box.color.swiftUIColor)
                    .multilineTextAlignment(box.alignment == .center ? .center : box.alignment == .trailing ? .trailing : .leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: box.alignment == .center ? .top : box.alignment == .trailing ? .topTrailing : .topLeading)
                    .contentShape(Rectangle())
                    .onTapGesture { session.edit() }
                    .accessibilityAction(named: L10n.textBoxEdit) { session.edit() }
                    .accessibilityIdentifier("inline-text-selected")
            }
        }
        .frame(width: box.frame.width, height: box.frame.height)
        .clipped()
        .position(x: box.frame.midX, y: box.frame.midY)
        .transformEffect(sourceToView)
        .id("inline-text-anchor")
    }

    private func handle(symbol: String, name: String, id: String, box: TextBox, resizing: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(width: 28, height: 28)
            .background(Theme.surface, in: Circle())
            .overlay { Circle().strokeBorder(Theme.accent.opacity(0.5)) }
            .frame(width: 44, height: 44).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 4)
                .onChanged { value in
                    if gestureFrame == nil { gestureFrame = box.frame }
                    guard let initial = gestureFrame else { return }
                    let frame: CGRect
                    if resizing {
                        let viewRect = initial.applying(sourceToView)
                        let resized = CGRect(origin: viewRect.origin,
                            size: CGSize(width: max(44, viewRect.width + value.translation.width),
                                         height: max(32, viewRect.height + value.translation.height)))
                        frame = resized.applying(sourceToView.inverted())
                    } else {
                        let delta = DocumentModel.sourceDelta(of: value.translation, sourceToView: sourceToView)
                        frame = initial.offsetBy(dx: delta.x, dy: delta.y)
                    }
                    session.change { $0.frame = DocumentModel.clamped(frame, within: page.sourceSize) }
                }.onEnded { _ in
                    gestureFrame = nil
                    Task { await session.flush(undoManager: undoManager) }
                })
            .accessibilityLabel(name).accessibilityIdentifier(id)
            .accessibilityHint(L10n.inlineGeometryHint)
    }
}

private struct InlineTextToolbar: View {
    @Bindable var session: InlineTextSession
    let sourceToView: CGAffineTransform
    let undoManager: UndoManager?
    @State private var showColors = false

    private var box: TextBox { session.box ?? TextBox(frame: .zero, text: "") }
    private func apply(_ change: (inout TextBox) -> Void) { session.change(change) }

    var body: some View {
        VStack(spacing: 0) {
            if session.hasFailure {
                InlineTextRecoveryBar(session: session, undoManager: undoManager)
            }
            HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    Menu {
                        ForEach(TextBox.FontFamily.allCases, id: \.self) { family in
                            Button(family.label) { apply { $0.fontFamily = family } }
                                .accessibilityIdentifier("inline-font-\(family.rawValue)")
                        }
                    } label: { Image(systemName: "textformat").font(.system(size: 18)).frame(width: 44, height: 44) }
                    .accessibilityLabel(L10n.inlineFont).accessibilityValue(box.fontFamily.label)
                    .accessibilityIdentifier("inline-text-font")
                    Menu {
                        ForEach([10,12,14,18,24,36,48,72], id: \.self) { value in
                            Button(String(value)) { apply { $0.fontSize = Double(value) } }
                                .accessibilityIdentifier("inline-size-\(value)")
                        }
                        Button(L10n.inlineLarger) { apply { $0.fontSize = min(144, $0.fontSize + 1) } }
                        Button(L10n.inlineSmaller) { apply { $0.fontSize = max(6, $0.fontSize - 1) } }
                    } label: { Text(verbatim: box.fontSize.formatted(.number.precision(.fractionLength(0)))).font(.system(size: 18)).monospacedDigit().frame(width: 44, height: 44) }
                    .accessibilityLabel(L10n.textBoxSize).accessibilityValue(String(Int(box.fontSize)))
                    .accessibilityIdentifier("inline-text-size")
                    Button { showColors = true } label: {
                        Circle().fill(box.color.swiftUIColor).frame(width: 20, height: 20)
                            .overlay { Circle().strokeBorder(Theme.secondaryText, lineWidth: 1) }.frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(L10n.markupCustomColor).accessibilityIdentifier("inline-text-color")
                    .popover(isPresented: $showColors) {
                        MarkupColorPicker(color: Binding(get: { box.color }, set: { value in apply { $0.color = value } }))
                            .padding().frame(width: 280).presentationCompactAdaptation(.popover)
                    }
                    tool(L10n.inlineBold, "bold", "bold", selected: box.isBold) { apply { $0.isBold.toggle() } }
                    tool(L10n.inlineItalic, "italic", "italic", selected: box.isItalic) { apply { $0.isItalic.toggle() } }
                    Menu {
                        Button(L10n.textBoxAlignLeft) { apply { $0.alignment = .leading } }.accessibilityIdentifier("inline-align-leading")
                        Button(L10n.textBoxAlignCenter) { apply { $0.alignment = .center } }.accessibilityIdentifier("inline-align-center")
                        Button(L10n.textBoxAlignRight) { apply { $0.alignment = .trailing } }.accessibilityIdentifier("inline-align-trailing")
                    } label: { Image(systemName: box.alignment == .center ? "text.aligncenter" : box.alignment == .trailing ? "text.alignright" : "text.alignleft").font(.system(size: 18)).frame(width: 44, height: 44) }
                    .accessibilityLabel(L10n.textBoxAlignment)
                    .accessibilityValue(box.alignment == .center ? L10n.textBoxAlignCenter : box.alignment == .trailing ? L10n.textBoxAlignRight : L10n.textBoxAlignLeft)
                    .accessibilityIdentifier("inline-text-alignment")
                    tool(L10n.delete, "trash", "delete") { Task { await session.delete(undoManager: undoManager) } }
                    Menu {
                        Button(L10n.textBoxEdit) { session.edit() }
                        Button(L10n.inlineMoveLeft) { nudge(dx: -10, dy: 0) }
                        Button(L10n.inlineMoveRight) { nudge(dx: 10, dy: 0) }
                        Button(L10n.inlineMoveUp) { nudge(dx: 0, dy: -10) }
                        Button(L10n.inlineMoveDown) { nudge(dx: 0, dy: 10) }
                        Button(L10n.inlineWider) { resize(dw: 20, dh: 0) }
                        Button(L10n.inlineNarrower) { resize(dw: -20, dh: 0) }
                        Button(L10n.inlineTaller) { resize(dw: 0, dh: 20) }
                        Button(L10n.inlineShorter) { resize(dw: 0, dh: -20) }
                    } label: { Image(systemName: "ellipsis").font(.system(size: 18)).frame(width: 44, height: 44) }
                    .accessibilityLabel(L10n.more).accessibilityIdentifier("inline-text-more")
                }.padding(.horizontal, 4)
            }
            tool(L10n.done, "checkmark", "done") { Task { await session.finish(undoManager: undoManager) } }
            }
        }
        .disabled(session.isFinishing)
        .buttonStyle(.plain)
        .font(.body)
        .foregroundStyle(Theme.primaryText)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.separator) }
        .shadow(color: Theme.paperShadow, radius: 6, y: 3)
        #if os(macOS)
        .focusable(false)
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inline-text-toolbar")

    }

    private func tool(_ label: String, _ symbol: String, _ id: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18)).frame(width: 40, height: 40)
                .background(selected ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 10))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label).help(label)
        .accessibilityValue(selected ? L10n.selectionOn : L10n.selectionOff)
        .accessibilityIdentifier("inline-text-\(id)")
    }
    private func nudge(dx: Double, dy: Double) {
        guard let page = session.page else { return }
        let delta = DocumentModel.sourceDelta(of: CGSize(width: dx, height: dy), sourceToView: sourceToView)
        apply { $0.frame = DocumentModel.clamped($0.frame.offsetBy(dx: delta.x, dy: delta.y), within: page.sourceSize) }
    }
    private func resize(dw: Double, dh: Double) {
        guard let page = session.page else { return }
        apply {
            let frame = $0.frame.applying(sourceToView)
            let resized = CGRect(origin: frame.origin, size: CGSize(width: max(40, frame.width + dw), height: max(24, frame.height + dh)))
            $0.frame = DocumentModel.clamped(resized.applying(sourceToView.inverted()), within: page.sourceSize)
        }
    }
}


/// Also appears outside the canvas when a competing window removes the page.
struct InlineTextRecoveryBar: View {
    @Bindable var session: InlineTextSession
    let undoManager: UndoManager?
    @State private var showDiscardConfirmation = false

    var body: some View {
        HStack {
            Text(L10n.saveFailed).font(.caption).lineLimit(2)
            Button(L10n.inlineRetry) { Task { await session.flush(undoManager: undoManager) } }
                .accessibilityIdentifier("inline-text-retry")
            Menu {
                Button(L10n.inlineSaveAsNew) { Task { await session.saveAsNewBox(undoManager: undoManager) } }
                    .disabled(session.box?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
                    .accessibilityIdentifier("inline-text-save-as-new")
                Button(L10n.inlineCopyText) {
                    session.commitNative?()
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.box?.text ?? "", forType: .string)
                    #elseif os(iOS)
                    UIPasteboard.general.string = session.box?.text ?? ""
                    #endif
                }.accessibilityIdentifier("inline-text-copy-draft")
                Button(L10n.inlineDiscardDraft, role: .destructive) { showDiscardConfirmation = true }
                    .accessibilityIdentifier("inline-text-discard")
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 18)).frame(width: 44, height: 44)
            }
            .accessibilityLabel(L10n.inlineRecover)
            .accessibilityIdentifier("inline-text-recovery")
        }
        .padding(.horizontal, 8)
        .disabled(session.isSaving || session.isFinishing)
        .confirmationDialog(L10n.inlineDiscardDraft, isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
            Button(L10n.inlineDiscardDraft, role: .destructive) { Task { await session.discardDraft() } }
                .accessibilityIdentifier("inline-text-confirm-discard")
            Button(L10n.cancel, role: .cancel) {}
        } message: { Text(L10n.inlineDiscardHelp) }
    }
}

extension TextBox.FontFamily {
    var label: String {
        switch self {
        case .sans: L10n.inlineSans
        case .serif: L10n.inlineSerif
        case .monospaced: L10n.inlineMono
        }
    }
}

import PaperNestCore
import SwiftUI

/// What the toolbar needs from the document it sits above. The toolbar owns
/// which tool is armed and which panel is open; everything that touches the
/// document itself stays with the editor and arrives here as an action.
struct NotesToolbarContext {
    var showsLabels: Bool
    /// Compact width: the row of tools scrolls, More stays pinned at its end
    /// where it can always be reached, and Undo and Redo live in the lower
    /// palette under the thumb instead of at the far end of a scrolling row.
    var isCompact: Bool
    var isPhone: Bool
    var hasPage: Bool
    var isChangingPage: Bool
    var isLoadingPhoto: Bool
    var undoManager: UndoManager?
    var historyRevision: Int
    /// Commits any text box being edited. False means it could not be saved
    /// and the tool change must not go ahead.
    var finishText: () async -> Bool
    var armText: () -> Void
    var selectAll: () -> Void
    var highlightText: (() -> Void)?
    var image: ImageToolActions
    var insertSticker: (Sticker) -> Void
    var insert: InsertToolActions
}

/// The notes editor's main toolbar: nine tools, undo and redo, and whatever
/// the editor puts at either end.
///
/// Tapping a drawing tool arms it; tapping the armed tool again opens its
/// settings, anchored to the button as a popover where there is room and as a
/// bottom sheet on a phone. The sheet leaves the page above it live, so a
/// width or colour can be tried while the panel is still open.
struct NotesEditorToolbar<Leading: View, Trailing: View>: View {
    let store: EditorToolSettingsStore
    let session: InlineTextSession
    @Binding var markupTool: MacMarkupTool
    @Binding var isMarkingUp: Bool
    @Binding var fingerDrawing: Bool
    @Binding var openPanel: EditorTool?
    let context: NotesToolbarContext
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing
    /// How wide the nine tools are with their names under them, measured in
    /// the language on screen, and how wide the toolbar has to be.
    @State private var namedToolsWidth: CGFloat = 0
    @State private var availableWidth: CGFloat = 0

    /// Everything on the bar that is not a tool: the dividers, undo and redo,
    /// More, the gaps between them and the surface's own padding.
    private var chromeWidth: CGFloat { 204 }

    /// Tools are named only when every one of them still fits. A named row
    /// that pushed Sticker, Insert, Undo and More off the edge would trade
    /// four tools for nine labels; icons that all fit are the better bar.
    private var showsLabels: Bool {
        guard context.showsLabels else { return false }
        guard namedToolsWidth > 0, availableWidth > 0 else { return true }
        return availableWidth >= namedToolsWidth + chromeWidth
    }

    var body: some View {
        GeometryReader { geometry in
            if context.isCompact {
                HStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) { tools }
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.leading, 8).padding(.trailing, 4).padding(.vertical, 5)
                    }
                    .accessibilityIdentifier("notebook-tool-bar")
                    EditorToolbarDivider()
                    trailing().padding(.trailing, 6)
                }
                .editorFloatingSurface()
                .padding(.horizontal, 12).padding(.vertical, 9)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        tools
                        EditorToolbarDivider()
                        NotebookHistoryActions(undoManager: context.undoManager, busy: context.isChangingPage,
                                               historyRevision: context.historyRevision, beforeAction: context.finishText)
                            .labelStyle(.iconOnly)
                            .font(.system(size: 17, weight: .medium))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                        trailing()
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .editorFloatingSurface()
                    // Room for the surface's shadow, which the scroll view clips.
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .frame(minWidth: geometry.size.width)
                }
                .accessibilityIdentifier("notebook-tool-bar")
            }
        }
        .frame(height: showsLabels ? 80 : 72)
        .buttonStyle(.plain)
        .foregroundStyle(EditorChrome.navy)
        .background(Theme.canvas)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .background {
            // Faces only, never shown and never interactive: this exists to
            // be measured.
            HStack(spacing: 2) {
                ForEach(EditorTool.allCases) { EditorToolButtonFace(kind: $0.icon, title: $0.title) }
            }
            .fixedSize()
            .hidden()
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { namedToolsWidth = $0 }
        }
    }

    /// The nine tools in their two groups, with whatever leads them.
    @ViewBuilder private var tools: some View {
        leading()
        ForEach([EditorTool.pen, .highlighter, .eraser, .lasso], id: \.self) { toolButton($0) }
        EditorToolbarDivider()
        ForEach([EditorTool.shape, .text, .image, .sticker, .insert], id: \.self) { toolButton($0) }
    }

    // MARK: Buttons

    private func isSelected(_ tool: EditorTool) -> Bool {
        if let mode = tool.markupTool { return isMarkingUp && markupTool == mode }
        if tool == .text { return session.isPlacing || session.isSelected || openPanel == .text }
        return openPanel == tool
    }

    private func isEnabled(_ tool: EditorTool) -> Bool {
        guard context.hasPage else { return false }
        switch tool {
        case .pen, .highlighter, .eraser, .lasso: return true
        case .shape, .text, .sticker, .insert: return !context.isChangingPage
        case .image: return !context.isChangingPage && !context.isLoadingPhoto
        }
    }

    /// The identifiers the tools have always had, so nothing that looks them
    /// up — tests, automation, a saved UI recording — has to learn new names.
    private func identifier(_ tool: EditorTool) -> String {
        switch tool {
        case .text: "editor-text-box"
        case .image: "editor-insert-image"
        default: "studio-tool-\(tool.rawValue)"
        }
    }

    private func label(_ tool: EditorTool) -> String {
        switch tool {
        case .text: L10n.textBox
        case .image: L10n.insertImage
        default: tool.title
        }
    }

    private func shortcut(_ tool: EditorTool) -> KeyEquivalent {
        let index = EditorTool.allCases.firstIndex(of: tool) ?? 0
        return KeyEquivalent(Character(String(index + 1)))
    }

    private func toolButton(_ tool: EditorTool) -> some View {
        let selected = isSelected(tool)
        return Button { tap(tool) } label: {
            EditorToolButtonFace(kind: tool.icon, title: showsLabels ? tool.title : nil, selected: selected)
        }
        .disabled(!isEnabled(tool))
        // ⌥⌘1…9, in toolbar order. ⌘ and ⌃ with a digit are both spoken for
        // (tabs and Mission Control), and a bare letter would fire while
        // typing in a text box.
        .keyboardShortcut(shortcut(tool), modifiers: [.command, .option])
        .accessibilityIdentifier(identifier(tool))
        .accessibilityLabel(label(tool))
        .accessibilityValue(selected ? L10n.selectionOn : L10n.selectionOff)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(label(tool))
        .popover(isPresented: Binding(get: { openPanel == tool },
                                      set: { showing in if !showing, openPanel == tool { openPanel = nil } }),
                 arrowEdge: .top) {
            panel(tool)
                .presentationCompactAdaptation(.sheet)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.visible)
        }
    }

    private func tap(_ tool: EditorTool) {
        Task {
            if let mode = tool.markupTool {
                guard await context.finishText() else { return }
                // The second tap on the tool already in hand is the way into
                // its settings; the first only picks it up.
                openPanel = isMarkingUp && markupTool == mode ? tool : nil
                markupTool = mode
                isMarkingUp = true
                if context.isPhone { fingerDrawing = true }
            } else if tool == .text {
                if session.isPlacing || session.isSelected { openPanel = .text } else {
                    openPanel = nil
                    context.armText()
                }
            } else {
                guard await context.finishText() else { return }
                openPanel = tool
            }
        }
    }

    // MARK: Panels

    private func close() { openPanel = nil }

    /// Closes the panel, then acts.
    private func closing(_ action: @escaping () -> Void) -> () -> Void {
        { close(); action() }
    }

    /// Closes the panel, then runs something that presents on its own — a
    /// picker, a camera, a sheet, another panel. Two presentations cannot be
    /// on their way up and down at once: asked for while this one is still
    /// leaving, the second is the one that silently never appears. So it is
    /// asked for once this one has gone.
    private func presenting(_ action: @escaping () -> Void) -> () -> Void {
        {
            close()
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                action()
            }
        }
    }

    @ViewBuilder
    private func panel(_ tool: EditorTool) -> some View {
        switch tool {
        case .pen:
            PenSettingsPanel(store: store, fingerDrawing: $fingerDrawing, close: close)
        case .highlighter:
            HighlighterSettingsPanel(store: store, fingerDrawing: $fingerDrawing,
                                     highlightText: context.highlightText.map(presenting), close: close)
        case .eraser:
            EraserSettingsPanel(store: store, fingerDrawing: $fingerDrawing, close: close)
        case .lasso:
            LassoSettingsPanel(store: store, selectAll: closing(context.selectAll), close: close)
        case .shape:
            ShapeSettingsPanel(store: store, close: close)
        case .text:
            TextSettingsPanel(store: store, session: session, place: context.armText, close: close)
        case .image:
            ImageSettingsPanel(actions: ImageToolActions(photos: presenting(context.image.photos),
                                                         files: presenting(context.image.files),
                                                         camera: context.image.camera.map(presenting),
                                                         cameraSupported: context.image.cameraSupported),
                               close: close)
        case .sticker:
            StickerSettingsPanel(store: store, insert: { sticker in close(); context.insertSticker(sticker) },
                                 close: close)
        case .insert:
            let actions = context.insert
            InsertSettingsPanel(actions: InsertToolActions(
                addPage: actions.addPage.map { add in { template in close(); add(template) } },
                importPages: presenting(actions.importPages), textBox: closing(actions.textBox),
                image: presenting(actions.image), dateAndTime: closing(actions.dateAndTime),
                divider: closing(actions.divider), duplicatePage: closing(actions.duplicatePage),
                organizePages: presenting(actions.organizePages)), close: close)
        }
    }
}

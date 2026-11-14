import PaperNestCore
import SwiftUI

/// Where Document Utilities remembers which of its two sections were open.
/// A preference about the panel, not about any document.
enum DocumentUtilitiesStorage {
    static let pagesExpanded = "documentUtilities.pagesExpanded"
    static let editExpanded = "documentUtilities.editExpanded"
    static let annotateExpanded = "documentUtilities.annotateExpanded"
    static let insertExpanded = "documentUtilities.insertExpanded"
    static let processExpanded = "documentUtilities.processExpanded"
    static let all = [pagesExpanded, editExpanded, annotateExpanded, insertExpanded, processExpanded]

    /// A launch pointed at a throwaway library — every UI test, every dev run
    /// — starts with both sections open, whatever an earlier launch left
    /// collapsed. Same rule, and same reason, as the tool settings.
    ///
    /// **Once per launch, and that is load-bearing.** Reading this constant
    /// runs the reset the first time only. It was first written as a function
    /// called from the editor's initializer, and hung the app: changing
    /// `UserDefaults` notifies every `@AppStorage` in the window, a view
    /// above the editor rebuilt, the editor was initialised again, and reset
    /// the defaults again — forever, at full CPU.
    @MainActor static let freshStartForThrowawayLibrary: Void = {
        let defaults = UserDefaults.standard
        guard EditorToolSettingsStore.standardStorage(defaults) == nil else { return }
        for key in all { defaults.removeObject(forKey: key) }
        NightMode.resetForThrowawayLibrary(defaults)
    }()
}

/// What a page thumbnail's menu can do. Each one acts on a real page through
/// the editor, so it saves, undoes and reports errors like the same action
/// anywhere else.
struct PageGalleryActions {
    var select: (PageID) -> Void
    /// Moves the page one place earlier (-1) or later (+1).
    var move: (PageID, Int) -> Void
    /// Puts the page at this position (a dragged thumbnail, on a Mac).
    var reorder: (PageID, Int) -> Void = { _, _ in }
    var duplicate: (PageID) -> Void
    var rotate: (PageID, _ clockwise: Bool) -> Void
    var delete: (PageID) -> Void
    var export: (PageID) -> Void
}

/// The one panel beside the document: its pages, and everything that can be
/// done to them.
///
/// It replaces a page strip on one side of the editor and a tools list on the
/// other, each with its own switch. There is one panel now and one way to
/// show it, so what is open beside the page is a single question.
struct DocumentUtilitiesSidebar<PagesRow: View, Sections: View, Footer: View>: View {
    @Bindable var model: DocumentModel
    let canClose: Bool
    let close: () -> Void
    let pageActions: PageGalleryActions
    @ViewBuilder let pagesRow: () -> PagesRow
    @ViewBuilder let sections: () -> Sections
    @ViewBuilder let footer: () -> Footer
    @AppStorage(DocumentUtilitiesStorage.pagesExpanded) private var pagesExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                BrandMark.image(size: 22)
                    .foregroundStyle(Color.white)
                    .frame(width: 38, height: 38)
                    .background(EditorChrome.selection, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.documentUtilities).font(.headline).accessibilityAddTraits(.isHeader)
                    Text(L10n.documentUtilitiesSubtitle).font(.caption).foregroundStyle(EditorChrome.purple)
                }
                Spacer(minLength: 4)
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canClose)
                .accessibilityLabel(L10n.documentUtilitiesClose)
                .accessibilityIdentifier("pdf-tools-close")
            }
            .padding(.leading, 14).padding(.trailing, 4).padding(.vertical, 6)
            ScrollView {
                VStack(spacing: 10) {
                    UtilitiesSection(title: L10n.documentUtilitiesPages(model.pages.count), systemImage: "doc.on.doc",
                                     isExpanded: $pagesExpanded, id: "utilities-section-pages") {
                        PageThumbnailGallery(model: model, actions: pageActions)
                        HStack(spacing: 6) { pagesRow() }
                            .buttonStyle(UtilityTileStyle(compact: true))
                            .labelStyle(UtilityTileLabelStyle())
                    }
                    sections()
                }
                .padding(12)
            }
            .accessibilityIdentifier("pdf-tools-list")
            footer()
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 12)
        }
        .foregroundStyle(EditorChrome.navy)
        .tint(EditorChrome.purple)
        .background(EditorChrome.secondaryBackground)
    }
}

/// A folding card of tools, laid out as many to a row as fit. Remembers
/// whether it was open, under its own key.
struct ToolGridSection<Content: View>: View {
    let title: String
    let systemImage: String
    let id: String
    @ViewBuilder let content: () -> Content
    @AppStorage private var isExpanded: Bool

    init(title: String, systemImage: String, storageKey: String, id: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.id = id
        self.content = content
        _isExpanded = AppStorage(wrappedValue: true, storageKey)
    }

    var body: some View {
        UtilitiesSection(title: title, systemImage: systemImage, isExpanded: $isExpanded, id: id) {
            ToolGridLayout { content() }
                .buttonStyle(UtilityTileStyle())
                .labelStyle(UtilityTileLabelStyle())
        }
    }
}

/// The pinned Export / Save action at the foot of the panel.
struct UtilitiesExportButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label { Text(L10n.toolsExportSave) } icon: { Image(systemName: "square.and.arrow.up") }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(Color.white)
                .background(EditorChrome.selection, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("utilities-export")
    }
}

/// One collapsible card inside the panel. The header is the whole control.
struct UtilitiesSection<Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var isExpanded: Bool
    let id: String
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: systemImage).frame(width: 22).foregroundStyle(EditorChrome.purple)
                    Text(verbatim: title).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up").font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 0 : 180))
                }
                .padding(.horizontal, 12).frame(minHeight: 44).contentShape(Rectangle())
                .hoverWash(radius: 16)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? L10n.sectionExpanded : L10n.sectionCollapsed)
            .accessibilityIdentifier(id)
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) { content() }
                    .padding(.horizontal, 10).padding(.bottom, 12)
            }
        }
        .background(EditorChrome.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(EditorChrome.border, lineWidth: 0.75)
        }
    }
}

/// The document's real pages, side by side.
struct PageThumbnailGallery: View {
    @Bindable var model: DocumentModel
    let actions: PageGalleryActions

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                // Lazy: a long PDF renders the thumbnails that are in view,
                // not all of them the moment the panel opens.
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
                        card(page, index: index).id(page.id)
                    }
                }
                .padding(.horizontal, 2).padding(.vertical, 4)
            }
            .onChange(of: model.selectedPageID, initial: true) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .accessibilityLabel(L10n.pages)
    }

    private func card(_ page: Page, index: Int) -> some View {
        let selected = page.id == model.selectedPageID
        let count = model.pages.count
        return Button { actions.select(page.id) } label: {
            VStack(spacing: 5) {
                PageImageView(page: page, pixelSize: 220, accessibilityLabel: L10n.pageLabel(index + 1, of: count))
                    .frame(width: 62, height: 82)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(4)
                    .background(EditorChrome.secondaryBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(selected ? EditorChrome.purple : EditorChrome.border, lineWidth: selected ? 2 : 0.75)
                    }
                Text(verbatim: "\(index + 1)")
                    .font(.caption2.monospacedDigit().weight(selected ? .bold : .regular))
                    .foregroundStyle(selected ? EditorChrome.purple : EditorChrome.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverWash(radius: 9)
        #if os(macOS)
        // Drag one thumbnail onto another to put it there. Mac only: on iPad
        // a long press already opens the menu below, and the same gesture
        // cannot mean both. The menu's Move Earlier/Later works everywhere.
        .draggable(page.id.rawValue)
        .dropDestination(for: String.self) { dropped, _ in
            guard let raw = dropped.first, raw != page.id.rawValue else { return false }
            actions.reorder(PageID(rawValue: raw), index)
            return true
        }
        #endif
        .contextMenu {
            Button { actions.move(page.id, -1) } label: {
                Label { Text(L10n.scannerMoveEarlier) } icon: { Image(systemName: "arrow.left") }
            }.disabled(index == 0)
            Button { actions.move(page.id, 1) } label: {
                Label { Text(L10n.scannerMoveLater) } icon: { Image(systemName: "arrow.right") }
            }.disabled(index == count - 1)
            Divider()
            Button { actions.rotate(page.id, false) } label: {
                Label { Text(L10n.rotateLeft) } icon: { Image(systemName: "rotate.left") }
            }
            Button { actions.rotate(page.id, true) } label: {
                Label { Text(L10n.rotateRight) } icon: { Image(systemName: "rotate.right") }
            }
            Button { actions.duplicate(page.id) } label: {
                Label { Text(L10n.duplicate) } icon: { Image(systemName: "plus.square.on.square") }
            }
            Button { actions.export(page.id) } label: {
                Label { Text(L10n.export) } icon: { Image(systemName: "square.and.arrow.up") }
            }
            Divider()
            Button(role: .destructive) { actions.delete(page.id) } label: {
                Label { Text(L10n.deletePage) } icon: { Image(systemName: "trash") }
            }
        }
        // One element per page, and it has to say it is a button: wrapping the
        // card to give it a menu makes a plain element of it otherwise, which
        // VoiceOver would read without offering to open the page.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.pageLabel(index + 1, of: count))
        .accessibilityValue(selected ? L10n.selectedPage : "")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { actions.select(page.id) }
        .accessibilityIdentifier("page-thumbnail-\(index + 1)")
    }
}

/// Lays its children out as many to a row as keep each at least
/// `minimumWidth` wide — two in an iPad column, three on a phone, more on a
/// wide Mac panel — every row as tall as its tallest tile. Not lazy on
/// purpose: every tool is in the hierarchy whether or not it has been
/// scrolled to, so VoiceOver, the keyboard and tests can all find it.
struct ToolGridLayout: Layout {
    var spacing: CGFloat = 8
    var minimumWidth: CGFloat = {
        #if os(macOS)
        // Four across in the default 320-point column, five when it is
        // dragged wider — the denser grid the Mac mockup shows.
        58
        #else
        96
        #endif
    }()

    func columns(for width: CGFloat) -> Int {
        max(2, Int((width + spacing) / (minimumWidth + spacing)))
    }

    private func rows(_ subviews: Subviews, width: CGFloat) -> (column: CGFloat, rows: [(height: CGFloat, items: [LayoutSubview])]) {
        let count = columns(for: width)
        let column = max((width - spacing * CGFloat(count - 1)) / CGFloat(count), 0)
        let rows = stride(from: 0, to: subviews.count, by: count).map { start in
            let items = Array(subviews[start..<min(start + count, subviews.count)])
            let height = items.map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }.max() ?? 0
            return (height, items)
        }
        return (column, rows)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        let all = rows(subviews, width: width).rows
        let height = all.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(all.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let laid = rows(subviews, width: bounds.width)
        var y = bounds.minY
        for row in laid.rows {
            for (offset, item) in row.items.enumerated() {
                item.place(at: CGPoint(x: bounds.minX + CGFloat(offset) * (laid.column + spacing), y: y),
                           proposal: ProposedViewSize(width: laid.column, height: row.height))
            }
            y += row.height + spacing
        }
    }
}

/// A compact tool: symbol above its name.
struct UtilityTileLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
        // Denser on a Mac: a pointer does not need a finger-sized target, and
        // the mockup fits four or five tools across the panel.
        VStack(spacing: 4) {
            configuration.icon.font(.system(size: 15)).frame(height: 18)
            configuration.title.font(.caption2).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
        }
        #else
        VStack(spacing: 6) {
            configuration.icon.font(.system(size: 19)).frame(height: 24)
            configuration.title.font(.caption).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
        }
        #endif
    }
}

/// A light wash under the pointer, on the platforms that have one.
private struct HoverWash: ViewModifier {
    var radius: CGFloat = 12
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(EditorChrome.purple.opacity(hovered && isEnabled ? 0.08 : 0))
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(EditorChrome.purple.opacity(hovered && isEnabled ? 0.45 : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .onHover { hovered = $0 }
    }
}

extension View {
    fileprivate func hoverWash(radius: CGFloat = 12) -> some View { modifier(HoverWash(radius: radius)) }
}

struct UtilityTileStyle: ButtonStyle {
    /// The Pages row's four actions, a little shorter than a tool tile.
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    private var height: CGFloat {
        #if os(macOS)
        compact ? 44 : 50
        #else
        compact ? 56 : 68
        #endif
    }

    private var radius: CGFloat {
        #if os(macOS)
        9
        #else
        12
        #endif
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 3).padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: height)
            .foregroundStyle(EditorChrome.navy)
            .background(configuration.isPressed ? EditorChrome.lavender : EditorChrome.secondaryBackground,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(EditorChrome.border, lineWidth: 0.75)
            }
            .hoverWash(radius: radius)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

/// A longer action, on a row of its own.
struct UtilityRowStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 2)
            .foregroundStyle(configuration.role == .destructive ? Color.red : EditorChrome.navy)
            .background(configuration.isPressed ? EditorChrome.lavender : EditorChrome.secondaryBackground,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(EditorChrome.border, lineWidth: 0.75)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

/// A tool that is a mode — on or off — shown purple while it is on.
struct UtilityToggleTile: View {
    #if os(macOS)
    private static let spacing: CGFloat = 4, iconSize: CGFloat = 15, height: CGFloat = 50
    private static var titleFont: Font { .caption2 }
    #else
    private static let spacing: CGFloat = 6, iconSize: CGFloat = 19, height: CGFloat = 68
    private static var titleFont: Font { .caption }
    #endif
    let title: String
    let systemImage: String
    @Binding var isOn: Bool
    let id: String
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button { isOn.toggle() } label: {
            VStack(spacing: Self.spacing) {
                Image(systemName: systemImage).font(.system(size: Self.iconSize)).frame(height: Self.iconSize + 4)
                Text(verbatim: title).font(Self.titleFont).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 3).padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: Self.height)
            .foregroundStyle(isOn ? Color.white : EditorChrome.navy)
            .background {
                let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                if isOn { shape.fill(EditorChrome.selection) } else { shape.fill(EditorChrome.secondaryBackground) }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isOn ? Color.clear : EditorChrome.border, lineWidth: 0.75)
            }
            .hoverWash()
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? L10n.selectionOn : L10n.selectionOff)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

/// The one control that shows and hides Document Utilities.
struct UtilitiesToggleButton: View {
    @Binding var isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { isOn.toggle() }
        } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isOn ? Color.white : EditorChrome.navy)
                .frame(width: 36, height: 36)
                .background {
                    if isOn { Circle().fill(EditorChrome.selection) } else { Circle().fill(EditorChrome.lavender) }
                }
                .overlay { Circle().strokeBorder(EditorChrome.purple.opacity(isOn ? 0.6 : 0.25), lineWidth: 1) }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.documentUtilities)
        .accessibilityValue(isOn ? L10n.selectionOn : L10n.selectionOff)
        .accessibilityIdentifier("editor-panels")
        // ⌥⌘0, as Mac apps show and hide their inspector. ⌘0 is Zoom to Fit
        // and ⌥⌘1…9 pick the drawing tools, so nothing here is taken twice.
        .keyboardShortcut("0", modifiers: [.command, .option])
        .help(L10n.documentUtilitiesToggleHelp)
    }
}

/// Document Tools on a phone: the same panel, rising from the bottom.
///
/// Drawn inside the editor rather than as a system sheet, because half of
/// what is in it opens a sheet or a picker of its own, and a sheet cannot
/// present from underneath another one. It behaves like one all the same:
/// a handle, two heights, and a swipe down to put it away.
struct UtilitiesDrawer<Content: View>: View {
    let close: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var isExpanded = false
    @State private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func settle(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { change() }
    }

    var body: some View {
        GeometryReader { proxy in
            let height = isExpanded ? proxy.size.height * 0.92 : min(proxy.size.height * 0.6, 560)
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture(perform: close)
                    .accessibilityHidden(true)
                VStack(spacing: 0) {
                    // The handle is the drag target, so a drag never fights
                    // the scrolling list of tools below it.
                    Capsule().fill(EditorChrome.border).frame(width: 40, height: 5)
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 4)
                            .onChanged { drag = $0.translation.height }
                            .onEnded { value in
                                let moved = value.translation.height
                                settle {
                                    drag = 0
                                    if moved > 90 { if isExpanded { isExpanded = false } else { close() } }
                                    else if moved < -60 { isExpanded = true }
                                }
                            })
                        .onTapGesture { settle { isExpanded.toggle() } }
                        .accessibilityElement()
                        .accessibilityLabel(isExpanded ? L10n.drawerCollapse : L10n.drawerExpand)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { settle { isExpanded.toggle() } }
                        .accessibilityIdentifier("utilities-drawer-handle")
                    content()
                }
                .frame(maxWidth: .infinity)
                .frame(height: max(height - min(drag, 0), 200))
                .offset(y: max(drag, 0))
                .background(EditorChrome.secondaryBackground)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 16, y: -4)
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape) { close() }
            }
        }
        // Down to the bottom edge of the screen, like any drawer: stopping at
        // the safe area left a strip of page showing underneath it.
        .ignoresSafeArea(.container, edges: .bottom)
    }
}

/// What the lower bar's display button opens: how the page is shown.
struct DisplaySettingsPopover: View {
    @Binding var zoom: CGFloat
    @Binding var fingerDrawing: Bool
    /// Night mode, where the editor offers it.
    var nightMode: Binding<Bool>?
    /// Nil where fitting the width is what "fit" already does (a phone).
    var fitWidth: (() -> Void)?
    let close: () -> Void

    var body: some View {
        // As tall as what is in it where there is room (a popover on iPad
        // and Mac). On a phone it is a half-height sheet, and with the
        // Reading section added there is more here than half a phone shows,
        // so there it scrolls.
        ViewThatFits(in: .vertical) {
            settings
            ScrollView { settings }.accessibilityIdentifier("display-settings-scroll")
        }
        .foregroundStyle(EditorChrome.navy)
        .tint(EditorChrome.purple)
        .frame(minWidth: 300, idealWidth: 360, maxWidth: .infinity)
        .background(EditorChrome.secondaryBackground)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.displaySettings).font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30).background(EditorChrome.lavender, in: Circle())
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(L10n.done)
                .accessibilityIdentifier("studio-settings-done")
            }
            PanelSection(title: L10n.displayZoom) {
                PanelSegmented(options: PageZoom.steps.map {
                    .init(value: $0, title: Double($0).formatted(.percent.precision(.fractionLength(0))),
                          id: "display-zoom-\(Int(($0 * 100).rounded()))")
                }, selection: $zoom)
                HStack(spacing: 8) {
                    fitButton(L10n.zoomToFit, symbol: "arrow.up.left.and.down.right.magnifyingglass", id: "display-fit-page") { zoom = 1 }
                    if let fitWidth {
                        fitButton(L10n.displayFitWidth, symbol: "arrow.left.and.right", id: "display-fit-width", action: fitWidth)
                    }
                }
            }
            if let nightMode { NightModeSection(isOn: nightMode) }
            #if os(iOS)
            PanelSection(title: L10n.markup) {
                PanelToggleRow(title: L10n.drawWithFinger, systemImage: "hand.draw", isOn: $fingerDrawing,
                               id: "studio-finger-drawing", detail: L10n.toolFingerDetail)
            }
            #endif
        }
        .padding(16)
    }

    private func fitButton(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label { Text(verbatim: title) } icon: { Image(systemName: symbol) }
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(EditorChrome.lavender, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

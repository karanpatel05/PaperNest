import PaperNestCore
import SwiftUI

/// Where Document Utilities remembers which of its two sections were open.
/// A preference about the panel, not about any document.
enum DocumentUtilitiesStorage {
    static let pagesExpanded = "documentUtilities.pagesExpanded"
    static let toolsExpanded = "documentUtilities.toolsExpanded"

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
        defaults.removeObject(forKey: pagesExpanded)
        defaults.removeObject(forKey: toolsExpanded)
    }()
}

/// What a page thumbnail's menu can do. Each one acts on a real page through
/// the editor, so it saves, undoes and reports errors like the same action
/// anywhere else.
struct PageGalleryActions {
    var select: (PageID) -> Void
    /// Moves the page one place earlier (-1) or later (+1).
    var move: (PageID, Int) -> Void
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
struct DocumentUtilitiesSidebar<AddPage: View, GridTools: View, RowTools: View>: View {
    @Bindable var model: DocumentModel
    let canClose: Bool
    let close: () -> Void
    let pageActions: PageGalleryActions
    @ViewBuilder let addPage: () -> AddPage
    @ViewBuilder let gridTools: () -> GridTools
    @ViewBuilder let rowTools: () -> RowTools
    @AppStorage(DocumentUtilitiesStorage.pagesExpanded) private var pagesExpanded = true
    @AppStorage(DocumentUtilitiesStorage.toolsExpanded) private var toolsExpanded = true

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
                VStack(spacing: 12) {
                    UtilitiesSection(title: L10n.documentUtilitiesPages(model.pages.count), systemImage: "doc",
                                     isExpanded: $pagesExpanded, id: "utilities-section-pages") {
                        PageThumbnailGallery(model: model, actions: pageActions)
                        addPage()
                    }
                    UtilitiesSection(title: L10n.pdfTools, systemImage: "square.3.layers.3d",
                                     isExpanded: $toolsExpanded, id: "utilities-section-tools") {
                        TwoColumnLayout(spacing: 8) { gridTools() }
                            .buttonStyle(UtilityTileStyle())
                            .labelStyle(UtilityTileLabelStyle())
                        VStack(spacing: 6) { rowTools() }
                            .buttonStyle(UtilityRowStyle())
                            .labelStyle(.titleAndIcon)
                    }
                }
                .padding(12)
            }
            .accessibilityIdentifier("pdf-tools-list")
        }
        .foregroundStyle(EditorChrome.navy)
        .tint(EditorChrome.purple)
        .background(EditorChrome.secondaryBackground)
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
                HStack(alignment: .top, spacing: 10) {
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

/// Lays its children out two to a row, each half the width, every row as
/// tall as its taller tile. Not lazy on purpose: every tool is in the
/// hierarchy whether or not it has been scrolled to, so it can be found.
struct TwoColumnLayout: Layout {
    var spacing: CGFloat = 8

    private func rows(_ subviews: Subviews, width: CGFloat) -> [(height: CGFloat, items: [LayoutSubview])] {
        let column = max((width - spacing) / 2, 0)
        return stride(from: 0, to: subviews.count, by: 2).map { start in
            let items = Array(subviews[start..<min(start + 2, subviews.count)])
            let height = items.map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }.max() ?? 0
            return (height, items)
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        let all = rows(subviews, width: width)
        let height = all.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(all.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let column = max((bounds.width - spacing) / 2, 0)
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            for (offset, item) in row.items.enumerated() {
                item.place(at: CGPoint(x: bounds.minX + CGFloat(offset) * (column + spacing), y: y),
                           proposal: ProposedViewSize(width: column, height: row.height))
            }
            y += row.height + spacing
        }
    }
}

/// A compact tool: symbol above its name.
struct UtilityTileLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 6) {
            configuration.icon.font(.system(size: 19)).frame(height: 24)
            configuration.title.font(.caption).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
        }
    }
}

struct UtilityTileStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 6).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 68)
            .foregroundStyle(EditorChrome.navy)
            .background(configuration.isPressed ? EditorChrome.lavender : EditorChrome.secondaryBackground,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(EditorChrome.border, lineWidth: 0.75)
            }
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
    let title: String
    let systemImage: String
    @Binding var isOn: Bool
    let id: String
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button { isOn.toggle() } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 19)).frame(height: 24)
                Text(verbatim: title).font(.caption).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 6).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 68)
            .foregroundStyle(isOn ? Color.white : EditorChrome.navy)
            .background {
                let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                if isOn { shape.fill(EditorChrome.selection) } else { shape.fill(EditorChrome.secondaryBackground) }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isOn ? Color.clear : EditorChrome.border, lineWidth: 0.75)
            }
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
        .help(L10n.documentUtilities)
    }
}

/// Document Utilities on a phone: the same panel, rising from the bottom.
///
/// Drawn inside the editor rather than as a system sheet, because half of
/// what is in it opens a sheet or a picker of its own, and a sheet cannot
/// present from underneath another one.
struct UtilitiesDrawer<Content: View>: View {
    let close: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture(perform: close)
                    .accessibilityHidden(true)
                VStack(spacing: 0) {
                    Capsule().fill(EditorChrome.border).frame(width: 40, height: 5).padding(.top, 8).padding(.bottom, 2)
                        .accessibilityHidden(true)
                    content()
                }
                .frame(maxWidth: .infinity)
                .frame(height: min(proxy.size.height * 0.72, 620))
                .background(EditorChrome.secondaryBackground)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 16, y: -4)
                .accessibilityAddTraits(.isModal)
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
    /// Nil where fitting the width is what "fit" already does (a phone).
    var fitWidth: (() -> Void)?
    let close: () -> Void

    var body: some View {
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
            #if os(iOS)
            PanelSection(title: L10n.markup) {
                PanelToggleRow(title: L10n.drawWithFinger, systemImage: "hand.draw", isOn: $fingerDrawing,
                               id: "studio-finger-drawing", detail: L10n.toolFingerDetail)
            }
            #endif
        }
        .padding(16)
        .foregroundStyle(EditorChrome.navy)
        .tint(EditorChrome.purple)
        .frame(minWidth: 300, idealWidth: 360, maxWidth: .infinity)
        .background(EditorChrome.secondaryBackground)
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

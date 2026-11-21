import PaperNestCore
import PaperNestRender
import SwiftUI

/// The find bar: a field, how many hits and which one, and the way to the
/// next and the previous. It sits under the editor's toolbar while it is up.
struct DocumentFindBar: View {
    @Bindable var find: DocumentFind
    let model: DocumentModel
    /// Shows the page a hit is on. The editor finishes any text still being
    /// typed before it turns the page, so that is the editor's to do.
    let showPage: (PageID) -> Void

    @Environment(LibrarySession.self) private var session
    @FocusState private var isFieldFocused: Bool

    /// The pages as find read them: reading again is owed when one changes.
    private struct PageStamp: Hashable {
        let id: PageID
        let revision: Int
        let content: PageContent
    }

    private struct FindKey: Hashable {
        let pages: [PageStamp]
        let handwritingEpoch: Int
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // One row where there is room for it. At phone width in French
            // or Spanish there is not — the field was left 22 points wide —
            // so the count and the arrows drop to a row of their own.
            //
            // A layout rather than `ViewThatFits`: that swaps one branch of
            // views for another, and the field in the new branch is a new
            // field — the keyboard's focus went with the old one, in the
            // middle of a word, the moment the first hit count appeared.
            FindBarLayout {
                field
                // Always a view, even with nothing to say, so the layout can
                // count on five.
                ZStack { status }
                previousButton
                nextButton
                doneButton
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            if find.status == .noText {
                Text(L10n.findNoTextDetail)
                    .font(.caption).foregroundStyle(EditorChrome.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("find-no-text-detail")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.surface)
        .overlay(alignment: .bottom) { Divider() }
        // Handwriting read in the background arrives with a new epoch and no
        // change to any page, so the epoch is part of what asks for a re-read.
        .task(id: FindKey(pages: model.pages.map { PageStamp(id: $0.id, revision: $0.revision, content: $0.content) },
                          handwritingEpoch: session.handwritingEpoch)) {
            guard let renderer = session.environment?.renderer else { return }
            await find.index(model.pages, with: renderer, handwritingEpoch: session.handwritingEpoch)
        }
        .onChange(of: model.selectedPageID, initial: true) { _, id in find.anchorPageID = id }
        .onChange(of: find.focusRequest) { _, _ in
            if let hit = find.current, hit.pageID != model.selectedPageID { showPage(hit.pageID) }
        }
        .onChange(of: isFieldFocused, initial: true) { _, focused in find.isTyping = focused }
        .onAppear { isFieldFocused = true }
        .onDisappear { find.isTyping = false }
    }

    private var previousButton: some View {
        Button { find.previous() } label: {
            Label(L10n.findPrevious, systemImage: "chevron.up")
                .frame(width: 36, height: 36).contentShape(Rectangle())
        }
        .keyboardShortcut("g", modifiers: [.command, .shift])
        .accessibilityIdentifier("find-previous")
        .disabled(find.hits.isEmpty)
    }

    private var nextButton: some View {
        Button { find.next() } label: {
            Label(L10n.findNext, systemImage: "chevron.down")
                .frame(width: 36, height: 36).contentShape(Rectangle())
        }
        .keyboardShortcut("g", modifiers: .command)
        .accessibilityIdentifier("find-next")
        .disabled(find.hits.isEmpty)
    }

    private var doneButton: some View {
        Button(L10n.done) { find.close() }
            .accessibilityIdentifier("find-done")
            #if os(macOS)
            .keyboardShortcut(.cancelAction)
            #endif
    }

    private var field: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(EditorChrome.secondaryText)
                .accessibilityHidden(true)
            TextField(L10n.findPlaceholder, text: $find.query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                #endif
                .focused($isFieldFocused)
                // Return goes to the next hit, as it does in every reader.
                .onSubmit {
                    find.next()
                    isFieldFocused = true
                }
                .accessibilityIdentifier("find-field")
            if !find.query.isEmpty {
                Button { find.query = ""; isFieldFocused = true } label: {
                    Label(L10n.findClear, systemImage: "xmark.circle.fill")
                }
                .foregroundStyle(EditorChrome.secondaryText)
                .accessibilityIdentifier("find-clear")
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 36)
        .background(EditorChrome.secondaryBackground,
                    in: RoundedRectangle(cornerRadius: EditorChrome.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: EditorChrome.controlRadius, style: .continuous)
                .strokeBorder(EditorChrome.border, lineWidth: 0.75)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch find.status {
        case .idle:
            EmptyView()
        case .searching:
            ProgressView().controlSize(.small)
                .accessibilityLabel(L10n.findSearching)
                .accessibilityIdentifier("find-status")
        case .hit(let number, let total):
            statusText(L10n.findCount(number, of: total))
        case .noResults:
            statusText(L10n.findNoResults)
        case .noText:
            statusText(L10n.findNoText)
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.subheadline).monospacedDigit()
            .foregroundStyle(EditorChrome.secondaryText)
            .lineLimit(1).fixedSize()
            .accessibilityIdentifier("find-status")
    }
}

/// Lays out the find bar's five parts — field, count, previous, next, done.
///
/// On one row when the field would still be wide enough to type in;
/// otherwise the field and Done on the first row and the count and the
/// arrows on a second. The same five views either way, only placed
/// differently, so the field keeps the keyboard while the bar reflows.
struct FindBarLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 6
    /// Narrower than this and the field is not somewhere to type: the
    /// magnifier, the clear button and the padding take about seventy
    /// points of it before a letter does.
    var minimumFieldWidth: CGFloat = 240

    private struct Measured {
        let field: CGSize, status: CGSize, previous: CGSize, next: CGSize, done: CGSize
        let spacing: CGFloat

        /// Everything on the first row except the field, with its gaps.
        var besideField: CGFloat {
            (status.width > 0 ? status.width + spacing : 0) + previous.width + spacing + next.width + spacing
                + done.width + spacing
        }
        var oneRowHeight: CGFloat { max(field.height, status.height, previous.height, next.height, done.height) }
        var firstRowHeight: CGFloat { max(field.height, done.height) }
        var secondRowHeight: CGFloat { max(status.height, previous.height, next.height) }
    }

    private func measure(_ subviews: Subviews) -> Measured? {
        guard subviews.count == 5 else { return nil }
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return Measured(field: sizes[0], status: sizes[1], previous: sizes[2], next: sizes[3], done: sizes[4],
                        spacing: spacing)
    }

    private func fitsOneRow(_ measured: Measured, width: CGFloat) -> Bool {
        width - measured.besideField >= minimumFieldWidth
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let measured = measure(subviews) else { return .zero }
        let width = proposal.width ?? (measured.besideField + minimumFieldWidth)
        let height = fitsOneRow(measured, width: width) ? measured.oneRowHeight
            : measured.firstRowHeight + rowSpacing + measured.secondRowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let measured = measure(subviews) else { return }
        func place(_ index: Int, size: CGSize, leading x: CGFloat, midY: CGFloat, width: CGFloat? = nil) {
            subviews[index].place(at: CGPoint(x: x, y: midY), anchor: .leading,
                                  proposal: ProposedViewSize(width: width ?? size.width, height: size.height))
        }
        if fitsOneRow(measured, width: bounds.width) {
            let midY = bounds.midY
            let fieldWidth = bounds.width - measured.besideField
            var x = bounds.minX
            place(0, size: measured.field, leading: x, midY: midY, width: fieldWidth)
            x += fieldWidth + spacing
            if measured.status.width > 0 {
                place(1, size: measured.status, leading: x, midY: midY)
                x += measured.status.width + spacing
            } else {
                place(1, size: measured.status, leading: x, midY: midY)
            }
            place(2, size: measured.previous, leading: x, midY: midY)
            x += measured.previous.width + spacing
            place(3, size: measured.next, leading: x, midY: midY)
            x += measured.next.width + spacing
            place(4, size: measured.done, leading: x, midY: midY)
        } else {
            let firstMidY = bounds.minY + measured.firstRowHeight / 2
            let fieldWidth = max(bounds.width - measured.done.width - spacing, 0)
            place(0, size: measured.field, leading: bounds.minX, midY: firstMidY, width: fieldWidth)
            place(4, size: measured.done, leading: bounds.minX + fieldWidth + spacing, midY: firstMidY)
            let secondMidY = bounds.minY + measured.firstRowHeight + rowSpacing + measured.secondRowHeight / 2
            place(1, size: measured.status, leading: bounds.minX, midY: secondMidY)
            let nextX = bounds.maxX - measured.next.width
            place(3, size: measured.next, leading: nextX, midY: secondMidY)
            place(2, size: measured.previous, leading: nextX - spacing - measured.previous.width, midY: secondMidY)
        }
    }
}

/// The hits on one page, drawn over it: every one in yellow, the current one
/// stronger. It takes no touches, so the page under it works as before.
struct FindHighlightsOverlay: View {
    let find: DocumentFind
    let page: Page
    /// Source space to this view's space, the same mapping every other layer
    /// over the page is given.
    let sourceToView: CGAffineTransform

    @Environment(LibrarySession.self) private var session
    @State private var boxes: [DocumentFind.Hit: [NormalizedRect]] = [:]
    @State private var layout: (stamp: LayoutStamp, layout: PageTextLayout)?

    private struct LayoutStamp: Hashable {
        let id: PageID
        let revision: Int
        let content: PageContent
        let handwritingEpoch: Int
    }

    private struct LoadKey: Hashable {
        let stamp: LayoutStamp
        let hits: [DocumentFind.Hit]
        /// When find catches up with a new epoch and finds the same hits, the
        /// highlights still have to be drawn again.
        let indexedEpoch: Int?
    }

    private var stamp: LayoutStamp {
        LayoutStamp(id: page.id, revision: page.revision, content: page.content, handwritingEpoch: session.handwritingEpoch)
    }

    private static let every = Color(red: 1, green: 0.84, blue: 0.04).opacity(0.5)
    private static let current = Color(red: 1, green: 0.55, blue: 0).opacity(0.62)
    /// Night mode lays its filter over this overlay as well as the page, and
    /// that filter turns a pale yellow almost black (see `NightPalette`). So
    /// at night the hits are filled with the colours the filter turns *into*
    /// an amber band and, for the current hit, an orange one, under white words.
    private static let everyAtNight = Color(.sRGB, red: 0.77, green: 0.69, blue: 0.35)
    private static let currentAtNight = Color(.sRGB, red: 0.93, green: 0.61, blue: 0.31)

    /// What a hit is filled with, before the page's own blending and filter.
    static func fill(isCurrent: Bool, isNight: Bool) -> Color {
        if isNight { return isCurrent ? currentAtNight : everyAtNight }
        return isCurrent ? current : every
    }

    @Environment(\.pageNightMode) private var isNight

    var body: some View {
        let hits = find.hits(on: page.id)
        Group {
            // Nothing at all on a page with no hits — not even an empty
            // element for a screen reader to land on.
            if !hits.isEmpty { highlights(hits) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .task(id: LoadKey(stamp: stamp, hits: hits, indexedEpoch: find.indexedHandwritingEpoch(of: page.id))) {
            await load(hits)
        }
        .onChange(of: find.focusRequest) { _, _ in announceCurrentHit() }
    }

    private func highlights(_ hits: [DocumentFind.Hit]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(hits, id: \.self) { hit in
                let isCurrent = hit == find.current
                ForEach(Array((boxes[hit] ?? []).enumerated()), id: \.offset) { index, box in
                    let rect = box.denormalized(in: page.sourceSize).applying(sourceToView)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Self.fill(isCurrent: isCurrent, isNight: isNight))
                        .frame(width: max(rect.width, 2), height: max(rect.height, 2))
                        // The anchor is the first line of the current hit:
                        // that is where the page scrolls to.
                        .id(isCurrent && index == 0 ? AnyHashable(DocumentFind.anchorID)
                            : AnyHashable("find-\(page.id.rawValue)-\(hit.range.lowerBound)-\(index)"))
                        .padding(.leading, max(rect.minX, 0))
                        .padding(.top, max(rect.minY, 0))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Yellow over black text has to leave the text readable.
        .blendMode(.multiply)
        .accessibilityElement()
        .accessibilityLabel(L10n.findOnPage)
        .accessibilityValue(Text(verbatim: "\(boxes.keys.filter(hits.contains).count)"))
        .accessibilityIdentifier("find-highlights")
    }

    private func load(_ hits: [DocumentFind.Hit]) async {
        guard !hits.isEmpty else {
            boxes = [:]
            return
        }
        // The hits were found in text read at some handwriting epoch; boxes
        // from a layout read at another could fall on the wrong words. Draw
        // nothing until find has caught up (its own task re-reads on the
        // same change).
        guard find.indexedHandwritingEpoch(of: page.id) == stamp.handwritingEpoch else {
            boxes = [:]
            return
        }
        if layout?.stamp != stamp {
            guard let renderer = session.environment?.renderer,
                  let read = try? await renderer.textLayout(for: page, includingHandwriting: true),
                  !Task.isCancelled else { return }
            layout = (stamp, read)
        }
        guard let layout else { return }
        boxes = Dictionary(zip(hits, layout.layout.boxes(for: hits.map(\.range))), uniquingKeysWith: { first, _ in first })
        announceCurrentHit()
    }

    /// Tells the page viewer the current hit is drawn and can be scrolled to.
    /// One turn of the run loop later, so the box has a frame to scroll to.
    private func announceCurrentHit() {
        guard let hit = find.current, hit.pageID == page.id, boxes[hit]?.isEmpty == false,
              find.shownFocus != find.focusRequest else { return }
        let request = find.focusRequest
        Task { @MainActor in
            await Task.yield()
            if find.focusRequest == request { find.shownFocus = request }
        }
    }
}

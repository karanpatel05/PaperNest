import SwiftUI
import PaperNestCore
import PaperNestRender
import PaperNestStore

/// Comparing this document with another: choosing the other, running the
/// comparison, and moving through its pages.
@MainActor @Observable
final class CompareModel {
    enum Mode: String, CaseIterable, Identifiable {
        case sideBySide, overlay, text
        var id: String { rawValue }
        var title: String {
            switch self {
            case .sideBySide: L10n.compareModeSideBySide
            case .overlay: L10n.compareModeOverlay
            case .text: L10n.compareModeText
            }
        }
    }

    enum Phase: Equatable {
        case choosing
        case comparing(Double)
        case done
        case failed
    }

    let session: LibrarySession
    private(set) var originalID: ItemID
    private(set) var newID: ItemID?
    /// Documents and notebooks with pages, other than the original.
    private(set) var candidates: [PaperNestCore.LibraryItem] = []
    private(set) var names: [ItemID: String] = [:]
    private(set) var phase: Phase = .choosing
    private(set) var comparison: DocumentComparison?
    private(set) var oldPages: [Page] = []
    private(set) var newPages: [Page] = []
    var position = 0
    var mode: Mode = .sideBySide
    private(set) var oldImage: CGImage?
    private(set) var newImage: CGImage?
    private(set) var overlayImage: CGImage?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Changes whenever a new comparison is shown, so pictures are drawn again.
    private(set) var generation = 0

    init(originalID: ItemID, session: LibrarySession) {
        self.originalID = originalID
        self.session = session
    }

    private var store: LibraryStore? { session.environment?.store }

    func loadCandidates() async {
        guard let store, let summaries = try? await store.items(in: .all) else { return }
        names = Dictionary(summaries.map { ($0.item.id, $0.item.name) }, uniquingKeysWith: { first, _ in first })
        candidates = summaries.filter { $0.item.kind != .file && $0.pageCount > 0 && $0.item.id != originalID }.map(\.item)
    }

    func name(of id: ItemID?) -> String? { id.flatMap { names[$0] } }

    func choose(_ id: ItemID) {
        newID = id
        start()
    }

    /// The new document becomes the original and the original the new.
    func swap() {
        guard let newID else { return }
        (originalID, self.newID) = (newID, originalID)
        candidates = candidates.filter { $0.id != originalID }
        Task { await loadCandidates() }
        start()
    }

    func cancel() { task?.cancel() }

    private func start() {
        task?.cancel()
        guard let store, let renderer = session.environment?.renderer, let newID else { return }
        let originalID = originalID
        phase = .comparing(0)
        comparison = nil
        oldImage = nil; newImage = nil; overlayImage = nil
        let progress: @Sendable (Double) async -> Void = { [weak self] share in await self?.report(share) }
        task = Task { [weak self] in
            do {
                let old = try await store.pages(of: originalID)
                let new = try await store.pages(of: newID)
                let result = try await DocumentComparer(renderer: renderer).compare(old: old, new: new, progress: progress)
                guard let self, !Task.isCancelled else { return }
                self.oldPages = old
                self.newPages = new
                self.comparison = result
                self.position = result.pages.firstIndex { $0.kind != .same || $0.moved } ?? 0
                self.generation += 1
                self.phase = .done
            } catch is CancellationError {
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.phase = .failed
            }
        }
    }

    private func report(_ share: Double) {
        if case .comparing = phase { phase = .comparing(share) }
    }

    var current: PageComparison? {
        guard let pages = comparison?.pages, pages.indices.contains(position) else { return nil }
        return pages[position]
    }

    var oldPage: Page? { current?.oldIndex.flatMap { oldPages.indices.contains($0) ? oldPages[$0] : nil } }
    var newPage: Page? { current?.newIndex.flatMap { newPages.indices.contains($0) ? newPages[$0] : nil } }

    func step(_ delta: Int) {
        guard let count = comparison?.pages.count, count > 0 else { return }
        position = min(max(position + delta, 0), count - 1)
    }

    /// Draws the pages on screen, and their overlay.
    func loadImages() async {
        guard let renderer = session.environment?.renderer else { return }
        let old = oldPage, new = newPage
        oldImage = nil; newImage = nil; overlayImage = nil
        var oldImage: CGImage?, newImage: CGImage?
        if let old { oldImage = try? await renderer.renderThumbnail(old, maxPixelSize: 1000) }
        if let new { newImage = try? await renderer.renderThumbnail(new, maxPixelSize: 1000) }
        guard !Task.isCancelled else { return }
        self.oldImage = oldImage
        self.newImage = newImage
        if let a = self.oldImage, let b = self.newImage { overlayImage = DocumentComparer.overlay(old: a, new: b) }
    }
}

/// One mark drawn over a page: a rectangle in its source space and what it means.
struct CompareMark: Hashable {
    enum Style { case removed, added, picture }
    var rect: NormalizedRect
    var style: Style

    var color: Color {
        switch style {
        case .removed: .red
        case .added: .green
        case .picture: .orange
        }
    }
}

struct CompareSheet: View {
    @State private var model: CompareModel
    @Environment(\.dismiss) private var dismiss

    init(originalID: ItemID, session: LibrarySession) {
        _model = State(initialValue: CompareModel(originalID: originalID, session: session))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    documents
                    switch model.phase {
                    case .choosing: EmptyView()
                    case .comparing(let share):
                        ProgressView(L10n.compareComparing, value: share)
                            .accessibilityIdentifier("compare-progress")
                    case .failed:
                        Label { Text(L10n.compareFailed) } icon: { Image(systemName: "exclamationmark.triangle") }
                            .accessibilityIdentifier("compare-failed")
                    case .done:
                        if let comparison = model.comparison { results(comparison) }
                    }
                }
                .padding(16)
            }
            .navigationTitle(L10n.compareTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.done) { model.cancel(); dismiss() }.accessibilityIdentifier("compare-done")
                }
            }
            .task { await model.loadCandidates() }
            .onDisappear { model.cancel() }
            .task(id: "\(model.generation)-\(model.position)") { await model.loadImages() }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 680)
        #endif
    }

    // MARK: - Choosing

    private var documents: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent(L10n.compareOriginal) {
                Text(verbatim: model.name(of: model.originalID) ?? "").lineLimit(2)
            }
            .accessibilityIdentifier("compare-original")
            // The whole row opens the list, not only the name at its end.
            NavigationLink {
                CompareDocumentList(model: model)
            } label: {
                HStack(spacing: 8) {
                    Text(L10n.compareNew).foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Text(verbatim: model.name(of: model.newID) ?? L10n.compareChoose)
                        .lineLimit(2).multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("compare-choose")
            if model.newID != nil {
                Button { model.swap() } label: { Label(L10n.compareSwap, systemImage: "arrow.up.arrow.down") }
                    .accessibilityIdentifier("compare-swap")
                    .disabled(model.phase != .done && model.phase != .failed)
            }
        }
    }

    // MARK: - Results

    private func results(_ comparison: DocumentComparison) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            summary(comparison)
            if comparison.isIdentical {
                // Only claim the same words where words were compared.
                Text(comparison.anyComparedOnlyByPicture ? L10n.compareIdenticalByLook : L10n.compareIdentical)
                    .accessibilityIdentifier("compare-identical")
            }
            Picker(L10n.compareTitle, selection: $model.mode) {
                ForEach(CompareModel.Mode.allCases) { Text(verbatim: $0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("compare-mode")
            .accessibilityValue(model.mode.rawValue)
            if let page = model.current {
                pageHeader(page, count: comparison.pages.count)
                pageBody(page)
                navigation(count: comparison.pages.count)
            }
            Text(L10n.compareLimits).font(.app(.footnote)).foregroundStyle(.secondary)
                .accessibilityIdentifier("compare-limits")
        }
    }

    private func summary(_ comparison: DocumentComparison) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.compareSummaryText(comparison.textChangeCount))
            Text(L10n.compareSummaryPicture(comparison.pictureDifferenceCount))
            Text(L10n.compareSummaryPages(comparison.addedPageCount, comparison.removedPageCount, comparison.movedPageCount))
        }
        .font(.app(.subheadline))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("compare-summary")
        .accessibilityValue(summaryValue(comparison))
    }

    private func summaryValue(_ comparison: DocumentComparison) -> String {
        [("text", comparison.textChangeCount), ("picture", comparison.pictureDifferenceCount),
         ("added", comparison.addedPageCount), ("removed", comparison.removedPageCount),
         ("moved", comparison.movedPageCount)].map { $0.0 + ":" + String($0.1) }.joined(separator: " ")
    }

    private func pageHeader(_ page: PageComparison, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.comparePosition(model.position + 1, count)).font(.app(.headline))
                    .accessibilityIdentifier("compare-position")
                    .accessibilityValue(String(model.position + 1) + "/" + String(count))
                Spacer()
                Text(verbatim: status(page)).font(.app(.subheadline).weight(.semibold))
                    .foregroundStyle(page.kind == .same && !page.moved ? Color.secondary : Color.primary)
                    .accessibilityIdentifier("compare-page-status")
                    .accessibilityValue(page.kind.rawValue + (page.moved ? ",moved" : ""))
            }
            Text(verbatim: pageNumbers(page)).font(.app(.footnote)).foregroundStyle(.secondary)
            if let method = page.method {
                Text(verbatim: describe(method)).font(.app(.footnote))
                    .accessibilityIdentifier("compare-method")
                    .accessibilityValue(methodValue(method))
            }
            if page.sizesDiffer {
                Text(L10n.compareSizesDiffer).font(.app(.footnote)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func pageBody(_ page: PageComparison) -> some View {
        switch model.mode {
        case .sideBySide:
            HStack(alignment: .top, spacing: 10) {
                ComparePageView(page: model.oldPage, image: model.oldImage, marks: oldMarks(page),
                                title: L10n.compareOriginal, identifier: "compare-old-page")
                ComparePageView(page: model.newPage, image: model.newImage, marks: newMarks(page),
                                title: L10n.compareNew, identifier: "compare-new-page")
            }
            legend
        case .overlay:
            overlay(page)
        case .text:
            textChanges(page)
        }
    }

    @ViewBuilder
    private func overlay(_ page: PageComparison) -> some View {
        if let image = model.overlayImage {
            Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                // A decorative image is hidden from VoiceOver; this one is the view itself.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: L10n.compareModeOverlay))
                .accessibilityIdentifier("compare-overlay")
            HStack(spacing: 16) {
                legendItem(L10n.compareLegendRemoved, .red)
                legendItem(L10n.compareLegendAdded, .green)
            }
        } else if model.oldPage == nil || model.newPage == nil {
            // Only one document has this page: nothing to lay over it.
            ComparePageView(page: model.oldPage ?? model.newPage, image: model.oldImage ?? model.newImage, marks: [],
                            title: model.oldPage == nil ? L10n.compareNew : L10n.compareOriginal,
                            identifier: "compare-overlay")
        } else {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func textChanges(_ page: PageComparison) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if page.textChanges.isEmpty {
                Text(L10n.compareNoTextChanges).foregroundStyle(.secondary)
                    .accessibilityIdentifier("compare-no-text-changes")
            }
            ForEach(Array(page.textChanges.enumerated()), id: \.offset) { index, change in
                VStack(alignment: .leading, spacing: 4) {
                    if !change.removed.isEmpty {
                        Text(L10n.compareRemovedWords(change.removed.map(\.text).joined(separator: " ")))
                            .foregroundStyle(.red)
                    }
                    if !change.added.isEmpty {
                        Text(L10n.compareAddedWords(change.added.map(\.text).joined(separator: " ")))
                            .foregroundStyle(.green)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("compare-change-\(index + 1)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(L10n.compareLegendRemoved, .red)
            legendItem(L10n.compareLegendAdded, .green)
            legendItem(L10n.compareLegendPicture, .orange)
        }
        .font(.app(.caption))
    }

    private func legendItem(_ title: String, _ color: Color) -> some View {
        Label { Text(verbatim: title) } icon: {
            RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.35))
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(color, lineWidth: 1.5)).frame(width: 14, height: 10)
        }
        .font(.app(.caption))
    }

    private func navigation(count: Int) -> some View {
        HStack {
            Button { model.step(-1) } label: { Label(L10n.comparePrevious, systemImage: "chevron.left") }
                .disabled(model.position == 0)
                .accessibilityIdentifier("compare-previous")
            Spacer()
            Button { model.step(1) } label: { Label(L10n.compareNext, systemImage: "chevron.right") }
                .disabled(model.position >= count - 1)
                .accessibilityIdentifier("compare-next")
        }
    }

    // MARK: - Words

    private func oldMarks(_ page: PageComparison) -> [CompareMark] {
        page.textChanges.flatMap { $0.removed.map { CompareMark(rect: $0.box, style: .removed) } }
            + page.oldPictureRegions.map { CompareMark(rect: $0, style: .picture) }
    }

    private func newMarks(_ page: PageComparison) -> [CompareMark] {
        page.textChanges.flatMap { $0.added.map { CompareMark(rect: $0.box, style: .added) } }
            + page.newPictureRegions.map { CompareMark(rect: $0, style: .picture) }
    }

    private func status(_ page: PageComparison) -> String {
        let kind = switch page.kind {
        case .same: L10n.compareKindSame
        case .changed: L10n.compareKindChanged
        case .added: L10n.compareKindAdded
        case .removed: L10n.compareKindRemoved
        }
        return page.moved ? "\(kind) · \(L10n.compareMoved)" : kind
    }

    private func pageNumbers(_ page: PageComparison) -> String {
        switch (page.oldIndex, page.newIndex) {
        case let (old?, new?): L10n.comparePages(old + 1, new + 1)
        case let (old?, nil): L10n.compareOnlyOriginal(old + 1)
        case let (nil, new?): L10n.compareOnlyNew(new + 1)
        case (nil, nil): ""
        }
    }

    private func describe(_ method: PageComparison.Method) -> String {
        switch method {
        case .text(.embedded): L10n.compareMethodText
        case .text(.recognized): L10n.compareMethodRecognized
        case .picture(.noTextOnEither): L10n.compareMethodPictureBoth
        case .picture(.noTextOnOld): L10n.compareMethodPictureOld
        case .picture(.noTextOnNew): L10n.compareMethodPictureNew
        }
    }

    private func methodValue(_ method: PageComparison.Method) -> String {
        switch method {
        case .text(let source): "text-\(source.rawValue)"
        case .picture(let reason): "picture-\(reason.rawValue)"
        }
    }
}

/// A page with its marks drawn over it, through its geometry.
private struct ComparePageView: View {
    let page: Page?
    let image: CGImage?
    let marks: [CompareMark]
    let title: String
    let identifier: String

    var body: some View {
        VStack(spacing: 6) {
            Text(verbatim: title).font(.app(.caption).weight(.semibold)).foregroundStyle(.secondary)
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: title))
                .accessibilityIdentifier(identifier)
                .accessibilityValue(page == nil ? "missing" : String(marks.count))
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if let page, let image {
            Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                .overlay {
                    Canvas { context, size in
                        let pageSize = page.geometry.pageSize
                        guard pageSize.width > 0, pageSize.height > 0 else { return }
                        let scale = CGAffineTransform(scaleX: size.width / pageSize.width, y: size.height / pageSize.height)
                        for mark in marks {
                            let rect = page.geometry.pageRect(forNormalizedSourceRect: mark.rect).applying(scale).insetBy(dx: -1.5, dy: -1.5)
                            context.fill(Path(rect), with: .color(mark.color.opacity(0.25)))
                            context.stroke(Path(rect), with: .color(mark.color), lineWidth: 1.5)
                        }
                    }
                }
                .background(Color.white)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        } else if page == nil {
            Text(L10n.compareMissing).font(.app(.footnote)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 160)
                .background(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4])))
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 160)
        }
    }
}

/// The library's other documents, to compare with.
private struct CompareDocumentList: View {
    let model: CompareModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if model.candidates.isEmpty {
                Text(L10n.compareNoDocuments).foregroundStyle(.secondary)
            }
            ForEach(model.candidates, id: \.id) { item in
                Button {
                    model.choose(item.id)
                    dismiss()
                } label: {
                    HStack {
                        Text(verbatim: item.name)
                        Spacer()
                        if item.id == model.newID { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
                .accessibilityIdentifier("compare-document")
            }
        }
        .navigationTitle(L10n.compareChooseTitle)
    }
}

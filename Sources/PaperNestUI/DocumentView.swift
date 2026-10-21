import PaperNestCore
import PaperNestStore
import SwiftUI

/// An open document. Mac and iPad show a page strip beside the page; iPhone
/// (compact width) shows the page full width with a thumbnail scroller
/// below and page actions in the bottom toolbar.
struct DocumentView: View {
    @State private var model: DocumentModel
    /// Runs "Add Pages" imports, including password prompts and errors.
    @State private var importModel: LibraryModel
    @Environment(\.undoManager) private var undoManager
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var isShowingExport = false
    @State private var isShowingAddPages = false
    @State private var isShowingAdjustments = false
    @State private var isShowingPageOrganizer = false
    @State private var isShowingCrop = false
    @State private var zoom: CGFloat = 1

    init(itemID: ItemID, session: LibrarySession) {
        _model = State(initialValue: DocumentModel(itemID: itemID, session: session))
        _importModel = State(initialValue: LibraryModel(session: session))
    }

    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        Group {
            if !model.hasLoaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.pages.isEmpty {
                ContentUnavailableView {
                    Label(L10n.emptyDocumentTitle, systemImage: "doc")
                } description: {
                    Text(L10n.emptyDocumentMessage)
                } actions: {
                    Button(L10n.addPages) { isShowingAddPages = true }
                }
            } else if isCompact {
                VStack(spacing: 0) {
                    PageViewer(model: model, zoom: $zoom, showsZoomButtons: false)
                    Divider()
                    PageScroller(model: model)
                }
            } else {
                HStack(spacing: 0) {
                    PageStrip(model: model, undoManager: undoManager)
                        .frame(width: 168)
                    Divider()
                    PageViewer(model: model, zoom: $zoom, showsZoomButtons: true)
                }
            }
        }
        .navigationTitle(model.item?.name ?? "")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbar }
        .task(id: model.session.changeToken) { await model.load() }
        #if DEBUG
        // Dev/screenshot hooks: `-PaperNestDebugShowExport YES`, `-PaperNestDebugShowCrop YES`.
        .task {
            isShowingExport = UserDefaults.standard.bool(forKey: "PaperNestDebugShowExport")
            isShowingCrop = UserDefaults.standard.bool(forKey: "PaperNestDebugShowCrop")
        }
        #endif
        .alert(model.presentedError?.title ?? "", isPresented: errorBinding, presenting: model.presentedError) { _ in
            Button(L10n.ok, role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
        .sheet(isPresented: $isShowingExport) {
            ExportLoader(itemID: model.itemID, currentPageID: model.selectedPageID)
        }
        .sheet(isPresented: $isShowingCrop) {
            if let page = model.selectedPage {
                CropEditor(page: page) { crop in
                    Task { await model.setCrop(crop, undoManager: undoManager) }
                }
            }
        }
        #if os(iOS)
        .sheet(isPresented: $isShowingPageOrganizer) {
            PageOrganizer(model: model, undoManager: undoManager)
        }
        #endif
        .fileImporter(isPresented: $isShowingAddPages, allowedContentTypes: LibraryView.importableTypes, allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            let after = model.selectedPageID
            Task { await importModel.importFiles(urls, into: model.itemID, after: after) }
        }
        .alert(importModel.presentedError?.title ?? "", isPresented: importErrorBinding, presenting: importModel.presentedError) { _ in
            Button(L10n.ok, role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
        .modifier(PasswordPrompt(model: importModel))
        .focusedSceneValue(\.documentCommands, DocumentCommandContext(
            model: model, undoManager: undoManager,
            showExport: { isShowingExport = true },
            showAddPages: { isShowingAddPages = true },
            showCrop: { isShowingCrop = true }
        ))
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        #if os(iOS)
        if isCompact {
            ToolbarItemGroup(placement: .bottomBar) {
                rotateLeftButton
                Spacer()
                rotateRightButton
                Spacer()
                cropButton
                Spacer()
                filterMenu
                Spacer()
                Button {
                    isShowingPageOrganizer = true
                } label: {
                    Label(L10n.pages, systemImage: "square.grid.2x2")
                }
                Spacer()
                deleteButton
            }
            ToolbarItemGroup(placement: .primaryAction) {
                addPagesButton
                exportButton
            }
        } else {
            ToolbarItemGroup(placement: .primaryAction) { allActions }
        }
        #else
        ToolbarItemGroup(placement: .primaryAction) { allActions }
        #endif
    }

    @ViewBuilder
    private var allActions: some View {
        rotateLeftButton
        rotateRightButton
        cropButton
        filterMenu
        deleteButton
        addPagesButton
        exportButton
    }

    private var rotateLeftButton: some View {
        Button {
            Task { await model.rotate(clockwise: false, undoManager: undoManager) }
        } label: {
            Label(L10n.rotateLeft, systemImage: "rotate.left")
        }
        .disabled(model.selectedPage == nil)
    }

    private var rotateRightButton: some View {
        Button {
            Task { await model.rotate(clockwise: true, undoManager: undoManager) }
        } label: {
            Label(L10n.rotateRight, systemImage: "rotate.right")
        }
        .disabled(model.selectedPage == nil)
    }

    private var cropButton: some View {
        Button {
            isShowingCrop = true
        } label: {
            Label(L10n.crop, systemImage: "crop")
        }
        .disabled(model.selectedPage == nil)
    }

    private var filterMenu: some View {
        Menu {
            Picker(L10n.filter, selection: filterBinding) {
                Text(L10n.filterOriginal).tag(PageFilter.original)
                Text(L10n.filterGrayscale).tag(PageFilter.grayscale)
                Text(L10n.filterBlackAndWhite).tag(PageFilter.blackAndWhite)
            }
            .pickerStyle(.inline)
            Divider()
            Button(L10n.adjustments) { isShowingAdjustments = true }
            Button(L10n.revertToOriginal) {
                Task { await model.revertToOriginal(undoManager: undoManager) }
            }
            .disabled(model.selectedPage?.transform == .identity)
        } label: {
            Label(L10n.filter, systemImage: "camera.filters")
        }
        .disabled(model.selectedPage == nil)
        .popover(isPresented: $isShowingAdjustments) {
            AdjustmentsPanel(model: model, undoManager: undoManager)
                .presentationCompactAdaptation(.sheet)
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            Task { await model.deleteSelectedPage(undoManager: undoManager) }
        } label: {
            Label(L10n.deletePage, systemImage: "trash")
        }
        .disabled(model.selectedPage == nil)
    }

    private var addPagesButton: some View {
        Button {
            isShowingAddPages = true
        } label: {
            Label(L10n.addPages, systemImage: "doc.badge.plus")
        }
    }

    private var exportButton: some View {
        Button {
            isShowingExport = true
        } label: {
            Label(L10n.export, systemImage: "square.and.arrow.up")
        }
        .disabled(model.pages.isEmpty)
    }

    private var filterBinding: Binding<PageFilter> {
        Binding(
            get: { model.selectedPage?.transform.filter ?? .original },
            set: { filter in Task { await model.setFilter(filter, undoManager: undoManager) } }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.presentedError != nil }, set: { if !$0 { model.presentedError = nil } })
    }

    private var importErrorBinding: Binding<Bool> {
        Binding(get: { importModel.presentedError != nil }, set: { if !$0 { importModel.presentedError = nil } })
    }
}

/// Thumbnails of every page in a vertical list; drag to reorder.
private struct PageStrip: View {
    @Bindable var model: DocumentModel
    let undoManager: UndoManager?

    var body: some View {
        List(selection: $model.selectedPageID) {
            ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
                VStack(spacing: 4) {
                    PageImageView(page: page, pixelSize: 260, accessibilityLabel: L10n.pageLabel(index + 1, of: model.pages.count))
                        .frame(maxHeight: 150)
                    Text(verbatim: "\(index + 1)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .tag(page.id)
            }
            .onMove { offsets, destination in
                Task { await model.movePages(from: offsets, to: destination, undoManager: undoManager) }
            }
        }
        .accessibilityLabel(L10n.pages)
    }
}

/// Compact-width page picker: a horizontal row of thumbnails.
private struct PageScroller: View {
    @Bindable var model: DocumentModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
                        let isSelected = page.id == model.selectedPageID
                        Button {
                            model.selectedPageID = page.id
                        } label: {
                            VStack(spacing: 2) {
                                PageImageView(page: page, pixelSize: 200, accessibilityLabel: L10n.pageLabel(index + 1, of: model.pages.count))
                                    .frame(height: 72)
                                    .overlay {
                                        if isSelected {
                                            Rectangle().strokeBorder(Theme.accent, lineWidth: 3)
                                        }
                                    }
                                Text(verbatim: "\(index + 1)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(isSelected ? Theme.accent : .secondary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .id(page.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .frame(height: 104)
            .background(.bar)
            .onChange(of: model.selectedPageID) { _, id in
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .accessibilityLabel(L10n.pages)
    }
}

#if os(iOS)
/// Compact-width page reordering: the full list in edit mode.
private struct PageOrganizer: View {
    @Bindable var model: DocumentModel
    let undoManager: UndoManager?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PageStrip(model: model, undoManager: undoManager)
                .environment(\.editMode, .constant(.active))
                .navigationTitle(L10n.pages)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.done) { dismiss() }
                    }
                }
        }
    }
}
#endif

/// The selected page, fitted to the available space and zoomable with
/// buttons/keyboard (Mac, iPad) or a pinch (trackpad, touch).
private struct PageViewer: View {
    @Bindable var model: DocumentModel
    @Binding var zoom: CGFloat
    let showsZoomButtons: Bool
    @Environment(\.displayScale) private var displayScale
    @State private var pinchBase: CGFloat?

    static let zoomSteps: [CGFloat] = [0.5, 0.75, 1, 1.5, 2, 3, 4]

    var body: some View {
        GeometryReader { proxy in
            if let page = model.selectedPage, let index = model.selectedIndex {
                let fitted = fittedSize(page.geometry.pageSize, in: proxy.size)
                let size = CGSize(width: fitted.width * zoom, height: fitted.height * zoom)
                ScrollView([.horizontal, .vertical]) {
                    PageImageView(page: page, pixelSize: max(size.width, size.height) * displayScale,
                                  accessibilityLabel: L10n.pageLabel(index + 1, of: model.pages.count))
                        .frame(width: size.width, height: size.height)
                        .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
                }
                .background(Color.secondary.opacity(0.08))
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let base = pinchBase ?? zoom
                            pinchBase = base
                            zoom = min(max(base * value.magnification, Self.zoomSteps.first!), Self.zoomSteps.last!)
                        }
                        .onEnded { _ in pinchBase = nil }
                )
            }
        }
        .toolbar {
            if showsZoomButtons {
                ToolbarItemGroup {
                    Button { step(-1) } label: { Label(L10n.zoomOut, systemImage: "minus.magnifyingglass") }
                        .keyboardShortcut("-", modifiers: .command)
                        .disabled(zoom <= Self.zoomSteps.first!)
                    Button { zoom = 1 } label: { Label(L10n.zoomToFit, systemImage: "arrow.up.left.and.down.right.magnifyingglass") }
                        .keyboardShortcut("0", modifiers: .command)
                    Button { step(1) } label: { Label(L10n.zoomIn, systemImage: "plus.magnifyingglass") }
                        .keyboardShortcut("+", modifiers: .command)
                        .disabled(zoom >= Self.zoomSteps.last!)
                }
            }
        }
        .onChange(of: model.selectedPageID) { zoom = 1 }
    }

    private func fittedSize(_ page: CGSize, in container: CGSize) -> CGSize {
        let inset: CGFloat = showsZoomButtons ? 32 : 12
        let available = CGSize(width: max(container.width - inset * 2, 50), height: max(container.height - inset * 2, 50))
        let scale = min(available.width / page.width, available.height / page.height)
        return CGSize(width: page.width * scale, height: page.height * scale)
    }

    private func step(_ direction: Int) {
        let current = Self.zoomSteps.firstIndex { $0 >= zoom } ?? Self.zoomSteps.count - 1
        let next = min(max(current + direction, 0), Self.zoomSteps.count - 1)
        zoom = Self.zoomSteps[next]
    }
}

/// Brightness and contrast, committed when a slider is released so each
/// adjustment is one undoable, durably saved edit.
private struct AdjustmentsPanel: View {
    let model: DocumentModel
    let undoManager: UndoManager?
    @State private var brightness: Double = 0
    @State private var contrast: Double = 1

    var body: some View {
        Form {
            Slider(value: $brightness, in: -0.5...0.5) { editing in
                if !editing { commit() }
            } label: {
                Text(L10n.brightness)
            }
            Slider(value: $contrast, in: 0.5...2) { editing in
                if !editing { commit() }
            } label: {
                Text(L10n.contrast)
            }
            Button(L10n.resetAdjustments) {
                brightness = 0
                contrast = 1
                commit()
            }
        }
        .padding()
        .frame(minWidth: 300)
        .onAppear {
            brightness = model.selectedPage?.transform.brightness ?? 0
            contrast = model.selectedPage?.transform.contrast ?? 1
        }
    }

    private func commit() {
        Task { await model.setAdjustments(brightness: brightness, contrast: contrast, undoManager: undoManager) }
    }
}

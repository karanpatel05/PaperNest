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
    @State private var stampPage: Page?
    @State private var shapePage: Page?
    @State private var commentsPage: Page?
    /// Why the file picker was opened. Kept apart from the presented flag:
    /// SwiftUI clears the flag when the picker closes, before calling the
    /// completion, so a purpose stored in the flag would already be gone
    /// (that turned a replace into an add).
    @State private var filePurpose: PageSourcePurpose = .add
    @State private var isShowingFilePicker = false
    #if os(iOS)
    /// Why the document camera is open.
    @State private var cameraPurpose: PageSourcePurpose?
    #endif
    @State private var isShowingAdjustments = false
    @State private var isShowingPageOrganizer = false
    @State private var isShowingCrop = false
    @State private var annotationPage: Page?
    @State private var managedMarkupPage: Page?
    @State private var notebookPageRequest: NotebookPageRequest?
    /// iPhone: the strip of filter previews above the tools.
    @State private var isShowingFilterStrip = false
    @State private var isRenaming = false
    /// iPad: the PencilKit ink layer is over the page (pass 7).
    @State private var isMarkingUp = false
    @State private var isFingerDrawing = false
    @State private var renameText = ""
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
                    Button(L10n.addPages) { openFilePicker(.add) }
                }
            } else if isCompact {
                VStack(spacing: 0) {
                    PageViewer(model: model, zoom: $zoom, showsZoomButtons: false,
                               isMarkingUp: isMarkingUp, fingerDrawing: isFingerDrawing, undoManager: undoManager)
                    pageNavigation
                }
            } else {
                HStack(spacing: 0) {
                    PageStrip(model: model, undoManager: undoManager)
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            addPagesMenu {
                                Image(systemName: "plus")
                                    .font(.body.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 32)
                            }
                            .menuIndicator(.hidden)
                            .buttonStyle(.bordered)
                            .padding(10)
                            .background(Theme.surface)
                            .accessibilityLabel(L10n.addOrReplacePages)
                            .accessibilityIdentifier("strip-add-pages")
                        }
                        .frame(width: 168)
                    Divider()
                    PageViewer(model: model, zoom: $zoom, showsZoomButtons: true, isMarkingUp: isMarkingUp,
                               fingerDrawing: isFingerDrawing, undoManager: undoManager)
                }
            }
        }
        .navigationTitle(model.item?.name ?? "")
        // The title's ▾ menu, as in the mockups.
        .toolbarTitleMenu { titleMenu }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        // iPad: title at the leading edge, editing tools in the middle.
        .toolbarRole(isCompact ? .automatic : .editor)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isCompact, !isNotebook, !model.pages.isEmpty {
                VStack(spacing: 0) {
                    if isShowingFilterStrip { filterStrip }
                    compactTools
                }
            }
        }
        #endif
        .safeAreaInset(edge: .top, spacing: 0) {
            if isNotebook { notebookTools }
        }
        .toolbar { toolbar }
        .alert(L10n.renameTitle, isPresented: $isRenaming) {
            TextField(L10n.renamePlaceholder, text: $renameText)
            Button(L10n.cancel, role: .cancel) {}
            Button(L10n.ok) {
                let name = renameText
                Task { await model.rename(to: name) }
            }
        }
        .task(id: model.session.changeToken) { await model.load() }
        .task(id: model.selectedPageID) { await model.loadSelectedPageObjects() }
        #if DEBUG
        // Dev/screenshot hooks: `-PaperNestDebugShowExport YES`, `-PaperNestDebugShowCrop YES`,
        // `-PaperNestDebugShowMarkup YES` (iPad).
        .task {
            isShowingExport = UserDefaults.standard.bool(forKey: "PaperNestDebugShowExport")
            isShowingCrop = UserDefaults.standard.bool(forKey: "PaperNestDebugShowCrop")
            isMarkingUp = UserDefaults.standard.bool(forKey: "PaperNestDebugShowMarkup")
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
        .sheet(item: $notebookPageRequest) { request in
            NotebookPageSheet(model: model, request: request, undoManager: undoManager)
        }
        .sheet(item: $stampPage) { page in
            ShapeAnnotationSheet(model: model, page: page, undoManager: undoManager, stampsOnly: true)
        }
        .sheet(item: $shapePage) { page in
            ShapeAnnotationSheet(model: model, page: page, undoManager: undoManager)
        }
        .sheet(item: $commentsPage) { page in
            PageCommentsSheet(model: model, pageID: page.id, undoManager: undoManager)
        }
        .sheet(item: $annotationPage) { page in
            TextAnnotationSheet(model: model, pageID: page.id, undoManager: undoManager)
        }
        .sheet(item: $managedMarkupPage) { page in
            MarkupManagerSheet(model: model, pageID: page.id, undoManager: undoManager)
        }
        #if os(iOS)
        .sheet(isPresented: $isShowingPageOrganizer) {
            PageOrganizer(model: model, undoManager: undoManager)
        }
        #endif
        // Adding or replacing a page needs something we can make pages from.
        .fileImporter(isPresented: $isShowingFilePicker, allowedContentTypes: LibraryView.pageTypes,
                      allowsMultipleSelection: filePurpose != .replace) { result in
            let purpose = filePurpose
            guard case .success(let urls) = result else {
                importModel.reportPickerFailure()
                return
            }
            guard !urls.isEmpty else { return }
            switch purpose {
            case .replace:
                Task {
                    await importModel.prepareFile(urls[0]) { prepared in
                        await model.replaceSelectedPage(with: prepared, undoManager: undoManager)
                    }
                }
            case .add:
                let after = model.selectedPageID
                Task { await importModel.importFiles(urls, into: model.itemID, after: after) }
            }
        }
        #if os(iOS)
        .fullScreenCover(item: $cameraPurpose) { purpose in
            DocumentCameraView { outcome in
                cameraPurpose = nil
                switch outcome {
                case .scanned(let images):
                    let name = model.item?.name ?? ""
                    Task {
                        await importModel.prepareImages(images, name: name) { prepared in
                            switch purpose {
                            case .add: await model.insertPages(prepared)
                            case .replace: await model.replaceSelectedPage(with: prepared, undoManager: undoManager)
                            }
                        }
                    }
                case .cancelled:
                    break
                case .failed:
                    model.presentedError = PresentedError(title: L10n.genericErrorTitle, message: L10n.scanFailed)
                }
            }
            .ignoresSafeArea()
        }
        #endif
        .alert(importModel.presentedError?.title ?? "", isPresented: importErrorBinding, presenting: importModel.presentedError) { _ in
            Button(L10n.ok, role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
        .modifier(PasswordPrompt(model: importModel))
        .focusedSceneValue(\.documentCommands, DocumentCommandContext(
            model: model, undoManager: undoManager,
            showExport: { isShowingExport = true },
            showAddPages: { openFilePicker(.add) },
            showReplacePage: { openFilePicker(.replace) },
            showCrop: { isShowingCrop = true }
        ))
    }

    private var isNotebook: Bool { model.item?.kind == .notebook }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if isNotebook {
            ToolbarItem(placement: .primaryAction) { exportButton }
        } else {
            #if os(iOS)
            if isCompact {
                ToolbarItemGroup(placement: .primaryAction) {
                    addPagesButton
                    exportButton
                }
            } else {
                ToolbarItemGroup(placement: .secondaryAction) { editingTools }
                ToolbarItemGroup(placement: .primaryAction) { trailingActions }
            }
            #else
            ToolbarItemGroup(placement: .principal) { editingTools }
            ToolbarItemGroup(placement: .primaryAction) { trailingActions }
            #endif
        }
    }

    @ViewBuilder
    private var titleMenu: some View {
        Button {
            renameText = model.item?.name ?? ""
            isRenaming = true
        } label: {
            Label(L10n.rename, systemImage: "pencil")
        }
        Button {
            Task { await model.setFavorite(!(model.item?.isFavorite ?? false)) }
        } label: {
            if model.item?.isFavorite == true {
                Label(L10n.removeFavorite, systemImage: "star.slash")
            } else {
                Label(L10n.addFavorite, systemImage: "star")
            }
        }
        Button {
            isShowingExport = true
        } label: {
            Label(L10n.export, systemImage: "square.and.arrow.up")
        }
        .disabled(model.pages.isEmpty)
    }

    /// The page-editing tools (the mockups' tool group): Markup (iPad), then
    /// rotate, crop, filter.
    @ViewBuilder
    private var editingTools: some View {
        #if os(iOS)
        Toggle(isOn: $isMarkingUp) {
            Label(L10n.markup, systemImage: "pencil.tip.crop.circle")
        }
        .toggleStyle(.button)
        .disabled(model.selectedPage == nil)
        .accessibilityIdentifier("editor-markup")
        if isMarkingUp {
            // The touch alternative to Apple Pencil (and how the Simulator draws).
            Toggle(isOn: $isFingerDrawing) {
                Label(L10n.drawWithFinger, systemImage: "hand.draw")
            }
            .toggleStyle(.button)
            .accessibilityIdentifier("editor-finger-drawing")
        }
        #endif
        rotateMenu
        cropButton
        filterMenu
    }

    /// Keep notebook actions in the content area so native toolbars never
    /// collapse them into an overflow menu. The row scrolls at narrow widths.
    private var notebookTools: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 18) {
                shapeButton
                stampButton
                commentsButton
                annotateTextButton
                manageMarkupButton
                NotebookHistoryActions(undoManager: undoManager, busy: model.isChangingNotebookPage)
                editingTools
                recognizeTextButton
                addPagesItems
                #if os(iOS)
                Button { isShowingPageOrganizer = true } label: {
                    Label(L10n.pages, systemImage: "square.grid.2x2")
                }
                .accessibilityIdentifier("editor-pages")
                #endif
                deleteButton
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .labelStyle(EditorToolLabelStyle())
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
        .background(Theme.surface)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityIdentifier("notebook-tool-bar")
    }

    /// A labeled Export button, then everything else in ⋯.
    @ViewBuilder
    private var trailingActions: some View {
        exportButton
            .labelStyle(.titleAndIcon)
        Menu {
            NotebookHistoryActions(undoManager: undoManager, busy: model.isChangingNotebookPage)
            Divider()
            addPagesItems
            Divider()
            recognizeTextButton
            annotateTextButton
            manageMarkupButton
            shapeButton
            stampButton
            commentsButton
            Divider()
            deleteButton
        } label: {
            Label(L10n.more, systemImage: "ellipsis.circle")
        }
        .accessibilityIdentifier("editor-more")
    }

    @ViewBuilder
    private var recognizeTextButton: some View {
        if let progress = model.recognitionProgress {
            Text(L10n.recognizeProgress(min(progress.done + 1, max(progress.total, 1)), max(progress.total, 1)))
        } else {
            Button {
                Task { await model.recognizeText() }
            } label: {
                Label(L10n.recognizeText, systemImage: "text.viewfinder")
            }
            .disabled(model.pages.isEmpty)
            .accessibilityIdentifier("editor-recognize")
        }
    }

    private var annotateTextButton: some View {
        Button { annotationPage = model.selectedPage } label: {
            Label(L10n.annotateText, systemImage: "highlighter")
        }
        .disabled(model.selectedPage == nil || model.isRecognizing)
        .accessibilityIdentifier("editor-annotate")
    }

    private var stampButton: some View {
        Button { stampPage = model.selectedPage } label: {
            Label(L10n.stampTitle, systemImage: "seal")
        }
        .disabled(model.selectedPage == nil || model.isChangingNotebookPage)
        .accessibilityIdentifier("editor-stamps")
    }

    private var shapeButton: some View {
        Button { shapePage = model.selectedPage } label: {
            Label(L10n.shapeTitle, systemImage: "square.on.circle")
        }
        .disabled(model.selectedPage == nil || model.isChangingNotebookPage)
        .accessibilityIdentifier("editor-shapes")
    }

    private var commentsButton: some View {
        Button { commentsPage = model.selectedPage } label: {
            Label(L10n.comments, systemImage: "text.bubble")
        }
        .disabled(model.selectedPage == nil || model.isChangingNotebookPage)
        .accessibilityIdentifier("editor-comments")
    }

    private var manageMarkupButton: some View {
        Button { managedMarkupPage = model.selectedPage } label: {
            Label(L10n.manageMarkup, systemImage: "pencil.and.outline")
        }
        .disabled(model.selectedPage == nil)
        .accessibilityIdentifier("editor-manage-markup")
    }

    private var pageNavigation: some View {
        VStack(spacing: 0) {
            if let index = model.selectedIndex {
                Text(L10n.pageLabel(index + 1, of: model.pages.count))
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .padding(.top, 10)
            }
            PageScroller(model: model)
        }
        .background(Theme.surface)
    }

    #if os(iOS)
    private var compactTools: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 0) { compactToolButtons }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) { compactToolButtons }
            }
        }
        .labelStyle(EditorToolLabelStyle())
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.surface)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private var compactToolButtons: some View {
        rotateMenu
        cropButton
        Button {
            withAnimation(.snappy) { isShowingFilterStrip.toggle() }
        } label: {
            Label(L10n.filter, systemImage: "camera.filters")
        }
        .disabled(model.selectedPage == nil)
        .accessibilityValue(isShowingFilterStrip ? L10n.selectedPage : "")
        .accessibilityAddTraits(isShowingFilterStrip ? .isSelected : [])
        .accessibilityIdentifier("editor-filter")
        Button { isShowingPageOrganizer = true } label: {
            Label(L10n.pages, systemImage: "square.grid.2x2")
        }
        Menu {
            NotebookHistoryActions(undoManager: undoManager, busy: model.isChangingNotebookPage)
            Divider()
            recognizeTextButton
            annotateTextButton
            manageMarkupButton
            shapeButton
            stampButton
            commentsButton
            Divider()
            deleteButton
        } label: {
            Label(L10n.more, systemImage: "ellipsis.circle")
        }
        .accessibilityIdentifier("editor-more")
    }

    /// Live previews of the selected page in each filter, then Adjustments
    /// and Revert. Only real filters appear (no invented presets).
    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                if let page = model.selectedPage {
                    ForEach([PageFilter.original, .grayscale, .blackAndWhite], id: \.self) { filter in
                        filterPreview(page, filter)
                    }
                }
                Divider().frame(height: 72)
                VStack(spacing: 8) {
                    Button(L10n.adjustments) { isShowingAdjustments = true }
                        .popover(isPresented: $isShowingAdjustments) {
                            AdjustmentsPanel(model: model, undoManager: undoManager)
                                .presentationCompactAdaptation(.sheet)
                        }
                    Button(L10n.revertToOriginal) {
                        Task { await model.revertToOriginal(undoManager: undoManager) }
                    }
                    .disabled(model.selectedPage?.transform == .identity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Theme.surface)
        .overlay(alignment: .top) { Divider() }
        .accessibilityIdentifier("filter-strip")
    }

    private func filterPreview(_ page: Page, _ filter: PageFilter) -> some View {
        let isSelected = page.transform.filter == filter
        var preview = page
        preview.transform.filter = filter
        return Button {
            Task { await model.setFilter(filter, undoManager: undoManager) }
        } label: {
            VStack(spacing: 5) {
                PageImageView(page: preview, pixelSize: 180)
                    .frame(width: 56, height: 72)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 2)
                    }
                Text(filter.title)
                    .font(.caption2.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.accent : .primary)
                    .fixedSize()
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(filter.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("filter-\(filter)")
    }
    #endif

    private var rotateMenu: some View {
        Menu {
            rotateLeftButton
            rotateRightButton
        } label: {
            Label(L10n.rotate, systemImage: "rotate.right")
        }
        .disabled(model.selectedPage == nil)
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
        .accessibilityIdentifier("editor-crop")
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
        .accessibilityIdentifier("editor-delete-page")
    }

    /// Add pages (camera on iPhone/iPad, files everywhere) or replace the
    /// selected page with a new capture.
    private var addPagesButton: some View {
        addPagesMenu {
            Label(L10n.addOrReplacePages, systemImage: "doc.badge.plus")
        }
    }

    private func addPagesMenu(@ViewBuilder label: () -> some View) -> some View {
        Menu { addPagesItems } label: { label() }
            .accessibilityIdentifier("editor-add-pages")
    }

    @ViewBuilder
    private var addPagesItems: some View {
        if model.item?.kind == .notebook {
            Button {
                let template: PageTemplate
                if case .template(let paper) = model.selectedPage?.content { template = paper }
                else { template = .blank }
                notebookPageRequest = NotebookPageRequest(after: model.selectedPageID, template: template)
            } label: {
                Label(L10n.addNotebookPage, systemImage: "doc.badge.plus")
            }
            .accessibilityIdentifier("editor-add-notebook-page")
            .disabled(model.isChangingNotebookPage)
        }
        #if os(iOS)
        Button {
            cameraPurpose = .add
        } label: {
            Label(L10n.scanPages, systemImage: "doc.viewfinder")
        }
        .disabled(!DocumentCameraView.isSupported)
        #endif
        Button {
            openFilePicker(.add)
        } label: {
            Label(L10n.addPages, systemImage: "doc.badge.plus")
        }
        if !isNotebook { Divider() }
        #if os(iOS)
        Button {
            cameraPurpose = .replace
        } label: {
            Label(L10n.rescanPage, systemImage: "arrow.triangle.2.circlepath.camera")
        }
        .disabled(!DocumentCameraView.isSupported || model.selectedPage == nil)
        #endif
        Button {
            openFilePicker(.replace)
        } label: {
            Label(L10n.replacePageWithFile, systemImage: "arrow.triangle.2.circlepath.doc.on.clipboard")
        }
        .disabled(model.selectedPage == nil)
    }

    private func openFilePicker(_ purpose: PageSourcePurpose) {
        filePurpose = purpose
        isShowingFilePicker = true
    }

    private var exportButton: some View {
        Button {
            isShowingExport = true
        } label: {
            Label(L10n.export, systemImage: "square.and.arrow.up")
        }
        .disabled(model.pages.isEmpty)
        .accessibilityIdentifier("editor-export")
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

/// Text stays visible below each tool on phones. At larger type sizes the
/// row scrolls instead of squeezing the translated labels into tiny targets.
private struct EditorToolLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 6) {
            configuration.icon.font(.title3).frame(height: 24)
            configuration.title.font(.caption2.weight(.medium)).fixedSize(horizontal: true, vertical: false)
        }
        .frame(minWidth: 60, minHeight: 48)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

/// What a picked file or camera capture is for.
enum PageSourcePurpose: Hashable, Identifiable {
    case add
    case replace
    var id: Self { self }
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
        .scrollContentBackground(.hidden)
        .background(Theme.surface)
        .accessibilityLabel(L10n.pages)
    }
}

/// Compact-width page picker: a horizontal row of thumbnails.
private struct PageScroller: View {
    @Bindable var model: DocumentModel
    @ScaledMetric(relativeTo: .caption2) private var numberSpace: CGFloat = 22

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
                        let isSelected = page.id == model.selectedPageID
                        Button {
                            model.selectedPageID = page.id
                        } label: {
                            VStack(spacing: 5) {
                                PageImageView(page: page, pixelSize: 200, accessibilityLabel: L10n.pageLabel(index + 1, of: model.pages.count))
                                    .frame(height: 72)
                                    .overlay {
                                        if isSelected {
                                            Rectangle().strokeBorder(Theme.accent, lineWidth: 2)
                                        }
                                    }
                                Text(verbatim: "\(index + 1)")
                                    .font(.caption2.monospacedDigit().weight(isSelected ? .bold : .regular))
                                    .foregroundStyle(isSelected ? Theme.accent : .secondary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L10n.pageLabel(index + 1, of: model.pages.count))
                        .accessibilityValue(isSelected ? L10n.selectedPage : "")
                        .accessibilityIdentifier("page-thumbnail-\(index + 1)")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .id(page.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .frame(height: 88 + numberSpace)
            .background(Theme.surface)
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
    var isMarkingUp = false
    var fingerDrawing = false
    var undoManager: UndoManager?
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
                                  accessibilityLabel: L10n.pageLabel(index + 1, of: model.pages.count),
                                  includesInk: !isMarkingUp)
                        .accessibilityIdentifier("document-page-image")
                        .accessibilityValue(L10n.strokeCount(model.selectedPageObjects.filter {
                            guard $0.pageID == page.id else { return false }
                            if case .ink = $0.payload { return true }
                            return false
                        }.count))
                        .frame(width: size.width, height: size.height)
                        #if os(iOS)
                        .overlay {
                            if isMarkingUp {
                                let pageSize = page.geometry.pageSize
                                // Only this page's objects: right after a page switch the
                                // previous page's are still loaded.
                                InkCanvas(pageID: page.id, objects: model.selectedPageObjects.filter { $0.pageID == page.id },
                                          sourceToView: page.geometry.sourceToPage.concatenating(
                                              CGAffineTransform(scaleX: size.width / pageSize.width, y: size.height / pageSize.height)),
                                          fingerDrawing: fingerDrawing, documentUndoManager: undoManager) { saving, deleting in
                                    Task { await model.changeInk(on: page.id, saving: saving, deleting: deleting, undoManager: undoManager) }
                                }
                            }
                        }
                        #endif
                        .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
                }
                .background(Theme.canvas)
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Hidden while marking up: the tool palette covers this spot
            // (pinch still zooms).
            if showsZoomButtons, !isMarkingUp {
                HStack(spacing: 18) {
                    Button { step(-1) } label: { Label(L10n.zoomOut, systemImage: "minus.magnifyingglass") }
                        .keyboardShortcut("-", modifiers: .command)
                        .disabled(zoom <= Self.zoomSteps.first!)
                    Button { zoom = 1 } label: { Label(L10n.zoomToFit, systemImage: "arrow.up.left.and.down.right.magnifyingglass") }
                        .keyboardShortcut("0", modifiers: .command)
                    Button { step(1) } label: { Label(L10n.zoomIn, systemImage: "plus.magnifyingglass") }
                        .keyboardShortcut("+", modifiers: .command)
                        .disabled(zoom >= Self.zoomSteps.last!)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Theme.canvas)
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

extension PageFilter {
    var title: String {
        switch self {
        case .original: L10n.filterOriginal
        case .grayscale: L10n.filterGrayscale
        case .blackAndWhite: L10n.filterBlackAndWhite
        }
    }
}

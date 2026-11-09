import PaperNestCore
import PaperNestStore
import PhotosUI
import SwiftUI

/// An open document. Mac and iPad show a page strip beside the page; iPhone
/// (compact width) shows the page full width with a thumbnail scroller
/// below and page actions in the bottom toolbar.
struct DocumentView: View {
    private let retainedState: DocumentEditorState?
    private let workspaceHeader: AnyView?
    @State private var model: DocumentModel
    /// Runs "Add Pages" imports, including password prompts and errors.
    @State private var importModel: LibraryModel
    @Environment(\.undoManager) private var nativeUndoManager
    private var undoManager: UndoManager? { retainedState?.undoManager ?? nativeUndoManager }
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var isShowingExport = false
    @State private var isShowingPDFTools = false
    @State private var isShowingThumbnails = true
    @State private var isAppendingNotebookPage = false
    @State private var inspectorTool: InspectorTool?
    @State private var signatureDrafts: [PageID: SignatureDraft] = [:]
    @State private var formSession: PDFFormSession?
    @State private var pageToolBusy = false

    private enum InspectorTool { case signature(Page), form, pages }
    @State private var stampPage: Page?
    @State private var shapePage: Page?
    @State private var commentsPage: Page?
    @State private var signaturePage: Page?
    @State private var isShowingPDFForm = false
    /// Why the file picker was opened. Kept apart from the presented flag:
    /// SwiftUI clears the flag when the picker closes, before calling the
    /// completion, so a purpose stored in the flag would already be gone
    /// (that turned a replace into an add).
    @State private var filePurpose: PageSourcePurpose = .add
    @State private var isShowingFilePicker = false
    #if os(iOS)
    /// Why the document camera is open.
    @State private var cameraPurpose: PageSourcePurpose?
    @State private var photoCameraPage: Page?
    #endif
    @State private var isShowingAdjustments = false
    @State private var isShowingPageOrganizer = false
    @State private var isShowingOutline = false
    @State private var commandContext: DocumentCommandContext?
    @State private var editingOwner = UUID()
    @State private var textSession: InlineTextSession
    @Environment(DocumentEditingGuard.self) private var editingGuard
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var inkTool: MacMarkupTool = .pen
    @State private var lassoMode: PageSelectionMode = .freehand
    @State private var lassoSelectAllRequest = 0
    @State private var didChooseInitialTool = false
    @State private var inkColor = RGBAColor(red: 0, green: 0, blue: 0, alpha: 1)
    @State private var isShowingInkSettings = false
    @State private var inkWeight: MarkupWeight = .medium
    @State private var penWidth = 2.0
    @State private var highlighterWidth = 20.0
    @State private var eraserWidth = 36.0
    @State private var eraserMode: InkEraserMode = .precision
    @State private var isShowingImagePicker = false
    @State private var isShowingPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoTargetPage: Page?
    @State private var isLoadingPhoto = false
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

    init(itemID: ItemID, session: LibrarySession, retainedState: DocumentEditorState? = nil,
         workspaceHeader: AnyView? = nil) {
        self.workspaceHeader = workspaceHeader
        self.retainedState = retainedState
        let document = retainedState?.model ?? DocumentModel(itemID: itemID, session: session)
        _zoom = State(initialValue: retainedState?.zoom ?? 1)
        _model = State(initialValue: document)
        #if os(iOS)
        _isShowingPDFTools = State(initialValue: UIDevice.current.userInterfaceIdiom == .pad)
        #else
        _isShowingPDFTools = State(initialValue: true)
        #endif
        _textSession = State(initialValue: retainedState?.textSession ?? InlineTextSession(model: document))
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
                    // Retain the user's thumbnail preference, but give the
                    // focused text editor room above the compact keyboard.
                    if isShowingThumbnails && !textSession.isSelected { pageNavigation }
                    PageViewer(model: model, textSession: textSession, zoom: $zoom, showsZoomButtons: false,
                               isMarkingUp: isMarkingUp, fingerDrawing: isFingerDrawing, undoManager: undoManager,
                               inkTool: inkTool, inkColor: inkColor, inkWidth: drawingWidth, eraserMode: eraserMode,
                               usesStudioTools: true, lassoMode: lassoMode, selectAllRequest: lassoSelectAllRequest,
                               onLeaveSelection: { isMarkingUp = false },
                               appendNotebookPage: isNotebook ? { appendContinuation(after: $0) } : nil,
                               canAppendNotebookPage: !isToolBusy && !textSession.isSelected)
                }
            } else {
                HStack(spacing: 0) {
                    if isShowingThumbnails {
                    PageStrip(model: model, undoManager: undoManager, beforeSelection: { await textSession.finish(undoManager: undoManager) })
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
                        .frame(width: 112)
                        .disabled(textSession.isSelected)
                    Divider()
                    }
                    VStack(spacing: 0) {
                        PageViewer(model: model, textSession: textSession, zoom: $zoom, showsZoomButtons: true, isMarkingUp: isMarkingUp,
                                   fingerDrawing: isFingerDrawing, undoManager: undoManager,
                                   inkTool: inkTool, inkColor: inkColor,
                                   inkWidth: drawingWidth, eraserMode: eraserMode, usesStudioTools: true, lassoMode: lassoMode, selectAllRequest: lassoSelectAllRequest,
                               onLeaveSelection: { isMarkingUp = false },
                               appendNotebookPage: isNotebook ? { appendContinuation(after: $0) } : nil,
                               canAppendNotebookPage: !isToolBusy && !textSession.isSelected)
                    }
                }
            }
        }
        .onChange(of: zoom) { _, value in retainedState?.zoom = value }
        .navigationTitle(model.item?.name ?? "")
        // The title's ▾ menu, as in the mockups.
        .toolbarTitleMenu { titleMenu }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        // iPad: title at the leading edge, editing tools in the middle.
        .toolbarRole(isCompact ? .automatic : .editor)
        #endif
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if let workspaceHeader { workspaceHeader }
                if !model.pages.isEmpty { NotebookToolbar(editor: self) }
                if textSession.hasFailure && (model.selectedPageID != textSession.page?.id ||
                    !model.pages.contains(where: { $0.id == textSession.page?.id })) {
                    InlineTextRecoveryBar(session: textSession, undoManager: undoManager)
                        .background(Theme.surface)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !model.pages.isEmpty && !(isCompact && textSession.isSelected) {
                studioPalette.opacity(textSession.isSelected ? 0 : 1)
                    .allowsHitTesting(!textSession.isSelected)
                    .accessibilityHidden(textSession.isSelected)
            }
        }
        .toolbar { toolbar }
        .inspector(isPresented: $isShowingPDFTools) {
            PDFToolsSidebar(editor: self)
                .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
        }
        .navigationBarBackButtonHidden()
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await textSession.commitAndFlush(undoManager: undoManager) } }
        }
        .onAppear {
            editingGuard.owner = editingOwner
            editingGuard.finish = { await finishEditing() }
            commandContext = makeCommandContext()
        }
        .onDisappear {
            Task { await textSession.commitAndFlush(undoManager: undoManager) }
            if editingGuard.owner == editingOwner {
                editingGuard.owner = nil
                editingGuard.finish = nil
            }
        }
        .alert(L10n.renameTitle, isPresented: $isRenaming) {
            TextField(L10n.renamePlaceholder, text: $renameText)
            Button(L10n.cancel, role: .cancel) {}
            Button(L10n.ok) {
                let name = renameText
                Task { await model.rename(to: name) }
            }
        }
        .onChange(of: model.hasLoaded, initial: true) { _, loaded in
            guard loaded, !didChooseInitialTool else { return }
            didChooseInitialTool = true
            if isNotebook { inkTool = .lasso; isMarkingUp = true }
        }
        .task(id: model.session.changeToken) { await model.load() }
        .task(id: model.selectedPageID) { await model.loadSelectedPageObjects() }
        #if DEBUG
        // Dev/screenshot hooks: `-PaperNestDebugShowExport YES`, `-PaperNestDebugShowCrop YES`,
        // `-PaperNestDebugShowMarkup YES` (iPad), `-PaperNestDebugShowOutline YES`.
        .task {
            isShowingExport = UserDefaults.standard.bool(forKey: "PaperNestDebugShowExport")
            isShowingCrop = UserDefaults.standard.bool(forKey: "PaperNestDebugShowCrop")
            if UserDefaults.standard.bool(forKey: "PaperNestDebugShowMarkup") { isMarkingUp = true }
            isShowingOutline = UserDefaults.standard.bool(forKey: "PaperNestDebugShowOutline")
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
        .fileImporter(isPresented: $isShowingImagePicker,
                      allowedContentTypes: [.image], onCompletion: insertPickedImage)
        .photosPicker(isPresented: $isShowingPhotoPicker, selection: $selectedPhoto,
                      matching: .images, preferredItemEncoding: .compatible)
        .task(id: selectedPhoto) {
            guard let selectedPhoto, let page = photoTargetPage else { return }
            isLoadingPhoto = true
            defer { isLoadingPhoto = false }
            do {
                guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else {
                    importModel.reportPickerFailure()
                    return
                }
                try Task.checkCancellation()
                try await model.addImage(data, named: nil, to: page, undoManager: undoManager)
            } catch is CancellationError {
                // Leaving the editor cancels the load without inserting anything.
            } catch {
                model.presentedError = .saveFailed()
            }
        }
        .sheet(isPresented: $isShowingOutline) {
            DocumentOutlineSheet(model: model) { id in
                Task { if await textSession.finish(undoManager: undoManager) { model.selectedPageID = id } }
            }
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
        .sheet(isPresented: $isShowingPDFForm) {
            PDFFormSheet(model: model, onClose: { clearFormDraft(); isShowingPDFForm = false },
                         retainedSession: retainedState?.formSession ?? formSession) { armText() }
        }
        .sheet(item: $signaturePage) { page in
            SignatureSheet(model: model, page: page, undoManager: undoManager,
                           onClose: { clearSignatureDraft(page.id); signaturePage = nil },
                           retainedDraft: retainedState?.signatureDrafts[page.id] ?? signatureDrafts[page.id])
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
        .sheet(isPresented: $isShowingPageOrganizer) {
            DocumentPagesSheet(model: model, undoManager: undoManager)
        }
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
        .fullScreenCover(item: $photoCameraPage) { page in
            PhotoCameraView { outcome in
                photoCameraPage = nil
                switch outcome {
                case .captured(let data):
                    isLoadingPhoto = true
                    Task {
                        defer { isLoadingPhoto = false }
                        do {
                            try await model.addImage(data, named: nil, to: page, undoManager: undoManager)
                        } catch {
                            model.presentedError = .saveFailed()
                        }
                    }
                case .cancelled:
                    break
                case .failed:
                    model.presentedError = PresentedError(title: L10n.genericErrorTitle,
                                                         message: L10n.photoCaptureFailed)
                }
            }
            .ignoresSafeArea()
        }
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
        .focusedSceneValue(\.documentCommands, commandContext)
    }

    private var isToolBusy: Bool {
        (retainedState?.isToolBusy ?? false) || pageToolBusy || isAppendingNotebookPage ||
        signatureDrafts.values.contains(where: { $0.busy }) || (formSession?.saving ?? false)
    }

    private func appendContinuation(after pageID: PageID) {
        guard !isToolBusy, !editingGuard.isClosing, !textSession.isSelected else { return }
        isAppendingNotebookPage = true
        Task {
            defer { isAppendingNotebookPage = false }
            guard await textSession.finish(undoManager: undoManager), !editingGuard.isClosing else { return }
            do { try await model.appendNotebookPage(after: pageID, undoManager: undoManager) }
            catch { model.presentedError = .saveFailed() }
        }
    }

    private func finishEditing() async -> Bool {
        guard !isToolBusy else { return false }
        return await textSession.finish(undoManager: undoManager)
    }

    private func clearSignatureDraft(_ id: PageID) {
        retainedState?.signatureDrafts[id] = nil
        signatureDrafts[id] = nil
    }

    private func clearFormDraft() {
        retainedState?.formSession = nil
        formSession = nil
    }

    /// Panel operations may mark themselves busy before invoking this gate.
    private func finishTextForPanelAction() async -> Bool {
        guard !editingGuard.isClosing else { return false }
        guard await textSession.finish(undoManager: undoManager) else { return false }
        return !editingGuard.isClosing
    }

    private func finishForAction() async -> Bool {
        guard !editingGuard.isClosing else { return false }
        guard await finishEditing() else { return false }
        return !editingGuard.isClosing
    }

    private func finishThen(_ action: @escaping () -> Void) {
        Task { if await finishForAction() { action() } }
    }

    private func makeCommandContext() -> DocumentCommandContext {
        DocumentCommandContext(model: model, undoManager: undoManager,
            showExport: { finishThen { isShowingExport = true } },
            showAddPages: { finishThen { openFilePicker(.add) } },
            showReplacePage: { finishThen { openFilePicker(.replace) } },
            showCrop: { finishThen { isShowingCrop = true } },
            showOutline: { finishThen { isShowingOutline = true } },
            showTextBox: { armText() },
            showInsertImage: { finishThen { isShowingImagePicker = true } },
            beforeAction: { await finishForAction() })
    }

    private var isNotebook: Bool { model.item?.kind == .notebook }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                Task { if await finishEditing() { dismiss() } }
            } label: { Label(L10n.inlineBack, systemImage: "chevron.left") }
            .accessibilityIdentifier("editor-back")
            if usesPDFToolsSidebar { pageSidebarToggle }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            exportButton
            if usesPDFToolsSidebar { editorMoreMenu }
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
            Task { if await textSession.finish(undoManager: undoManager) { isShowingExport = true } }
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
        #if os(macOS)
        // The Mac has no PencilKit, so drawing is this app's own canvas; the
        // toggle is the same idea as the iPad's.
        Toggle(isOn: $isMarkingUp) {
            Label(L10n.markup, systemImage: "pencil.tip.crop.circle")
        }
        .toggleStyle(.button)
        .disabled(model.selectedPage == nil)
        .accessibilityIdentifier("editor-markup")
        #endif
        rotateMenu
        cropButton
        filterMenu
    }

    #if os(macOS)
    /// Pen or highlighter, how thick, and what colour. Shown only while the
    /// Mac canvas is up, in the content area rather than the toolbar, where a
    /// colour picker has no room.
    private var macInkTools: some View {
        HStack(spacing: 16) {
            Picker(L10n.markup, selection: $inkTool) {
                Text(L10n.inkPen).tag(MacMarkupTool.pen)
                Text(L10n.inkHighlighter).tag(MacMarkupTool.highlighter)
                Text(L10n.inkEraser).tag(MacMarkupTool.eraser)
                Text(L10n.inkLasso).tag(MacMarkupTool.lasso)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 420)
            .accessibilityIdentifier("ink-tool")
            if inkTool.ink != nil {
                // Thin, Medium and Thick rather than numbers, because what
                // they are worth depends on the tool: see `width(for:)`.
                Picker(L10n.shapeWidth, selection: $inkWeight) {
                    Text(L10n.shapeThin).tag(MarkupWeight.thin)
                    Text(L10n.shapeMedium).tag(MarkupWeight.medium)
                    Text(L10n.shapeThick).tag(MarkupWeight.thick)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                .accessibilityIdentifier("ink-width")
                MarkupColorPicker(color: $inkColor)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.surface)
    }
    #endif

    /// A real View boundary defers the toolbar's large generic value until
    /// SwiftUI evaluates its own body. A computed property or Group evaluates
    /// it inside DocumentView.body, exhausting the device's debug-build stack.
    private struct NotebookToolbar: View {
        let editor: DocumentView

        var body: some View { editor.notebookTools }
    }

    /// Keep notebook actions in the content area so native toolbars never
    /// collapse them into an overflow menu. The row scrolls at narrow widths.
    private var notebookTools: some View {
        GeometryReader { toolbarGeometry in
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                if !usesPDFToolsSidebar { pageSidebarToggle }
                studioTool(.pen, title: L10n.inkPen, icon: .pen)
                studioTool(.eraser, title: L10n.inkEraser, icon: .eraser)
                studioTool(.highlighter, title: L10n.inkHighlighter, icon: .highlighter)
                studioTool(.lasso, title: L10n.inkLasso, icon: .lasso)
                Rectangle().fill(Theme.separator).frame(width: 1, height: 22).padding(.horizontal, 3)
                    .accessibilityHidden(true)
                imageButton
                textBoxButton
                if !usesPDFToolsSidebar { editorMoreMenu }
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(6)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.separator.opacity(0.65), lineWidth: 0.75) }
            .frame(minWidth: toolbarGeometry.size.width)
        }
        }
        .frame(height: 60)
        .buttonStyle(.plain)
        .foregroundStyle(Theme.primaryText)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Theme.libraryBackground)
        .accessibilityIdentifier("notebook-tool-bar")
    }

    private var pageSidebarToggle: some View {
        Button { isShowingThumbnails.toggle() } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 19)).frame(width: 44, height: 44)
                .background(isShowingThumbnails && !usesPDFToolsSidebar ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
        }
        .accessibilityLabel(isShowingThumbnails ? L10n.hidePageThumbnails : L10n.showPageThumbnails)
        .accessibilityValue(isShowingThumbnails ? L10n.selectionOn : L10n.selectionOff)
        .accessibilityIdentifier("editor-toggle-thumbnails")
        .foregroundStyle(usesPDFToolsSidebar
            ? (isShowingThumbnails ? Theme.accent : Theme.secondaryText) : Theme.primaryText)
        .help(isShowingThumbnails ? L10n.hidePageThumbnails : L10n.showPageThumbnails)
    }

    private var usesPDFToolsSidebar: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        true
        #endif
    }

    @ViewBuilder
    private var editorMoreMenu: some View {
        if usesPDFToolsSidebar {
            Button { isShowingPDFTools.toggle() } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(isShowingPDFTools ? Theme.accent : Theme.secondaryText)
                    .contentShape(Rectangle())
            }
            .disabled(isToolBusy)
            .accessibilityIdentifier("studio-more-tools")
            .accessibilityLabel(isShowingPDFTools ? L10n.hidePDFTools : L10n.showPDFTools)
            .accessibilityValue(isShowingPDFTools ? L10n.selectedPage : "")
            .accessibilityAddTraits(isShowingPDFTools ? .isSelected : [])
            .help(isShowingPDFTools ? L10n.hidePDFTools : L10n.showPDFTools)
        } else {
            Menu { editorMoreActions } label: {
                if isNotebook {
                    NotebookToolFace(kind: .more).accessibilityLabel(L10n.more)
                } else {
                    Label(L10n.more, systemImage: "ellipsis")
                        .labelStyle(.iconOnly).font(.system(size: 20)).frame(width: 44, height: 44)
                }
            }
            .accessibilityIdentifier("studio-more-tools")
            .accessibilityLabel(L10n.more)
            .help(L10n.more)
            .disabled(textSession.isSelected)
        }
    }

    // Shared actions retain the existing sheets, history and subscription checks.
    @ViewBuilder
    private var editorMoreActions: some View {
        if !isNotebook {
            Button { openInspectorTool(.form) } label: {
                Label(L10n.formTitle, systemImage: "list.bullet.rectangle")
            }.accessibilityIdentifier("editor-fill-form")
        }
        Button { if let page = model.selectedPage { openInspectorTool(.signature(page)) } } label: {
            Label(L10n.signatureTitle, systemImage: "signature")
        }.accessibilityIdentifier("editor-signature")
        shapeButton
        Divider()
        editingTools
        stampButton
        commentsButton
        annotateTextButton
        manageMarkupButton
        recognizeTextButton
        Divider()
        addPagesItems
        Button { openInspectorTool(.pages) } label: {
            Label(L10n.pages, systemImage: "square.grid.2x2")
        }.accessibilityIdentifier("editor-pages")
        deleteButton
    }

    private func openInspectorTool(_ tool: InspectorTool) {
        finishThen {
            switch tool {
            case .signature(let page):
                if let retainedState {
                    if retainedState.signatureDrafts[page.id] == nil { retainedState.signatureDrafts[page.id] = SignatureDraft(model: model, page: page) }
                } else if signatureDrafts[page.id] == nil { signatureDrafts[page.id] = SignatureDraft(model: model, page: page) }
            case .form:
                if let retainedState {
                    if retainedState.formSession == nil { retainedState.formSession = PDFFormSession(itemID: model.itemID, library: model.session) }
                } else if formSession == nil { formSession = PDFFormSession(itemID: model.itemID, library: model.session) }
            case .pages: break
            }
            if usesPDFToolsSidebar {
                inspectorTool = tool
                isShowingPDFTools = true
            } else {
                switch tool {
                case .signature(let page): signaturePage = page
                case .form: isShowingPDFForm = true
                case .pages: isShowingPageOrganizer = true
                }
            }
        }
    }

    /// A separate evaluation boundary keeps the large editor value off the
    /// iPad debug-build stack, just like NotebookToolbar.
    private struct PDFToolsSidebar: View {
        let editor: DocumentView

        var body: some View {
            Group {
                switch editor.inspectorTool {
                case .signature(let page):
                    SignatureSheet(model: editor.model, page: page, undoManager: editor.undoManager,
                                   isEmbedded: true, onClose: { editor.clearSignatureDraft(page.id); editor.inspectorTool = nil },
                                   beforeAction: { await editor.finishTextForPanelAction() },
                                   retainedDraft: editor.retainedState?.signatureDrafts[page.id] ?? editor.signatureDrafts[page.id])
                        .id(page.id)
                case .form:
                    PDFFormSheet(model: editor.model, isEmbedded: true,
                                 onClose: { editor.clearFormDraft(); editor.inspectorTool = nil },
                                 beforeAction: { await editor.finishTextForPanelAction() },
                                 retainedSession: editor.retainedState?.formSession ?? editor.formSession) { editor.armText() }
                case .pages:
                    DocumentPagesSheet(model: editor.model, undoManager: editor.undoManager,
                                       isEmbedded: true, onClose: { editor.inspectorTool = nil },
                                       beforeAction: { await editor.finishTextForPanelAction() },
                                       onBusyChange: { editor.pageToolBusy = $0; editor.retainedState?.pageToolBusy = $0 })
                case nil:
                    toolList
                }
            }
        }

        private var toolList: some View {
            VStack(spacing: 0) {
                HStack {
                    Text(L10n.pdfTools).font(.headline)
                    Spacer()
                    Button { editor.isShowingPDFTools = false } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(editor.isToolBusy)
                    .accessibilityLabel(L10n.hidePDFTools)
                    .accessibilityIdentifier("pdf-tools-close")
                }
                .padding(.horizontal, 16)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        editor.editorMoreActions
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(PDFToolRowStyle())
                    .disabled(editor.textSession.isSelected)
                    .padding(12)
                }
                .accessibilityIdentifier("pdf-tools-list")
            }
            .foregroundStyle(Theme.primaryText)
            .background(Theme.libraryBackground)
        }
    }

    private struct PDFToolRowStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.body)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 3)
                .foregroundStyle(configuration.role == .destructive ? Color.red : Theme.primaryText)
                .background(configuration.isPressed ? Theme.selection : Theme.surface,
                            in: RoundedRectangle(cornerRadius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .opacity(isEnabled ? 1 : 0.45)
        }
    }

    private func studioTool(_ tool: MacMarkupTool, title: String, icon: NotebookToolIcon.Kind) -> some View {
        Button {
            Task {
                guard await textSession.finish(undoManager: undoManager) else { return }
                if isMarkingUp && inkTool == tool { isShowingInkSettings = true }
                inkTool = tool
                isMarkingUp = true
                #if os(iOS)
                if UIDevice.current.userInterfaceIdiom == .phone { isFingerDrawing = true }
                #endif
            }
        } label: {
            NotebookToolFace(kind: icon, selected: isMarkingUp && inkTool == tool)
        }
        .disabled(model.selectedPage == nil)
        .accessibilityIdentifier("studio-tool-\(tool.rawValue)")
        .accessibilityLabel(title)
        .help(title)
        .popover(isPresented: Binding(
            get: { isShowingInkSettings && inkTool == tool },
            set: { isShowingInkSettings = $0 }
        ), arrowEdge: .top) {
            NotebookInkSettings(tool: inkTool, width: studioWidth, eraserMode: $eraserMode, color: studioColor,
                                opacity: $inkColor.alpha, fingerDrawing: $isFingerDrawing,
                                selectionMode: $lassoMode, selectAll: {
                                    isShowingInkSettings = false; lassoSelectAllRequest += 1
                                }) {
                isShowingInkSettings = false
            }
            .presentationCompactAdaptation(.popover)
        }
        .accessibilityValue(isMarkingUp && inkTool == tool ? L10n.selectionOn : L10n.selectionOff)
    }

    private var studioWidth: Binding<Double> {
        inkTool == .eraser ? $eraserWidth : inkTool == .highlighter ? $highlighterWidth : $penWidth
    }

    private var drawingWidth: Double {
        studioWidth.wrappedValue
    }

    /// Swatches/custom colors change hue without resetting the chosen opacity.
    private var studioColor: Binding<RGBAColor> {
        Binding(get: { inkColor }, set: { value in
            var color = value
            color.alpha = inkColor.alpha
            inkColor = color
        })
    }

    private func isStudioColor(_ color: RGBAColor) -> Bool {
        inkColor.red == color.red && inkColor.green == color.green && inkColor.blue == color.blue
    }

    private var studioToolIcon: NotebookToolIcon.Kind {
        switch inkTool {
        case .pen: .pen
        case .highlighter: .highlighter
        case .eraser: .eraser
        case .lasso: .lasso
        }
    }

    private var studioPalette: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                NotebookHistoryActions(undoManager: undoManager, busy: model.isChangingNotebookPage,
                                       historyRevision: model.historyRevision,
                                       beforeAction: { await textSession.finish(undoManager: undoManager) })
                    .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                PageZoomControls(zoom: $zoom)
                Divider().frame(height: 28)
                Button { isMarkingUp.toggle() } label: {
                    Group {
                        if isMarkingUp { NotebookToolIcon(kind: studioToolIcon) }
                        else { Image(systemName: "hand.draw").font(.system(size: 20, weight: .regular)) }
                    }
                        .foregroundStyle(isMarkingUp ? Theme.accent : Theme.primaryText)
                        .frame(width: 44, height: 44)
                        .background(isMarkingUp ? Theme.selection : .clear, in: Circle())
                }.accessibilityLabel(L10n.markup)
                    .accessibilityValue(isMarkingUp ? L10n.selectionOn : L10n.selectionOff)
                    .accessibilityIdentifier("studio-drawing-toggle")
                if inkTool.ink != nil {
                    Button { isShowingInkSettings = true } label: {
                        Capsule().fill(inkColor.swiftUIColor)
                            .frame(width: 32, height: max(2, drawingWidth / 2))
                            .frame(width: 44, height: 44)
                    }.accessibilityLabel(L10n.studioToolSettings)
                    ForEach(MarkupColorPicker.presets, id: \.id) { preset in
                        Button { studioColor.wrappedValue = preset.color } label: {
                            Circle().fill(preset.color.swiftUIColor).frame(width: 24, height: 24)
                                .padding(5)
                                .overlay { Circle().strokeBorder(isStudioColor(preset.color) ? Theme.accent : .clear, lineWidth: 2) }
                                .frame(width: 44, height: 44)
                        }.accessibilityLabel(preset.name)
                            .accessibilityValue(isStudioColor(preset.color) ? L10n.selectionOn : L10n.selectionOff)
                            .accessibilityIdentifier("studio-color-\(preset.id)")
                    }
                }
                Button { isShowingInkSettings = true } label: {
                    Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
                }.accessibilityLabel(L10n.studioToolSettings)
                    .accessibilityIdentifier("studio-tool-settings")

            }.padding(8)
        }
        .buttonStyle(.plain).foregroundStyle(Theme.primaryText)
        .background(Theme.surface, in: Capsule())
        .shadow(color: Theme.paperShadow, radius: 12, y: 4)
        .frame(maxWidth: 650)
        .padding(12)
    }

    /// A labeled Export button, then everything else in ⋯.
    @ViewBuilder
    private var trailingActions: some View {
        exportButton
            .labelStyle(.titleAndIcon)
        Menu {
            NotebookHistoryActions(undoManager: undoManager, busy: model.isChangingNotebookPage,
                                   historyRevision: model.historyRevision,
                                       beforeAction: { await textSession.finish(undoManager: undoManager) })
            Divider()
            addPagesItems
            Divider()
            recognizeTextButton
            annotateTextButton
            manageMarkupButton
            shapeButton
            stampButton
            textBoxButton
            imageButton
            commentsButton
            Divider()
            outlineButton
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
        Button { isMarkingUp = false; shapePage = model.selectedPage } label: {
            Label(L10n.shapeTitle, systemImage: "square.on.circle")
        }
        .disabled(model.selectedPage == nil || model.isChangingNotebookPage)
        .accessibilityIdentifier("editor-shapes")
    }

    /// Reads a picked image and places it on the selected page.
    ///
    /// A method rather than a closure in the body: the type-checker gave up on
    /// that expression once this was inlined in the modifier chain.
    private func insertPickedImage(_ result: Result<URL, Error>) {
        guard case .success(let url) = result, let page = model.selectedPage else { return }
        Task {
            guard let importer = importModel.environment?.importer,
                  let data = try? importer.loadData(.file(url)) else {
                importModel.reportPickerFailure()
                return
            }
            try? await model.addImage(data, named: url.lastPathComponent, to: page,
                                      undoManager: undoManager)
        }
    }

    private var imageButton: some View {
        Menu {
            #if os(iOS)
            Button {
                guard let page = model.selectedPage else { return }
                isMarkingUp = false
                isLoadingPhoto = true
                Task {
                    defer { isLoadingPhoto = false }
                    guard await PhotoCameraView.requestAccess() else {
                        model.presentedError = PresentedError(title: L10n.genericErrorTitle,
                                                             message: L10n.photoCameraPermission)
                        return
                    }
                    photoCameraPage = page
                }
            } label: {
                Label(L10n.takePhoto, systemImage: "camera")
            }
            .disabled(!PhotoCameraView.isSupported)
            .accessibilityIdentifier("editor-image-camera")
            .accessibilityValue(PhotoCameraView.isSupported ? L10n.takePhoto : L10n.scanUnsupported)
            #endif
            Button {
                isMarkingUp = false
                selectedPhoto = nil
                photoTargetPage = model.selectedPage
                isShowingPhotoPicker = true
            } label: {
                Label(L10n.importPhotos, systemImage: "photo.on.rectangle")
            }
            .accessibilityIdentifier("editor-image-photos")
            Button { isMarkingUp = false; isShowingImagePicker = true } label: {
                Label(L10n.importFiles, systemImage: "folder")
            }
            .accessibilityIdentifier("editor-image-files")
        } label: {
            NotebookToolFace(kind: .image).accessibilityLabel(L10n.insertImage)
        }
        .disabled(model.selectedPage == nil || model.isChangingNotebookPage || isLoadingPhoto)
        .accessibilityIdentifier("editor-insert-image")
        .accessibilityLabel(L10n.insertImage)
        .help(L10n.insertImage)
    }

    private var textBoxButton: some View {
        Button { armText() } label: {
            NotebookToolFace(kind: .text, selected: textSession.isPlacing || textSession.isSelected)
        }
        .disabled(model.selectedPage == nil || model.isChangingNotebookPage)
        .accessibilityIdentifier("editor-text-box")
        .accessibilityLabel(L10n.textBox)
        .help(L10n.textBox)
        .background(!isNotebook && (textSession.isPlacing || textSession.isSelected) ? Theme.selection : .clear,
                    in: RoundedRectangle(cornerRadius: 16))
        .accessibilityValue(textSession.isPlacing || textSession.isSelected ? L10n.selectionOn : L10n.selectionOff)
    }

    private func armText() {
        Task {
            guard await finishForAction() else { return }
            isMarkingUp = false
            textSession.isPlacing = true
        }
    }

    private var outlineButton: some View {
        Button { isShowingOutline = true } label: {
            Label(L10n.outline, systemImage: "list.bullet.indent")
        }
        .disabled(model.pages.isEmpty)
        .accessibilityIdentifier("editor-outline")
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
            HStack(spacing: 0) {
                PageScroller(model: model, beforeSelection: { await textSession.finish(undoManager: undoManager) })
                addPagesMenu {
                    Label(L10n.addPages, systemImage: "plus")
                        .labelStyle(EditorToolLabelStyle())
                        .padding(8).background(Theme.selection, in: RoundedRectangle(cornerRadius: 12))
                }.padding(.trailing, 12).disabled(textSession.isSelected).accessibilityIdentifier("scan-add-page")
            }
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
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: Theme.paperShadow, radius: 10, y: 3)
        .padding(10).background(Theme.libraryBackground)
    }

    @ViewBuilder
    private var compactToolButtons: some View {
        cropButton
        rotateMenu
        Button {
            withAnimation(.snappy) { isShowingFilterStrip.toggle() }
        } label: {
            Label(L10n.filter, systemImage: "camera.filters")
        }
        .disabled(model.selectedPage == nil)
        .accessibilityValue(isShowingFilterStrip ? L10n.selectedPage : "")
        .accessibilityAddTraits(isShowingFilterStrip ? .isSelected : [])
        .accessibilityIdentifier("editor-filter")
        Button { isShowingAdjustments = true } label: {
            Label(L10n.adjustments, systemImage: "sparkles")
        }.popover(isPresented: $isShowingAdjustments) {
            AdjustmentsPanel(model: model, undoManager: undoManager)
                .presentationCompactAdaptation(.sheet)
        }
        .accessibilityIdentifier("editor-adjustments")
        recognizeTextButton
        Menu {
            Button { openInspectorTool(.pages) } label: {
                Label(L10n.pages, systemImage: "square.grid.2x2")
            }.accessibilityIdentifier("editor-pages")
            NotebookHistoryActions(undoManager: undoManager, busy: model.isChangingNotebookPage,
                                   historyRevision: model.historyRevision,
                                       beforeAction: { await textSession.finish(undoManager: undoManager) })
            Divider()
            recognizeTextButton
            annotateTextButton
            manageMarkupButton
            shapeButton
            stampButton
            textBoxButton
            imageButton
            commentsButton
            Divider()
            outlineButton
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
                    // The always-present compact toolbar owns presentation.
                    Button(L10n.adjustments) { isShowingAdjustments = true }
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
            Task { if await textSession.finish(undoManager: undoManager) { isShowingExport = true } }
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

/// Separate view evaluation keeps the notebook editor's body small on devices.
private struct NotebookInkSettings: View {
    let tool: MacMarkupTool
    @Binding var width: Double
    @Binding var eraserMode: InkEraserMode
    @Binding var color: RGBAColor
    @Binding var opacity: Double
    @Binding var fingerDrawing: Bool
    @Binding var selectionMode: PageSelectionMode
    let selectAll: () -> Void
    let done: () -> Void

    private var title: String {
        switch tool {
        case .pen: L10n.inkPen
        case .highlighter: L10n.inkHighlighter
        case .eraser: L10n.inkEraser
        case .lasso: L10n.inkLasso
        }
    }

    private var resizableEraser: Bool {
        #if os(iOS)
        eraserMode == .precision
        #else
        true
        #endif
    }

    private var eraserPreviewDiameter: Double {
        #if os(iOS)
        InkCanvas.eraser(mode: .precision, size: width).width
        #else
        width
        #endif
    }

    private var eraserSizeValue: String { ((width - 8) / 56).formatted(.percent.precision(.fractionLength(0))) }

    private var swatchColor: Binding<RGBAColor> {
        Binding(get: {
            var value = color
            value.alpha = 1
            return value
        }, set: { color = $0 })
    }

    private var widthPresets: some View {
        ForEach(MarkupWeight.allCases, id: \.self) { weight in
            Button { width = tool.width(for: weight) } label: {
                Text(weight == .thin ? L10n.shapeThin : weight == .medium ? L10n.shapeMedium : L10n.shapeThick)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(abs(width - tool.width(for: weight)) < 0.01 ? Theme.selection : Theme.libraryBackground,
                                in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityValue(abs(width - tool.width(for: weight)) < 0.01 ? L10n.selectionOn : L10n.selectionOff)
            .accessibilityIdentifier("studio-width-\(weight.rawValue)")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button(L10n.done, action: done)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("studio-settings-done")
            }.padding(.horizontal, 20).padding(.top, 8)
            Form {
                if tool.ink != nil {
                    Section(L10n.studioStrokePreview) {
                        GeometryReader { geometry in
                            Path { path in
                                path.move(to: CGPoint(x: 16, y: 40))
                                path.addCurve(to: CGPoint(x: geometry.size.width - 16, y: 32),
                                              control1: CGPoint(x: geometry.size.width * 0.35, y: 0),
                                              control2: CGPoint(x: geometry.size.width * 0.65, y: 72))
                            }
                            .stroke(color.swiftUIColor, style: StrokeStyle(lineWidth: width, lineCap: .round))
                        }
                        .frame(height: 72)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)
                    }
                    Section(L10n.shapeWidth) {
                        LabeledContent(L10n.shapeWidth, value: L10n.studioWidthValue(width.formatted(.number.precision(.fractionLength(1)))))
                        Slider(value: $width, in: tool == .highlighter ? 4...40 : 0.5...12, step: 0.1) {
                            Text(L10n.shapeWidth)
                        }
                        .accessibilityValue(L10n.studioWidthValue(width.formatted(.number.precision(.fractionLength(1)))))
                        .accessibilityIdentifier("studio-width-slider")
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { widthPresets }.fixedSize(horizontal: true, vertical: false)
                            VStack(alignment: .leading, spacing: 8) { widthPresets }
                        }
                    }
                    Section(L10n.markupCustomColor) {
                        MarkupColorPicker(color: swatchColor)
                        LabeledContent(L10n.studioOpacity, value: opacity.formatted(.percent.precision(.fractionLength(0))))
                        Slider(value: $opacity, in: 0.1...1) { Text(L10n.studioOpacity) }
                            .accessibilityIdentifier("studio-opacity-slider")
                    }
                } else if tool == .eraser {
                    if resizableEraser {
                    Section(L10n.eraserSize) {
                        Circle().strokeBorder(Theme.accent, lineWidth: 2)
                            .background(Circle().fill(Theme.selection.opacity(0.5)))
                            .frame(width: eraserPreviewDiameter, height: eraserPreviewDiameter)
                            .frame(maxWidth: .infinity, minHeight: 88)
                            .accessibilityHidden(true)
                        LabeledContent(L10n.eraserSize, value: eraserSizeValue)
                        Slider(value: $width, in: 8...64) { Text(L10n.eraserSize) }
                            .accessibilityIdentifier("studio-eraser-size")
                            .accessibilityValue(eraserSizeValue)
                        ForEach([8.0, 36, 64], id: \.self) { size in
                            Button { width = size } label: {
                                HStack {
                                    Image(systemName: "circle").frame(width: 28)
                                    Text(size == 8 ? L10n.eraserSmall : size == 36 ? L10n.eraserMedium : L10n.eraserLarge)
                                    Spacer()
                                    if width == size { Image(systemName: "checkmark") }
                                }.padding(.horizontal, 10).frame(minHeight: 44)
                                    .background(width == size ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 12))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            .accessibilityValue(width == size ? L10n.selectionOn : L10n.selectionOff)
                            .accessibilityIdentifier("studio-eraser-size-\(Int(size))")
                        }
                    }
                    }
                    Section(L10n.eraserMode) {
                        ForEach(InkEraserMode.allCases, id: \.self) { mode in
                            Button { eraserMode = mode } label: {
                                HStack {
                                    Text(mode == .precision ? L10n.eraserPrecision : L10n.eraserStroke)
                                    Spacer()
                                    if eraserMode == mode { Image(systemName: "checkmark") }
                                }.padding(.horizontal, 10).frame(minHeight: 44)
                                    .background(eraserMode == mode ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 12))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            .accessibilityValue(eraserMode == mode ? L10n.selectionOn : L10n.selectionOff)
                            .accessibilityIdentifier("studio-eraser-mode-\(mode.rawValue)")
                        }
                        Text(eraserMode == .precision ? L10n.eraserPrecisionDetail : L10n.studioEraserDetail)
                    }
                } else if tool == .lasso {
                    Text(L10n.lassoInkHint)
                    Section(L10n.selectionMode) {
                        ForEach(PageSelectionMode.allCases, id: \.self) { mode in
                            Button { selectionMode = mode } label: {
                                HStack {
                                    Text(mode == .freehand ? L10n.selectionFreehand : L10n.selectionRectangle)
                                    Spacer()
                                    if selectionMode == mode { Image(systemName: "checkmark") }
                                }.frame(minHeight: 44)
                            }
                            .accessibilityValue(selectionMode == mode ? L10n.selectionOn : L10n.selectionOff)
                            .accessibilityIdentifier("studio-lasso-\(mode.rawValue)")
                        }
                        Button(L10n.selectAll, action: selectAll)
                            .accessibilityIdentifier("studio-lasso-select-all")
                    }
                }
                #if os(iOS)
                if tool != .lasso {
                    Section {
                        Toggle(L10n.drawWithFinger, isOn: $fingerDrawing)
                            .accessibilityIdentifier("studio-finger-drawing")
                    }
                }
                #endif
            }
            .formStyle(.grouped)

        }
        .frame(minWidth: 280, idealWidth: 360, minHeight: 400, idealHeight: 620)
    }
}

/// Text stays visible below each tool on phones. At larger type sizes the
/// row scrolls instead of squeezing the translated labels into tiny targets.
private struct EditorToolLabelStyle: LabelStyle {
    var minimumWidth: CGFloat = 60
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 6) {
            configuration.icon.font(.title3).frame(height: 24)
            configuration.title.font(.caption2.weight(.medium)).fixedSize(horizontal: true, vertical: false)
        }
        .frame(minWidth: minimumWidth, minHeight: 48)
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
    var beforeSelection: (() async -> Bool)? = nil

    var body: some View {
        List(selection: Binding(get: { model.selectedPageID }, set: { id in
            Task { if await beforeSelection?() ?? true { model.selectedPageID = id } }
        })) {
            ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
                VStack(spacing: 4) {
                    PageImageView(page: page, pixelSize: 260, accessibilityLabel: L10n.pageLabel(index + 1, of: model.pages.count))
                        #if os(macOS)
                        // AppKit's List measures an ideal row height repeatedly.
                        // A flexible aspect-fit thumbnail can feed that measurement
                        // back into itself during opening/window zoom. Reserve a
                        // stable preview slot while the image loads and resizes.
                        .frame(height: 150)
                        #else
                        .frame(maxHeight: 150)
                        #endif
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
    var beforeSelection: (() async -> Bool)? = nil
    @ScaledMetric(relativeTo: .caption2) private var numberSpace: CGFloat = 22

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
                        let isSelected = page.id == model.selectedPageID
                        Button {
                            Task { if await beforeSelection?() ?? true { model.selectedPageID = page.id } }
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

private struct NotebookPageFrames: PreferenceKey {
    static let defaultValue: [PageID: CGRect] = [:]
    static func reduce(value: inout [PageID: CGRect], nextValue: () -> [PageID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

/// Notebook pages share one lazy scrolling canvas; PDFs retain selected-page viewing.
/// Pages are fitted to the available space and zoomable with
/// buttons/keyboard (Mac, iPad) or a pinch (trackpad, touch).
private struct PageViewer: View {
    @Bindable var model: DocumentModel
    @Bindable var textSession: InlineTextSession
    @Binding var zoom: CGFloat
    let showsZoomButtons: Bool
    var isMarkingUp = false
    var fingerDrawing = false
    var undoManager: UndoManager?
    var inkTool: MacMarkupTool = .pen
    var inkColor = RGBAColor(red: 0, green: 0, blue: 0, alpha: 1)
    var inkWidth: Double = 2
    var eraserMode: InkEraserMode = .precision
    var usesStudioTools = false
    var lassoMode: PageSelectionMode = .freehand
    var selectAllRequest = 0
    var onLeaveSelection: () -> Void = {}
    var appendNotebookPage: ((PageID) -> Void)? = nil
    var canAppendNotebookPage = false

    /// Whether the rendered page includes the ink already saved on it.
    ///
    /// On iOS the canvas is PencilKit, which draws every stroke itself, so the
    /// page underneath leaves ink out to avoid drawing it twice. The Mac
    /// canvas previews **only the stroke being drawn** — so the page has to
    /// keep drawing the saved ones, or a finished stroke vanishes the instant
    /// the pointer comes up. It did exactly that until this was separated.
    private var pageShowsInk: Bool {
        #if os(macOS)
        true
        #else
        !isMarkingUp || inkTool == .lasso
        #endif
    }
    @Environment(\.displayScale) private var displayScale
    @State private var pinchBase: CGFloat?
    @State private var selectedMark: PageObjectID?
    @State private var pageFrame: CGRect = .zero
    @State private var lassoHiddenIDs: Set<PageObjectID> = []

    static let zoomSteps = PageZoom.steps

    @State private var scrollSelection: PageID?
    @State private var jumpTarget: PageID?
    @State private var isSelectingVisiblePage = false
    @State private var hasPositionedInitialPage = false
    private var isContinuous: Bool { model.item?.kind == .notebook }

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { reader in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(spacing: isContinuous ? 20 : 0) {
                        ForEach(isContinuous ? model.pages : model.selectedPage.map { [$0] } ?? []) { page in
                            pageSurface(page, in: proxy)
                                .background {
                                    GeometryReader { paper in
                                        Color.clear.preference(key: NotebookPageFrames.self,
                                            value: [page.id: paper.frame(in: .global)])
                                    }
                                }
                                .frame(minWidth: proxy.size.width,
                                       minHeight: isContinuous && page.id != model.pages.last?.id ? nil : proxy.size.height)
                                .id(page.id)
                        }
                        if let page = model.pages.last, let appendNotebookPage, isContinuous {
                        Button { appendNotebookPage(page.id) } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "plus.circle")
                                Text(L10n.notebookScrollAdd).multilineTextAlignment(.center)
                            }
                            .font(.callout).padding(16)
                            .frame(maxWidth: .infinity, minHeight: 112)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).foregroundStyle(Theme.accent)
                        .disabled(!canAppendNotebookPage)
                        .accessibilityLabel(L10n.addNotebookPage)
                        .accessibilityHint(L10n.notebookScrollAdd)
                        .accessibilityIdentifier("notebook-scroll-add")
                        .background {
                            NotebookScrollAppendObserver(enabled: canAppendNotebookPage) { appendNotebookPage(page.id) }
                        }
                        }
                    }
                    .padding(.vertical, isContinuous ? 16 : 0)
                    #if os(iOS)
                    .background { PagePinchZoom(zoom: $zoom) }
                    .background {
                        if isContinuous && UIDevice.current.userInterfaceIdiom == .pad {
                            NotebookTouchScrolling(requiresTwoFingers: isMarkingUp)
                        }
                    }
                    #endif
                }
                .accessibilityIdentifier("document-page-scroll")
                .onPreferenceChange(NotebookPageFrames.self) { frames in
                    selectVisiblePage(frames, viewport: proxy.frame(in: .global))
                }
                .onChange(of: model.selectedPageID) { _, id in
                    guard let id else { return }
                    if scrollSelection == id { scrollSelection = nil; return }
                    if isContinuous {
                        jumpTarget = id
                        reader.scrollTo(id, anchor: .center)
                    } else { zoom = 1 }
                }
                .task(id: model.pages.map(\.id)) {
                    // A new page must enter the lazy stack before a jump can
                    // resolve its anchor. Keep the visible-page tracker parked
                    // while this explicit navigation completes.
                    guard isContinuous, let id = model.selectedPageID else { return }
                    jumpTarget = id
                    await Task.yield()
                    reader.scrollTo(id, anchor: .center)
                    hasPositionedInitialPage = true
                }
                .background(Theme.canvas)
                .onChange(of: proxy.size) { _, _ in
                    if textSession.isEditing {
                        withAnimation { reader.scrollTo("inline-text-anchor", anchor: .center) }
                    }
                }
                #if os(macOS)
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let base = pinchBase ?? zoom
                            pinchBase = base
                            zoom = min(max(base * value.magnification, Self.zoomSteps.first!), Self.zoomSteps.last!)
                        }
                        .onEnded { _ in pinchBase = nil }
                )
                #endif
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Hidden while marking up: the tool palette covers this spot
            // (pinch still zooms).
            if showsZoomButtons, !isMarkingUp, !usesStudioTools {
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

    }

    private func selectVisiblePage(_ frames: [PageID: CGRect], viewport: CGRect) {
        guard isContinuous, hasPositionedInitialPage, !textSession.isSelected, !isSelectingVisiblePage,
              !model.isChangingNotebookPage else { return }
        if let target = jumpTarget {
            guard let frame = frames[target], frame.intersects(viewport) else { return }
            jumpTarget = nil
            return
        }
        // Prefer the page with the greatest visible paper area. When two
        // sheets fit completely, keep the earlier one instead of skipping it.
        let visible = model.pages.compactMap { page -> (PageID, CGFloat)? in
            guard let frame = frames[page.id], frame.intersects(viewport) else { return nil }
            return (page.id, frame.intersection(viewport).height)
        }
        guard let best = visible.max(by: { $0.1 < $1.1 }),
              let closest = visible.first(where: { $0.1 >= best.1 - 1 })?.0,
              closest != model.selectedPageID else { return }
        activate(closest, fromScroll: true)
    }

    private func activate(_ id: PageID, fromScroll: Bool) {
        guard !isSelectingVisiblePage else { return }
        isSelectingVisiblePage = true
        Task {
            defer { isSelectingVisiblePage = false }
            guard await textSession.finish(undoManager: undoManager),
                  model.pages.contains(where: { $0.id == id }) else { return }
            if fromScroll { scrollSelection = id }
            model.selectedPageID = id
        }
    }

    private func pageSurface(_ page: Page, in proxy: GeometryProxy) -> some View {
        let active = page.id == model.selectedPageID
        let index = model.pages.firstIndex(where: { $0.id == page.id }) ?? 0
        let fitted = fittedSize(page.geometry.pageSize, in: proxy.size)
        let held = textSession.page?.id == page.id ? textSession.canvasSize : nil
        let size = held.map { CGSize(width: $0.width * zoom / textSession.canvasZoom,
                                     height: $0.height * zoom / textSession.canvasZoom) }
            ?? CGSize(width: fitted.width * zoom, height: fitted.height * zoom)
        return PageImageView(page: page, pixelSize: max(size.width, size.height) * displayScale,
                      accessibilityLabel: L10n.pageLabel(index + 1, of: model.pages.count),
                      includesInk: !active || pageShowsInk,
                      excludingObjectIDs: (textSession.page?.id == page.id ? textSession.excludedIDs : []).union(active ? lassoHiddenIDs : []))
            .accessibilityIdentifier(active ? "document-page-image" : "notebook-preview-\(page.id)")
            .accessibilityValue(active ? L10n.strokeCount(model.selectedPageObjects.filter {
                guard $0.pageID == page.id else { return false }
                if case .ink = $0.payload { return true }
                return false
            }.count) : "")
            .frame(width: size.width, height: size.height)
            // Text boxes and placed images can be picked up and
            // moved. Stood down while the ink canvas is up, which
            // owns the whole page then.
            .overlay {
                if active && !isMarkingUp {
                    let pageSize = page.geometry.pageSize
                    MovableMarksOverlay(
                        model: model, page: page,
                        sourceToView: page.geometry.sourceToPage.concatenating(
                            CGAffineTransform(scaleX: size.width / pageSize.width,
                                              y: size.height / pageSize.height)),
                        undoManager: undoManager, includesText: false,
                        selected: $selectedMark)
                    InlineTextOverlay(session: textSession, page: page,
                        sourceToView: page.geometry.sourceToPage.concatenating(
                            CGAffineTransform(scaleX: size.width / pageSize.width, y: size.height / pageSize.height)),
                        // GeometryReader already occupies the safe content area.
                        // Convert its actual viewport into the scrolled page's space;
                        // safeAreaInsets include ancestors and must not be subtracted again.
                        visible: proxy.frame(in: .global)
                            .offsetBy(dx: -pageFrame.minX, dy: -pageFrame.minY)
                            .intersection(CGRect(origin: .zero, size: size)),
                        zoom: zoom, undoManager: undoManager)
                }
            }
            .overlay {
                if active && isMarkingUp && inkTool == .lasso {
                    let pageSize = page.geometry.pageSize
                    let mapping = page.geometry.sourceToPage.concatenating(
                        CGAffineTransform(scaleX: size.width / pageSize.width, y: size.height / pageSize.height))
                    PageSelectionOverlay(model: model, page: page, sourceToView: mapping,
                        visible: proxy.frame(in: .global).offsetBy(dx: -pageFrame.minX, dy: -pageFrame.minY)
                            .intersection(CGRect(origin: .zero, size: size)),
                        mode: lassoMode, selectAllRequest: selectAllRequest, enablesTwoFingerNavigation: isContinuous, undoManager: undoManager,
                        hiddenIDs: $lassoHiddenIDs) { object in
                            onLeaveSelection()
                            switch object.payload {
                            case .text: textSession.select(object, on: page, sourceToView: mapping, zoom: zoom); textSession.edit()
                            case .image: selectedMark = object.id
                            default: break
                            }
                        }
                }
            }
            #if os(macOS)
            .overlay {
                if active && isMarkingUp && inkTool != .lasso {
                    let pageSize = page.geometry.pageSize
                    MacInkCanvas(
                        model: model, page: page,
                        sourceToView: page.geometry.sourceToPage.concatenating(
                            CGAffineTransform(scaleX: size.width / pageSize.width,
                                              y: size.height / pageSize.height)),
                        tool: inkTool, color: inkColor, width: inkWidth, eraserMode: eraserMode,
                        undoManager: undoManager)
                }
            }
            #endif
            #if os(iOS)
            .overlay {
                if active && isMarkingUp && inkTool != .lasso {
                    let pageSize = page.geometry.pageSize
                    // Only this page's objects: right after a page switch the
                    // previous page's are still loaded.
                    InkCanvas(pageID: page.id, objects: model.selectedPageObjects.filter { $0.pageID == page.id },
                              sourceToView: page.geometry.sourceToPage.concatenating(
                                  CGAffineTransform(scaleX: size.width / pageSize.width, y: size.height / pageSize.height)),
                              fingerDrawing: fingerDrawing, documentUndoManager: undoManager,
                              studioTool: usesStudioTools ? inkTool : nil, enablesTwoFingerNavigation: isContinuous,
                              studioColor: inkColor, studioWidth: inkWidth, eraserMode: eraserMode) { saving, deleting in
                        Task { await model.changeInk(on: page.id, saving: saving, deleting: deleting, undoManager: undoManager) }
                    }
                }
            }
            #endif
            .onGeometryChange(for: CGRect.self) { pageProxy in
                pageProxy.frame(in: .global)
            } action: { if active { pageFrame = $0 } }

            .overlay {
                if !active {
                    Button { activate(page.id, fromScroll: true) } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.pageLabel(index + 1, of: model.pages.count))
                }
            }
    }

    private func fittedSize(_ page: CGSize, in container: CGSize) -> CGSize {
        let inset: CGFloat = showsZoomButtons ? 32 : 12
        let available = CGSize(width: max(container.width - inset * 2, 50), height: max(container.height - inset * 2, 50))
        // Compact editors scroll vertically instead of shrinking the paper
        // and its contextual controls to the height left by large navigation.
        let scale = showsZoomButtons
            ? min(available.width / page.width, available.height / page.height)
            : available.width / page.width
        return CGSize(width: page.width * scale, height: page.height * scale)
    }

    private func step(_ direction: Int) {
        zoom = PageZoom.step(zoom, direction: direction)
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

import PaperNestCore
import PaperNestExport
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
    @State private var isShowingDisplaySettings = false
    /// Bumped to ask the page viewer to fit the page's width to the window.
    @State private var fitWidthRequest = 0
    @State private var isAppendingNotebookPage = false
    @State private var inspectorTool: InspectorTool?
    @State private var signatureDrafts: [PageID: SignatureDraft] = [:]
    @State private var formSession: PDFFormSession?
    @State private var pageToolBusy = false

    private enum InspectorTool { case signature(Page), form, pages, ocr }
    @State private var isShowingOCR = false
    @State private var stampPage: Page?
    @State private var textStampPage: Page?
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
    @State private var lassoSelectAllRequest = 0
    @State private var didChooseInitialTool = false
    /// Every tool's settings: one set for the whole app, saved as it changes,
    /// so the pen in hand in one document is the pen in hand in the next.
    @State private var toolSettings = EditorToolSettingsStore.shared
    /// The tool whose settings panel is open, if any.
    @State private var openToolPanel: EditorTool?
    @State private var isShowingImagePicker = false
    @State private var isShowingPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoTargetPage: Page?
    @State private var isLoadingPhoto = false
    @State private var isShowingCrop = false
    /// The Redact screen, for the page on screen.
    @State private var isShowingRedact = false
    /// Comparing this document with another.
    @State private var isShowingCompare = false
    /// Reading a receipt's, card's or invoice's details off the page.
    @State private var isShowingDetails = false
    /// Blank and repeated pages, offered for removal.
    @State private var isShowingCleanup = false
    /// Saving the page as a template: asking for its name.
    @State private var isNamingTemplate = false
    @State private var templateName = ""
    @State private var renamingTemplate: SavedPageTemplate?
    @State private var templateRename = ""
    /// Deleting a template is not undoable, so it is asked first.
    @State private var deletingTemplate: SavedPageTemplate?
    @State private var annotationPage: Page?
    /// Which mark the recognised-text sheet opens on.
    @State private var annotationStyle: TextMarkupStyle = .highlight
    @State private var isShowingCompress = false
    /// Opens the export sheet with Word chosen.
    @State private var exportFormat: ExportFormat?
    @State private var splitCount: Int?
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
    /// Find in document: the bar under the toolbar and the hits over the page.
    @State private var find = DocumentFind()
    /// The words selected on the page being read.
    @State private var textSelection = PageTextSelectionModel()
    @State private var isShowingGoToPage = false
    @State private var goToPageText = ""
    /// Print: makes the PDF and shows the system's print panel.
    @State private var printer = DocumentPrinter()
    /// Read aloud: says the document from the page being read, lighting each word.
    @State private var readAloud = ReadAloud()
    /// Night mode: pages shown light on dark. A preference, not part of the document.
    @AppStorage(NightMode.storageKey) private var isNightMode = false
    /// Two-page view: a document a spread at a time where there is room. A preference too.
    @AppStorage(TwoPageView.storageKey) private var isTwoPages = false
    @AppStorage(TwoPageView.coverKey) private var isCoverAlone = false
    /// The reader's bookmarks in this document.
    @State private var bookmarks = ReaderBookmarks()

    init(itemID: ItemID, session: LibrarySession, retainedState: DocumentEditorState? = nil,
         workspaceHeader: AnyView? = nil) {
        self.workspaceHeader = workspaceHeader
        self.retainedState = retainedState
        _ = DocumentUtilitiesStorage.freshStartForThrowawayLibrary
        let document = retainedState?.model ?? DocumentModel(itemID: itemID, session: session)
        _zoom = State(initialValue: retainedState?.zoom ?? 1)
        _model = State(initialValue: document)
        #if os(iOS)
        // Only where it will lay out as a column. An inspector that has to
        // overlay swallows the reader's first touch; see
        // `inspectorColumnMinimumWidth`.
        _isShowingPDFTools = State(initialValue: UIDevice.current.userInterfaceIdiom == .pad
                                   && Self.activeWindowWidth() >= Self.inspectorColumnMinimumWidth)
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

    /// Below this width SwiftUI stops laying `.inspector` out as a column and
    /// presents it as an **overlay**, and that overlay's tap-outside-to-dismiss
    /// swallows the first touch outside it — so opening a document with the
    /// tools panel already up cost the user their first tap or first pinch.
    ///
    /// Measured, first tap on a tool after opening a notebook: 834pt (11-inch
    /// iPad portrait) **eaten**; 1032pt (13-inch portrait), 1210pt and 1376pt
    /// (landscape) all landed. The switch therefore sits between 834 and 1032,
    /// and 900 is inside that bracket rather than guessed. Auto-presenting is
    /// skipped below it; the toolbar button still opens the panel by hand,
    /// which costs a deliberate tap instead of a surprising one.
    static let inspectorColumnMinimumWidth: CGFloat = 900

    #if os(iOS)
    /// The active window's width, read before the editor is ever on screen.
    ///
    /// The decision has to happen here rather than from a later layout pass:
    /// presenting the inspector *after* the editor has appeared costs a touch
    /// of its own even at widths where it lays out as a column — measured, a
    /// 13-inch iPad in landscape lost its first tap that way. Deciding up
    /// front keeps the original, working presentation path and changes only
    /// whether it is taken.
    static func activeWindowWidth() -> CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .bounds.width
            ?? UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.screen.bounds.width }
                .first
            ?? 0
    }
    #endif

    /// The editor's modifiers are applied by the seven functions below, in
    /// this order, rather than as one chain here, and that is not a matter of
    /// taste. Every modifier wraps all that was chained before it in a new
    /// value, and an unoptimised build keeps each of those values on the
    /// stack until the function returns. As a single chain of some
    /// seventy-five modifiers this body needed 885 KB of stack to run. An
    /// iPhone or iPad gives its main thread 1 MB, where the Mac and the
    /// Simulator gave 8, so the editor passed every Simulator and Mac check
    /// and then crashed on a real iPad as it opened (2026-11-15).
    ///
    /// Split this way each function's values are gone when it returns, and
    /// nothing else changes: the view built is the same view, of the same
    /// type, evaluated in this one `body` as before, so everything read
    /// along the way still re-evaluates the whole editor. (Turning the runs
    /// into `ViewModifier`s saves more stack but each then re-evaluates on
    /// its own, and a stroke drawn at night stopped showing until the pen
    /// was put down.) Put a new modifier in the function it belongs with,
    /// and start another function rather than let one grow past a dozen.
    var body: some View {
        readerServices(pageSources(templateDialogs(toolSheets(exportAndPictures(lifecycle(toolsPanel(bars(pages))))))))
    }

    /// The pages themselves, or what stands in for them while there are none.
    private var pages: some View {
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
                    PageViewer(model: model, textSession: textSession, zoom: $zoom, showsZoomButtons: false,
                               isMarkingUp: isMarkingUp, fingerDrawing: isFingerDrawing, undoManager: undoManager,
                               inkTool: inkTool, tools: toolSettings.settings,
                               usesStudioTools: true, selectAllRequest: lassoSelectAllRequest,
                               fitWidthRequest: fitWidthRequest,
                               onLeaveSelection: { isMarkingUp = false },
                               appendNotebookPage: isNotebook ? { appendContinuation(after: $0) } : nil,
                               canAppendNotebookPage: !isToolBusy && !textSession.isSelected, find: find,
                               textSelection: textSelection)
                        // One point of padding keeps the scroll view from
                        // extending under the toolbar above it. Without it
                        // the hidden top of a page taller than the screen
                        // lies beneath the toolbar and, to accessibility,
                        // on top of it: the tool buttons are then reported as
                        // covered. The page strip used to sit in that gap.
                        .padding(.top, 1)
                }
            } else {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        PageViewer(model: model, textSession: textSession, zoom: $zoom, showsZoomButtons: true, isMarkingUp: isMarkingUp,
                                   fingerDrawing: isFingerDrawing, undoManager: undoManager,
                                   inkTool: inkTool, tools: toolSettings.settings,
                                   usesStudioTools: true, selectAllRequest: lassoSelectAllRequest,
                                   fitWidthRequest: fitWidthRequest,
                               onLeaveSelection: { isMarkingUp = false },
                               appendNotebookPage: isNotebook ? { appendContinuation(after: $0) } : nil,
                               canAppendNotebookPage: !isToolBusy && !textSession.isSelected, find: find,
                               textSelection: textSelection,
                               twoPages: isTwoPages && !isNotebook, coverAlone: isCoverAlone)
                    }
                }
            }
        }
    }

    /// The title and its menu, and the bars above and below the page.
    @inline(never)
    private func bars<Content: View>(_ content: Content) -> some View {
        content
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
                    if find.isPresented && !model.pages.isEmpty {
                        DocumentFindBar(find: find, model: model) { id in
                            Task { if await textSession.finish(undoManager: undoManager) { model.selectedPageID = id } }
                        }
                    }
                    if readAloud.isActive && !model.pages.isEmpty {
                        ReadAloudBar(readAloud: readAloud, model: model)
                    }
                    if textSession.hasFailure && (model.selectedPageID != textSession.page?.id ||
                        !model.pages.contains(where: { $0.id == textSession.page?.id })) {
                        InlineTextRecoveryBar(session: textSession, undoManager: undoManager)
                            .background(Theme.surface)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // A phone's keyboard leaves little enough of the page; the palette
                // would cover what is left, including the hit just found.
                if !model.pages.isEmpty && !(isCompact && (textSession.isSelected || find.isTyping)) {
                    studioPalette.opacity(textSession.isSelected ? 0 : 1)
                        .allowsHitTesting(!textSession.isSelected)
                        .accessibilityHidden(textSession.isSelected)
                }
            }
    }

    /// The tools panel, as a drawer or as a column, and the toolbar that opens it.
    @inline(never)
    private func toolsPanel<Content: View>(_ content: Content) -> some View {
        content
            .overlay {
                // A phone has no room for a column, so the same panel rises from
                // the bottom instead — drawn here, not as a system sheet, because
                // the tools in it open sheets of their own.
                if !usesPDFToolsSidebar && isShowingPDFTools {
                    UtilitiesDrawer(close: { closeUtilities() }) { PDFToolsSidebar(editor: self) }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onChange(of: isPresentingOverUtilities) { _, presenting in
                if presenting && !usesPDFToolsSidebar { isShowingPDFTools = false }
            }
            .toolbar { toolbar }
            // Preserve the former sheet's transaction boundary while keeping the page visible.
            .disabled(usesPDFToolsSidebar && (isShowingExport || isShowingCompress))
            .inspector(isPresented: inspectorBinding) {
                PDFToolsSidebar(editor: self)
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
            }
            .navigationBarBackButtonHidden()
    }

    /// What the editor does as it comes and goes and as the document loads,
    /// with the prompts that belong to the document as a whole.
    @inline(never)
    private func lifecycle<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { Task { await textSession.commitAndFlush(undoManager: undoManager) } }
                // Without background audio the system silences the app anyway;
                // paused, it carries on from the same word when the reader is back.
                if phase == .background { readAloud.pause() }
            }
            .onAppear {
                editingGuard.owner = editingOwner
                editingGuard.finish = { await finishEditing() }
                commandContext = makeCommandContext()
                let settings = toolSettings
                textSession.styleForNewBox = { settings.settings.text.apply(to: &$0) }
            }
            .onDisappear {
                readAloud.stop()
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
            .alert(L10n.goToPage, isPresented: $isShowingGoToPage) {
                TextField(L10n.goToPageField, text: $goToPageText)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Button(L10n.cancel, role: .cancel) {}
                Button(L10n.goToPageGo) {
                    guard let index = PageNumberEntry.pageIndex(for: goToPageText, pageCount: model.pages.count)
                    else { return }
                    model.selectedPageID = model.pages[index].id
                }
            } message: {
                Text(L10n.goToPageMessage(model.pages.count))
            }
            .onChange(of: model.hasLoaded, initial: true) { _, loaded in
                guard loaded, !didChooseInitialTool else { return }
                didChooseInitialTool = true
                if isNotebook { inkTool = .lasso; isMarkingUp = true }
            }
            .task(id: model.session.changeToken) { await model.load() }
            // A search hit asking for a page of this document while it is open.
            .task(id: model.session.pageRequest) { model.applyPageRequest() }
            // Opening a document that is only in iCloud fetches it.
            .task(id: model.itemID) { await model.session.sync?.downloadIfNeeded(model.itemID) }
            .task(id: model.selectedPageID) { await model.loadSelectedPageObjects() }
            #if DEBUG
            // Dev/screenshot hooks: `-PaperNestDebugShowExport YES`, `-PaperNestDebugShowCrop YES`,
            // `-PaperNestDebugShowMarkup YES` (iPad), `-PaperNestDebugShowOutline YES`.
            .task {
                isShowingExport = UserDefaults.standard.bool(forKey: "PaperNestDebugShowExport")
                isShowingCrop = UserDefaults.standard.bool(forKey: "PaperNestDebugShowCrop")
                isShowingRedact = UserDefaults.standard.bool(forKey: "PaperNestDebugShowRedact")
                isShowingCompare = UserDefaults.standard.bool(forKey: "PaperNestDebugShowCompare")
                isShowingCompress = UserDefaults.standard.bool(forKey: "PaperNestDebugShowCompress")
                if UserDefaults.standard.bool(forKey: "PaperNestDebugShowMarkup") { isMarkingUp = true }
                isShowingOutline = UserDefaults.standard.bool(forKey: "PaperNestDebugShowOutline")
            }
            #endif
            .proPaywall(Binding(get: { model.proPaywall }, set: { model.proPaywall = $0 }))
            .alert(model.presentedError?.title ?? "", isPresented: errorBinding, presenting: model.presentedError) { _ in
                Button(L10n.ok, role: .cancel) {}
            } message: { error in
                Text(error.message)
            }
    }

    /// Export and Compress, as sheets or in the tools panel, and choosing a picture.
    @inline(never)
    private func exportAndPictures<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: isShowingPDFTools) { _, showing in
                if !showing && usesPDFToolsSidebar {
                    isShowingExport = false
                    isShowingCompress = false
                }
            }
            .onChange(of: isShowingCompress) { _, showing in
                if showing && usesPDFToolsSidebar { isShowingPDFTools = true }
            }
            .sheet(isPresented: usesPDFToolsSidebar ? .constant(false) : $isShowingCompress) { CompressSheet(itemID: model.itemID) }
            .alert(L10n.splitDoneTitle, isPresented: Binding(get: { splitCount != nil }, set: { if !$0 { splitCount = nil } })) {
                Button(L10n.ok, role: .cancel) {}
            } message: { Text(L10n.splitDoneMessage(splitCount ?? 0)) }
            .onChange(of: isShowingExport) { _, showing in
                if !showing { exportFormat = nil }
                else if usesPDFToolsSidebar { isShowingPDFTools = true }
            }
            .sheet(isPresented: usesPDFToolsSidebar ? .constant(false) : $isShowingExport) {
                ExportLoader(itemID: model.itemID, currentPageID: model.selectedPageID, initialFormat: exportFormat)
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
    }

    /// Saving the page as a template, and renaming or deleting one. System
    /// alerts and sheets: their fields and buttons do not carry SwiftUI
    /// identifiers, so tests find them through `app.alerts` and `app.sheets`.
    @inline(never)
    private func templateDialogs<Content: View>(_ content: Content) -> some View {
        content
            .sheet(isPresented: $isShowingCleanup) {
                CleanupSheet(document: model, undoManager: undoManager)
            }
            .sheet(item: $textStampPage) { page in
                StampSheet(document: model, page: page, undoManager: undoManager)
            }
            .sheet(isPresented: $isShowingDetails) {
                if let page = model.selectedPage {
                    DetailsSheet(itemID: model.itemID, pageID: page.id, session: model.session)
                }
            }
            .alert(L10n.templatesNamePrompt, isPresented: $isNamingTemplate) {
                TextField(L10n.templatesNameField, text: $templateName)
                Button(L10n.cancel, role: .cancel) {}
                Button(L10n.templatesSave) {
                    guard let page = model.selectedPageID else { return }
                    let name = templateName
                    Task {
                        do { try await model.saveTemplate(from: page, named: name) } catch { model.presentedError = .saveFailed() }
                    }
                }
            } message: { Text(L10n.templatesSaveDetail) }
            .alert(L10n.templatesRenameTitle, isPresented: Binding(get: { renamingTemplate != nil },
                                                                   set: { if !$0 { renamingTemplate = nil } })) {
                TextField(L10n.templatesNameField, text: $templateRename)
                Button(L10n.cancel, role: .cancel) {}
                Button(L10n.rename) {
                    guard let template = renamingTemplate else { return }
                    let name = templateRename
                    Task {
                        do { try await model.renameSavedTemplate(template.id, to: name) } catch { model.presentedError = .saveFailed() }
                    }
                }
            }
            .confirmationDialog(L10n.templatesDeleteTitle(deletingTemplate?.name ?? ""),
                                isPresented: Binding(get: { deletingTemplate != nil }, set: { if !$0 { deletingTemplate = nil } }),
                                titleVisibility: .visible) {
                Button(L10n.delete, role: .destructive) {
                    guard let template = deletingTemplate else { return }
                    Task {
                        do { try await model.deleteSavedTemplate(template.id) } catch { model.presentedError = .saveFailed() }
                    }
                }
                Button(L10n.cancel, role: .cancel) {}
            } message: { Text(L10n.templatesDeleteDetail) }
    }

    /// The sheet each page tool opens where there is no tools panel to hold it.
    @inline(never)
    private func toolSheets<Content: View>(_ content: Content) -> some View {
        content
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
            .sheet(isPresented: $isShowingCompare) {
                CompareSheet(originalID: model.itemID, session: model.session)
            }
            .sheet(isPresented: $isShowingRedact) {
                if let page = model.selectedPage {
                    RedactEditor(model: model, page: page, undoManager: undoManager)
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
                TextAnnotationSheet(model: model, pageID: page.id, undoManager: undoManager, initialStyle: annotationStyle)
            }
            .sheet(item: $managedMarkupPage) { page in
                MarkupManagerSheet(model: model, pageID: page.id, undoManager: undoManager)
            }
            .sheet(isPresented: $isShowingOCR) {
                OCRPanel(model: model, undoManager: undoManager, beforeAction: { await finishTextForPanelAction() })
            }
            .sheet(isPresented: $isShowingPageOrganizer) {
                DocumentPagesSheet(model: model, undoManager: undoManager)
            }
    }

    /// Where new pages come from: a file, the camera, a document that needs its password.
    @inline(never)
    private func pageSources<Content: View>(_ content: Content) -> some View {
        content
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
    }

    /// Reading: print, night mode, read aloud, bookmarks, and the menu commands.
    @inline(never)
    private func readerServices<Content: View>(_ content: Content) -> some View {
        content
            .documentPrinting(printer)
            .environment(\.pageNightMode, isNightMode)
            .environment(\.readAloud, readAloud)
            // Reading follows the reader: turning the page restarts it there.
            .onChange(of: model.selectedPageID) { _, id in readAloud.pageChanged(to: id) }
            .documentBookmarks(bookmarks, model: model) { id in
                Task { if await textSession.finish(undoManager: undoManager) { model.selectedPageID = id } }
            }
            .focusedSceneValue(\.documentCommands, commandContext)
            .focusedSceneValue(\.documentPrinter, printer)
            .focusedSceneValue(\.readerBookmarks, bookmarks)
            .focusedSceneValue(\.readAloud, readAloud)
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

    /// Opens a Pro tool's screen, or, for a free user once products are
    /// configured, the paywall naming it.
    private func openProTool(_ feature: ProFeature, _ open: () -> Void) {
        guard SubscriptionStore.shared.allows(feature) else { model.proPaywall = feature; return }
        open()
    }

    private func makeCommandContext() -> DocumentCommandContext {
        DocumentCommandContext(model: model, undoManager: undoManager,
            showExport: { finishThen { isShowingExport = true } },
            showAddPages: { finishThen { openFilePicker(.add) } },
            showReplacePage: { finishThen { openFilePicker(.replace) } },
            showCrop: { finishThen { isShowingCrop = true } },
            showOutline: { finishThen { isShowingOutline = true } },
            showFind: { finishThen { find.isPresented = true } },
            showGoToPage: { showGoToPage() },
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
        }
        if isCompact {
            // Keep the custom tools toggle in the bar: UIKit's automatic
            // overflow menu can omit custom toolbar views for longer titles.
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 4) {
                    CloudSyncStatusView(session: model.session, style: .compact)
                    findButton.frame(width: 44, height: 44)
                    exportButton.frame(width: 44, height: 44)
                    UtilitiesToggleButton(isOn: $isShowingPDFTools)
                        .disabled(isToolBusy || isShowingExport || isShowingCompress)
                }.labelStyle(.iconOnly).fixedSize()
            }
        } else {
            ToolbarItemGroup(placement: .primaryAction) {
                CloudSyncStatusView(session: model.session, style: .compact)
                findButton
                exportButton
                UtilitiesToggleButton(isOn: $isShowingPDFTools)
                    .disabled(isToolBusy || isShowingExport || isShowingCompress)
            }
        }
    }

    /// Opens find, or closes it if it is already up. ⌘F lives on the button
    /// rather than in the menu bar, where the system keeps a Find of its own.
    private var findButton: some View {
        Button { toggleFind() } label: { Label(L10n.find, systemImage: "magnifyingglass") }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(model.pages.isEmpty)
            .accessibilityIdentifier("editor-find")
            .help(L10n.find)
    }

    private func toggleFind() {
        if find.isPresented { find.close() } else { finishThen { find.isPresented = true } }
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
        Button { showGoToPage() } label: {
            Label(L10n.goToPage, systemImage: "arrow.right.doc.on.clipboard")
        }
        .disabled(model.pages.count < 2)
        Button { finishThen { printer.print(model.itemID, in: model.session.environment) } } label: {
            Label(L10n.printMenu, systemImage: "printer")
        }
        .disabled(model.pages.isEmpty)
        Button { finishThen { readAloud.toggle(reading: model) } } label: {
            if readAloud.isActive {
                Label(L10n.readAloudStop, systemImage: "stop.circle")
            } else {
                Label(L10n.readAloudMenu, systemImage: "speaker.wave.2")
            }
        }
        .disabled(model.pages.isEmpty)
        BookmarkMenuItems(bookmarks: bookmarks, model: model, finishThen: finishThen)
    }

    private func showGoToPage() {
        goToPageText = ""
        finishThen { isShowingGoToPage = true }
    }


    /// A real View boundary defers the toolbar's large generic value until
    /// SwiftUI evaluates its own body. A computed property or Group evaluates
    /// it inside DocumentView.body, exhausting the device's debug-build stack.
    private struct NotebookToolbar: View {
        let editor: DocumentView

        var body: some View { editor.notebookTools }
    }

    /// The notes editor's main toolbar, in the content area so a native
    /// toolbar never collapses it into an overflow menu. It scrolls sideways
    /// when the window is narrower than the tools.
    private var notebookTools: some View {
        NotesEditorToolbar(store: toolSettings, session: textSession, markupTool: $inkTool,
                           isMarkingUp: $isMarkingUp, fingerDrawing: $isFingerDrawing,
                           openPanel: $openToolPanel, context: toolbarContext) {
            EmptyView()
        } trailing: {
            // No More menu: everything it held is in Document Tools, behind
            // the one toggle at the top right (owner, 2026-11-14).
            EmptyView()
        }
    }

    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    private var toolbarContext: NotesToolbarContext {
        NotesToolbarContext(
            showsLabels: !isCompact, isCompact: isCompact, isPhone: isPhone, hasPage: model.selectedPage != nil,
            isChangingPage: model.isChangingNotebookPage, isLoadingPhoto: isLoadingPhoto,
            undoManager: undoManager, historyRevision: model.historyRevision,
            finishText: { await textSession.finish(undoManager: undoManager) },
            armText: { armText() },
            selectAll: { lassoSelectAllRequest += 1 },
            highlightText: model.selectedPage == nil || model.isRecognizing ? nil : { annotationStyle = .highlight; annotationPage = model.selectedPage },
            image: imageToolActions,
            insertSticker: { insertSticker($0) },
            insert: insertToolActions)
    }

    private var imageToolActions: ImageToolActions {
        var actions = ImageToolActions(photos: {
            isMarkingUp = false
            selectedPhoto = nil
            photoTargetPage = model.selectedPage
            isShowingPhotoPicker = true
        }, files: { isMarkingUp = false; isShowingImagePicker = true })
        #if os(iOS)
        actions.cameraSupported = PhotoCameraView.isSupported
        actions.camera = {
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
        }
        #endif
        return actions
    }

    private var insertToolActions: InsertToolActions {
        InsertToolActions(
            addPage: isNotebook ? { template in
                Task {
                    do { try await model.addNotebookPage(template, after: model.selectedPageID, undoManager: undoManager) }
                    catch { model.presentedError = .saveFailed() }
                }
            } : nil,
            importPages: { openFilePicker(.add) },
            textBox: { armText() },
            image: { openToolPanel = .image },
            dateAndTime: { insertDateAndTime() },
            divider: { insertDivider() },
            duplicatePage: {
                Task {
                    do { try await model.duplicateSelectedPage(undoManager: undoManager) }
                    catch { model.presentedError = .saveFailed() }
                }
            },
            organizePages: { openInspectorTool(.pages) },
            templates: model.savedTemplates,
            addPageFromTemplate: isNotebook ? { template in
                Task {
                    do { try await model.addNotebookPage(fromTemplate: template.id, after: model.selectedPageID,
                                                         undoManager: undoManager) }
                    catch { model.presentedError = .saveFailed() }
                }
            } : nil,
            saveTemplate: model.selectedPage == nil ? nil : {
                templateName = model.item?.name ?? ""
                isNamingTemplate = true
            },
            renameTemplate: { template in
                templateRename = template.name
                renamingTemplate = template
            },
            deleteTemplate: { template in deletingTemplate = template })
    }

    /// Places one of the app's own stickers on the selected page, as an image
    /// like any other: it can be moved, resized, deleted, undone and exported.
    private func insertSticker(_ sticker: Sticker) {
        guard let page = model.selectedPage, let data = StickerLibrary.pngData(for: sticker) else { return }
        isMarkingUp = false
        Task {
            do {
                try await model.addImage(data, named: "sticker-\(sticker.id).png", to: page,
                                         frame: DocumentModel.stickerFrame(on: page), undoManager: undoManager)
                toolSettings.update { $0.noteStickerUsed(sticker.id) }
            } catch { model.presentedError = .saveFailed() }
        }
    }

    /// Today's date and the time, as a text box in the Text tool's current
    /// type settings. Typed text, so it can be corrected like any other.
    private func insertDateAndTime() {
        guard let page = model.selectedPage else { return }
        let style = toolSettings.settings.text
        let stamp = Date.now.formatted(date: .long, time: .shortened)
        isMarkingUp = false
        Task {
            do {
                try await model.addTextBox(to: page, text: stamp, fontSize: style.fontSize, color: style.color,
                                           alignment: style.alignment, undoManager: undoManager)
            } catch { model.presentedError = .saveFailed() }
        }
    }

    private func insertDivider() {
        guard let page = model.selectedPage else { return }
        let stroke = DocumentModel.dividerStroke(on: page, color: RGBAColor(red: 0.42, green: 0.44, blue: 0.56), width: 1.5)
        Task {
            do { try await model.addInkStroke(stroke, to: page, undoManager: undoManager) }
            catch { model.presentedError = .saveFailed() }
        }
    }

    private var usesPDFToolsSidebar: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        true
        #endif
    }

    /// Document Utilities as a column on iPad and Mac; a phone shows the same
    /// state as a drawer instead.
    ///
    /// Decided by the kind of device, never by the size class. The column's
    /// own presence narrows the page, and a rule that read the width to
    /// decide whether to show the column could close it, widen the page, and
    /// open it again without end.
    private var inspectorBinding: Binding<Bool> {
        usesPDFToolsSidebar ? $isShowingPDFTools : .constant(false)
    }

    private func closeUtilities() {
        withAnimation(.easeInOut(duration: 0.25)) { isShowingPDFTools = false }
    }

    /// Whether something that presents itself — a sheet, a picker, a camera —
    /// has been asked for. On a phone the utilities drawer steps aside for it.
    private var isPresentingOverUtilities: Bool {
        var presenting = shapePage != nil || stampPage != nil || textStampPage != nil || commentsPage != nil || annotationPage != nil
            || managedMarkupPage != nil || signaturePage != nil || notebookPageRequest != nil
            || isShowingCrop || isShowingFilePicker || isShowingPDFForm || isShowingPageOrganizer
            || isShowingExport || isShowingAdjustments || isShowingOutline || isShowingImagePicker
            || isShowingPhotoPicker || isShowingCompress || isShowingOCR || isShowingRedact || isShowingCompare || isShowingDetails || isShowingCleanup
        #if os(iOS)
        presenting = presenting || cameraPurpose != nil || photoCameraPage != nil
        #endif
        return presenting
    }

    private var signatureButton: some View {
        Button { if let page = model.selectedPage { openInspectorTool(.signature(page)) } } label: {
            Label(L10n.signatureTitle, systemImage: "signature")
        }.accessibilityIdentifier("editor-signature")
    }

    private var formButton: some View {
        Button { openInspectorTool(.form) } label: {
            Label(L10n.formTitle, systemImage: "list.bullet.rectangle")
        }.accessibilityIdentifier("editor-fill-form")
    }

    private var pagesOrganizerButton: some View {
        Button { openInspectorTool(.pages) } label: {
            Label(L10n.pages, systemImage: "square.grid.2x2")
        }.accessibilityIdentifier("editor-pages")
    }

    // MARK: Document Tools sections

    /// Under the page thumbnails: add, organise, turn, remove.
    @ViewBuilder
    private var utilitiesPagesRow: some View {
        addPagesMenu {
            Label(L10n.documentUtilitiesAddPage, systemImage: "plus")
        }
        .menuIndicator(.hidden)
        .disabled(textSession.isSelected)
        .accessibilityLabel(L10n.addOrReplacePages)
        .accessibilityIdentifier("strip-add-pages")
        Button { openInspectorTool(.pages) } label: {
            Label(L10n.toolsOrganize, systemImage: "square.grid.2x2")
        }
        .accessibilityIdentifier("editor-pages")
        Button { Task { await model.rotate(clockwise: true, undoManager: undoManager) } } label: {
            Label(L10n.rotate, systemImage: "rotate.right")
        }
        .disabled(model.selectedPage == nil)
        .accessibilityIdentifier("utilities-rotate-page")
        deleteButton
    }

    @ViewBuilder
    private var utilitiesSections: some View {
        ToolGridSection(title: L10n.toolsEditPDF, systemImage: "slider.horizontal.below.square.filled.and.square",
                        storageKey: DocumentUtilitiesStorage.editExpanded, id: "utilities-section-edit") {
            cropButton
            rotateMenu
            filterMenu
            Button { runSplit() } label: { Label(L10n.toolsSplit, systemImage: "square.split.2x1") }
                .disabled(model.pages.count < 2 || isToolBusy)
                .accessibilityIdentifier("utilities-split")
            Menu { replacePageItems } label: {
                Label(L10n.toolsReplacePage, systemImage: "arrow.triangle.2.circlepath.doc.on.clipboard")
            }
            .menuIndicator(.hidden)
            .disabled(model.selectedPage == nil)
            .accessibilityIdentifier("utilities-replace-page")
        }
        ToolGridSection(title: L10n.toolsAnnotate, systemImage: "highlighter",
                        storageKey: DocumentUtilitiesStorage.annotateExpanded, id: "utilities-section-annotate") {
            textMarkupButton(.highlight, title: L10n.toolsHighlightText, symbol: "highlighter", id: "editor-annotate")
            textMarkupButton(.underline, title: L10n.toolsUnderlineText, symbol: "underline", id: "editor-annotate-underline")
            textMarkupButton(.strikethrough, title: L10n.toolsStrikeText, symbol: "strikethrough", id: "editor-annotate-strikethrough")
            commentsButton
            UtilityToggleTile(title: L10n.toolsDraw, systemImage: "pencil.tip.crop.circle", isOn: $isMarkingUp,
                              id: "editor-markup")
                .disabled(model.selectedPage == nil)
            #if os(iOS)
            UtilityToggleTile(title: L10n.drawWithFinger, systemImage: "hand.draw", isOn: $isFingerDrawing,
                              id: "editor-finger-drawing")
            #endif
            signatureButton
            manageMarkupButton
        }
        ToolGridSection(title: L10n.toolsInsert, systemImage: "plus.rectangle.on.rectangle",
                        storageKey: DocumentUtilitiesStorage.insertExpanded, id: "utilities-section-insert") {
            Button { armText() } label: { Label(L10n.toolText, systemImage: "character.textbox") }
                .disabled(model.selectedPage == nil || model.isChangingNotebookPage)
                .accessibilityIdentifier("utilities-insert-text")
            Menu { insertImageItems } label: { Label(L10n.toolImage, systemImage: "photo") }
                .menuIndicator(.hidden)
                .disabled(model.selectedPage == nil || model.isChangingNotebookPage || isLoadingPhoto)
                .accessibilityIdentifier("utilities-insert-image")
            shapeButton
            stampButton
            textStampButton
        }
        ToolGridSection(title: L10n.toolsProcess, systemImage: "gearshape.2",
                        storageKey: DocumentUtilitiesStorage.processExpanded, id: "utilities-section-process") {
            recognizeTextButton
            if !isNotebook {
                Button { openInspectorTool(.form) } label: {
                    Label(L10n.toolsFillForm, systemImage: "list.bullet.rectangle")
                }.accessibilityIdentifier("editor-fill-form")
            }
            Button { finishThen { openProTool(.compress) { isShowingCompress = true } } } label: {
                Label(L10n.toolsCompress, systemImage: "arrow.down.right.and.arrow.up.left")
            }
            .disabled(model.pages.isEmpty)
            .accessibilityIdentifier("utilities-compress")
            Button { finishThen { exportFormat = .docx; isShowingExport = true } } label: {
                Label(L10n.toolsConvert, systemImage: "doc.text")
            }
            .disabled(model.pages.isEmpty)
            .accessibilityIdentifier("utilities-convert")
            Button { finishThen { isShowingCompare = true } } label: {
                Label(L10n.compareTitle, systemImage: "rectangle.split.2x1")
            }
            .disabled(model.pages.isEmpty)
            .accessibilityIdentifier("utilities-compare")
            Button { finishThen { isShowingDetails = true } } label: {
                Label(L10n.detailsExtract, systemImage: "doc.text.magnifyingglass")
            }
            .disabled(model.selectedPage == nil)
            .accessibilityIdentifier("utilities-extract-details")
            Button { finishThen { isShowingCleanup = true } } label: {
                Label(L10n.cleanupButton, systemImage: "sparkles.rectangle.stack")
            }
            .disabled(model.pages.count < 2)
            .accessibilityIdentifier("utilities-cleanup")
            Button { finishThen { openProTool(.redact) { isShowingRedact = true } } } label: {
                Label(L10n.redactTitle, systemImage: "eye.slash")
            }
            .disabled(model.selectedPage == nil || model.isChangingNotebookPage)
            .accessibilityIdentifier("utilities-redact")
        }
    }

    private func textMarkupButton(_ style: TextMarkupStyle, title: String, symbol: String, id: String) -> some View {
        Button { annotationStyle = style; annotationPage = model.selectedPage } label: {
            Label { Text(verbatim: title) } icon: { Image(systemName: symbol) }
        }
        .disabled(model.selectedPage == nil || model.isRecognizing)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private var insertImageItems: some View {
        let actions = imageToolActions
        if let camera = actions.camera {
            Button(action: camera) { Label(L10n.takePhoto, systemImage: "camera") }
                .disabled(!actions.cameraSupported)
        }
        Button(action: actions.photos) { Label(L10n.importPhotos, systemImage: "photo.on.rectangle") }
        Button(action: actions.files) { Label(L10n.importFiles, systemImage: "folder") }
    }

    private func runSplit() {
        finishThen {
            pageToolBusy = true
            Task {
                defer { pageToolBusy = false }
                if let count = await model.split() { splitCount = count }
            }
        }
    }

    /// What a thumbnail's menu does. Each action first makes that page the
    /// current one, because the document's page operations act on the current
    /// page — and the reader should see the page that is about to change.
    private var pageGalleryActions: PageGalleryActions {
        func onPage(_ id: PageID, _ work: @escaping () async -> Void) {
            Task {
                guard await finishForAction(), model.pages.contains(where: { $0.id == id }) else { return }
                model.selectedPageID = id
                await work()
            }
        }
        return PageGalleryActions(
            select: { id in
                Task { if await textSession.finish(undoManager: undoManager) { model.selectedPageID = id } }
            },
            move: { id, delta in onPage(id) { await model.moveSelected(by: delta, undoManager: undoManager) } },
            reorder: { id, target in
                guard let from = model.pages.firstIndex(where: { $0.id == id }), from != target else { return }
                onPage(id) {
                    // movePages counts the moved page in its destination, as a List does.
                    await model.movePages(from: [from], to: target > from ? target + 1 : target, undoManager: undoManager)
                }
            },
            duplicate: { id in
                onPage(id) {
                    do { try await model.duplicateSelectedPage(undoManager: undoManager) }
                    catch { model.presentedError = .saveFailed() }
                }
            },
            rotate: { id, clockwise in onPage(id) { await model.rotate(clockwise: clockwise, undoManager: undoManager) } },
            delete: { id in onPage(id) { await model.deleteSelectedPage(undoManager: undoManager) } },
            export: { id in onPage(id) { isShowingExport = true } })
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
            case .pages, .ocr: break
            }
            if usesPDFToolsSidebar {
                inspectorTool = tool
                isShowingPDFTools = true
            } else {
                switch tool {
                case .signature(let page): signaturePage = page
                case .form: isShowingPDFForm = true
                case .pages: isShowingPageOrganizer = true
                case .ocr: isShowingOCR = true
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
                if editor.isShowingExport && editor.usesPDFToolsSidebar {
                    ExportLoader(itemID: editor.model.itemID, currentPageID: editor.model.selectedPageID,
                                 initialFormat: editor.exportFormat, isEmbedded: true,
                                 onClose: { editor.isShowingExport = false })
                } else if editor.isShowingCompress && editor.usesPDFToolsSidebar {
                    CompressSheet(itemID: editor.model.itemID, isEmbedded: true,
                                  onClose: { editor.isShowingCompress = false })
                } else {
                    inspectorContents
                }
            }
        }

        private var inspectorContents: some View {
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
                case .ocr:
                    OCRPanel(model: editor.model, undoManager: editor.undoManager, isEmbedded: true,
                             onClose: { editor.inspectorTool = nil },
                             beforeAction: { await editor.finishTextForPanelAction() })
                case nil:
                    toolList
                }
            }
        }

        private var toolList: some View {
            DocumentUtilitiesSidebar(model: editor.model, canClose: !editor.isToolBusy,
                                     close: { editor.closeUtilities() },
                                     pageActions: editor.pageGalleryActions) {
                editor.utilitiesPagesRow
            } sections: {
                editor.utilitiesSections.disabled(editor.textSession.isSelected)
            } footer: {
                UtilitiesExportButton { editor.finishThen { editor.isShowingExport = true } }
                    .disabled(editor.model.pages.isEmpty || editor.textSession.isSelected)
            }
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

    /// The lower floating bar: how the page is viewed, and nothing else.
    ///
    /// Zoom out, fit, zoom in; then whether a touch draws or moves the page;
    /// then display settings and the zoom in force. It used to show the armed
    /// tool's own icon as well — a second Lasso button under the first — and
    /// a row of colour swatches; tools and their colours live in the toolbar
    /// above and its panels now.
    private var studioPalette: some View {
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // On a phone, undo and redo stay down here under the thumb.
                // Wider windows have them at the end of the main toolbar.
                if isCompact {
                    NotebookHistoryActions(undoManager: undoManager, busy: model.isChangingNotebookPage,
                                           historyRevision: model.historyRevision,
                                           beforeAction: { await textSession.finish(undoManager: undoManager) })
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                }
                ViewportZoomControls(zoom: $zoom, showSettings: { isShowingDisplaySettings = true })
                barDivider
                pageStepper
                barDivider
                Button { isMarkingUp.toggle() } label: {
                    Image(systemName: "hand.draw").font(.system(size: 18))
                        .foregroundStyle(isMarkingUp ? Color.white : EditorChrome.navy)
                        .frame(width: 38, height: 38)
                        .background { if isMarkingUp { Circle().fill(EditorChrome.selection) } }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(L10n.displayDrawingMode)
                .accessibilityValue(isMarkingUp ? L10n.selectionOn : L10n.selectionOff)
                .accessibilityIdentifier("studio-drawing-toggle")
                .help(L10n.displayDrawingMode)
                Button { isShowingDisplaySettings = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 17)).frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(L10n.displaySettings)
                .accessibilityIdentifier("studio-tool-settings")
                .help(L10n.displaySettings)
                .popover(isPresented: $isShowingDisplaySettings, arrowEdge: .bottom) {
                    DisplaySettingsPopover(zoom: $zoom, fingerDrawing: $isFingerDrawing, nightMode: $isNightMode,
                                           // Two pages need the width: not on a phone, and a
                                           // notebook scrolls its pages in one column.
                                           twoPages: isCompact || isNotebook ? nil : $isTwoPages,
                                           coverAlone: isCompact || isNotebook ? nil : $isCoverAlone,
                                           fitWidth: isCompact ? nil : { fitWidthRequest += 1 },
                                           close: { isShowingDisplaySettings = false })
                        .presentationCompactAdaptation(.sheet)
                        .presentationDetents([.medium])
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .buttonStyle(.plain).foregroundStyle(EditorChrome.navy)
        .editorFloatingSurface(radius: 30)
        .frame(maxWidth: 620)
        .padding(12)
    }

    private var barDivider: some View {
        Rectangle().fill(EditorChrome.border).frame(width: 1, height: 24).accessibilityHidden(true)
    }

    /// Previous page, "3 / 12", next page. Goes through the same path as a
    /// thumbnail tap, so a text box being edited is saved first.
    private var pageStepper: some View {
        let index = model.selectedIndex ?? 0
        let count = model.pages.count
        // In two-page view a step is a spread, as in Acrobat.
        let bySpread = isTwoPages && !isCompact && !isNotebook
        func target(_ delta: Int) -> PageID? {
            if bySpread, let id = model.selectedPageID {
                return TwoPageView.step(from: id, by: delta, in: model.pages, coverAlone: isCoverAlone)
            }
            let target = index + delta
            return model.pages.indices.contains(target) ? model.pages[target].id : nil
        }
        func go(_ delta: Int) {
            guard let id = target(delta) else { return }
            Task { if await textSession.finish(undoManager: undoManager) { model.selectedPageID = id } }
        }
        return HStack(spacing: 0) {
            Button { go(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 44).contentShape(Rectangle())
            }
            .disabled(target(-1) == nil)
            .accessibilityLabel(L10n.pagePrevious)
            .accessibilityIdentifier("editor-page-previous")
            .help(L10n.pagePrevious)
            Text(verbatim: L10n.pageCounter(index + 1, max(count, 1)))
                .font(.subheadline.weight(.medium).monospacedDigit())
                .lineLimit(1).fixedSize()
                .frame(minWidth: 44)
                .accessibilityLabel(L10n.pageLabel(index + 1, of: max(count, 1)))
                .accessibilityIdentifier("editor-page-counter")
            Button { go(1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 44).contentShape(Rectangle())
            }
            .disabled(target(1) == nil)
            .accessibilityLabel(L10n.pageNext)
            .accessibilityIdentifier("editor-page-next")
            .help(L10n.pageNext)
        }
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
            textStampButton
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
                openInspectorTool(.ocr)
            } label: {
                Label(L10n.recognizeText, systemImage: "text.viewfinder")
            }
            .disabled(model.pages.isEmpty)
            .accessibilityIdentifier("editor-recognize")
        }
    }

    private var annotateTextButton: some View {
        Button { annotationStyle = .highlight; annotationPage = model.selectedPage } label: {
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

    /// Approved, Paid, a saved stamp or one's own words, as an editable text box.
    private var textStampButton: some View {
        Button { textStampPage = model.selectedPage } label: {
            Label(L10n.textStampTitle, systemImage: "checkmark.seal")
        }
        .disabled(model.selectedPage == nil || model.isChangingNotebookPage)
        .accessibilityIdentifier("editor-text-stamps")
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
            textStampButton
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
        Menu { addOnlyItems } label: { label() }
            .accessibilityIdentifier("editor-add-pages")
    }

    @ViewBuilder
    private var addOnlyItems: some View {
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
    }

    /// Everything that adds pages and everything that replaces one, for the
    /// menus that offer both.
    @ViewBuilder
    private var addPagesItems: some View {
        addOnlyItems
        if !isNotebook { Divider() }
        replacePageItems
    }

    @ViewBuilder
    private var replacePageItems: some View {
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
    /// The toolbar's settings as they stand: colour, width, pen, eraser and
    /// lasso choices all come from here, so there is one place they are read.
    var tools = EditorToolSettings()
    var usesStudioTools = false
    var selectAllRequest = 0
    var fitWidthRequest = 0
    var onLeaveSelection: () -> Void = {}
    var appendNotebookPage: ((PageID) -> Void)? = nil
    var canAppendNotebookPage = false
    /// Find in document, when the editor has it. Its hits are drawn over the page.
    var find: DocumentFind? = nil
    /// The words selected on the page, when the editor lets them be.
    var textSelection: PageTextSelectionModel? = nil
    /// Two-page view: the page being read and the one beside it, side by
    /// side. Only where the editor asks for it (wide enough, a document).
    var twoPages = false
    var coverAlone = false

    /// Whether a page pan should demand two fingers. Kept out of the body so
    /// the rule is named once and the type-checker is not asked to infer it
    /// inside an already-large expression. See `PageScrollTouchPolicy`.
    private var pageNeedsTwoFingers: Bool {
        PageScrollTouchPolicy.requiresTwoFingers(markingUp: isMarkingUp, tool: inkTool, fingerDrawing: fingerDrawing)
    }

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
        !isMarkingUp || inkTool == .lasso || inkTool == .shape
        #endif
    }

    /// The ink the freehand canvas should hold for a page.
    ///
    /// Normally all of it. With the eraser limited to handwriting or to
    /// highlights, only that kind: PencilKit erases whatever is on its canvas,
    /// so the way to protect a stroke from it is not to put the stroke there.
    private func canvasObjects(on page: Page) -> [PageObject] {
        let objects = model.selectedPageObjects.filter { $0.pageID == page.id }
        guard inkTool == .eraser, tools.eraserTarget != .all else { return objects }
        return tools.eraserTarget.erasable(in: objects)
    }

    /// iOS only: the ink the canvas was not given has to be drawn by the page
    /// underneath instead, or it would vanish while the eraser was in hand.
    private func pageDrawsProtectedInk(on page: Page) -> Bool {
        #if os(iOS)
        isMarkingUp && inkTool == .eraser && tools.eraserTarget != .all
        #else
        false
        #endif
    }
    @Environment(\.displayScale) private var displayScale
    @Environment(\.pageNightMode) private var isNight
    @Environment(\.readAloud) private var readAloud
    @State private var pinchBase: CGFloat?
    @State private var selectedMark: PageObjectID?
    @State private var pageFrame: CGRect = .zero
    @State private var lassoHiddenIDs: Set<PageObjectID> = []

    static let zoomSteps = PageZoom.steps

    @State private var scrollSelection: PageID?
    @State private var jumpTarget: PageID?
    @State private var isSelectingVisiblePage = false
    @State private var hasPositionedInitialPage = false
    /// The viewport's width when the visible page was last worked out, and a
    /// counter that asks for the current page to be brought back to centre.
    @State private var lastViewportWidth: CGFloat = 0
    @State private var recenterRequest = 0
    private var isContinuous: Bool { model.item?.kind == .notebook }

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { reader in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(spacing: isContinuous ? 20 : 0) {
                        if usesSpreads {
                            spreadSurface(in: proxy)
                        } else {
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
                            NotebookTouchScrolling(requiresTwoFingers: pageNeedsTwoFingers)
                        }
                    }
                    #endif
                }
                .accessibilityIdentifier("document-page-scroll")
                #if os(macOS)
                // The owner asked for the bar along the bottom gone and the
                // one down the right kept. Hiding the indicator for one axis
                // is presentation only: the page still pans horizontally by
                // trackpad, scroll wheel and drag, and the vertical indicator
                // keeps its normal behaviour. iOS already shows these only
                // while scrolling, so it is left alone.
                .scrollIndicators(.hidden, axes: .horizontal)
                #endif
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
                .background(isNight ? NightMode.canvas : Theme.canvas)
                .onChange(of: recenterRequest) { _, _ in
                    guard let id = model.selectedPageID else { return }
                    reader.scrollTo(id, anchor: .center)
                }
                .onChange(of: find?.shownFocus) { _, _ in
                    // The current hit is drawn; bring it into view.
                    withAnimation { reader.scrollTo(DocumentFind.anchorID, anchor: .center) }
                }
                .onChange(of: readAloud?.shownLine) { _, _ in
                    // The line being read moved: scroll only as far as it
                    // takes to keep it on screen, so a page that fits stays put.
                    withAnimation { reader.scrollTo(ReadAloud.anchorID) }
                }
                .onChange(of: fitWidthRequest) { _, _ in
                    // Fit is the whole page in the window. This is the page
                    // as wide as the window, however tall that leaves it.
                    guard let page = model.selectedPage else { return }
                    let fitted = fittedSize(page.geometry.pageSize, in: proxy.size)
                    let inset: CGFloat = showsZoomButtons ? 32 : 12
                    zoom = PageZoom.clamp(max(proxy.size.width - inset * 2, 50) / max(fitted.width, 1))
                }
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
        // The window changed width: Document Utilities opened or closed, the
        // device turned, the window was resized. Every page refits, so the
        // same scroll offset now shows a different page — and "most visible"
        // would quietly change the current page to a neighbour. Nobody
        // scrolled; hold the current page and bring it back to centre.
        if abs(viewport.width - lastViewportWidth) > 0.5 {
            let hadWidth = lastViewportWidth > 0
            lastViewportWidth = viewport.width
            if hadWidth, isContinuous, hasPositionedInitialPage, let id = model.selectedPageID {
                jumpTarget = id
                recenterRequest &+= 1
            }
            return
        }
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

    /// Two-page view applies: asked for, a document, and a spread to show.
    private var usesSpreads: Bool { twoPages && !isContinuous && model.selectedPage != nil }

    /// The spread holding the page being read: its pages side by side, each
    /// fitted to its share of the width. Each is an ordinary page surface —
    /// its own find hits, bookmark ribbon and night filter — and only the
    /// page being read carries the ink canvas and selection; touching the
    /// other makes it the page being read, as tapping a preview always has.
    private func spreadSurface(in proxy: GeometryProxy) -> some View {
        let spread = TwoPageView.spread(for: model.selectedPage, in: model.pages, coverAlone: coverAlone)
        let room = TwoPageView.room(for: spread.count, in: proxy.size)
        return HStack(alignment: .center, spacing: TwoPageView.gap) {
            ForEach(spread) { page in
                pageSurface(page, in: proxy, room: room)
                    .background {
                        GeometryReader { paper in
                            Color.clear.preference(key: NotebookPageFrames.self,
                                value: [page.id: paper.frame(in: .global)])
                        }
                    }
                    .id(page.id)
            }
        }
        .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("document-spread")
        .accessibilityValue(spread.compactMap { page in
            model.pages.firstIndex { $0.id == page.id }.map { String($0 + 1) }
        }.joined(separator: "-"))
    }

    private func pageSurface(_ page: Page, in proxy: GeometryProxy, room: CGSize? = nil) -> some View {
        let active = page.id == model.selectedPageID
        let index = model.pages.firstIndex(where: { $0.id == page.id }) ?? 0
        let fitted = fittedSize(page.geometry.pageSize, in: room ?? proxy.size)
        let held = textSession.page?.id == page.id ? textSession.canvasSize : nil
        let size = held.map { CGSize(width: $0.width * zoom / textSession.canvasZoom,
                                     height: $0.height * zoom / textSession.canvasZoom) }
            ?? CGSize(width: fitted.width * zoom, height: fitted.height * zoom)
        return PageImageView(page: page, pixelSize: max(size.width, size.height) * displayScale,
                      accessibilityLabel: L10n.pageLabel(index + 1, of: model.pages.count),
                      includesInk: !active || pageShowsInk || pageDrawsProtectedInk(on: page),
                      excludingObjectIDs: (textSession.page?.id == page.id ? textSession.excludedIDs : [])
                          .union(active ? lassoHiddenIDs : [])
                          .union(active && pageDrawsProtectedInk(on: page) ? Set(canvasObjects(on: page).map(\.id)) : []),
                      isNight: isNight)
            .accessibilityIdentifier(active ? "document-page-image" : "notebook-preview-\(page.id)")
            .accessibilityValue(active ? L10n.strokeCount(model.selectedPageObjects.filter {
                guard $0.pageID == page.id else { return false }
                if case .ink = $0.payload { return true }
                return false
            }.count) : "")
            .frame(width: size.width, height: size.height)
            // What find found on this page. It takes no touches.
            .overlay {
                if let find, find.isPresented {
                    let pageSize = page.geometry.pageSize
                    FindHighlightsOverlay(find: find, page: page,
                        sourceToView: page.geometry.sourceToPage.concatenating(
                            CGAffineTransform(scaleX: size.width / pageSize.width, y: size.height / pageSize.height)))
                }
            }
            // The word being read aloud. It takes no touches.
            .overlay {
                if readAloud?.pageID == page.id {
                    let pageSize = page.geometry.pageSize
                    ReadAloudHighlight(page: page,
                        sourceToView: page.geometry.sourceToPage.concatenating(
                            CGAffineTransform(scaleX: size.width / pageSize.width, y: size.height / pageSize.height)))
                }
            }
            // Selecting the page's own words. Only while reading: a drawing
            // tool owns the page, and so does a text box being typed in or
            // placed. Beneath the layers that move marks, so those keep
            // their touches.
            .overlay {
                if active, !isMarkingUp, !textSession.isSelected, !textSession.isPlacing, let textSelection {
                    let pageSize = page.geometry.pageSize
                    TextSelectionOverlay(selection: textSelection, model: model, page: page,
                        sourceToView: page.geometry.sourceToPage.concatenating(
                            CGAffineTransform(scaleX: size.width / pageSize.width, y: size.height / pageSize.height)),
                        undoManager: undoManager, claimsCopyShortcut: find?.isTyping != true)
                }
            }
            // The page's own links. Over the text selection, so a tap on a
            // link follows it; under the marks, which keep their touches.
            .overlay {
                if active, !isMarkingUp, !textSession.isSelected, !textSession.isPlacing {
                    let pageSize = page.geometry.pageSize
                    PageLinksOverlay(model: model, page: page,
                        sourceToView: page.geometry.sourceToPage.concatenating(
                            CGAffineTransform(scaleX: size.width / pageSize.width, y: size.height / pageSize.height)),
                        showPage: { activate($0, fromScroll: false) })
                }
            }
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
                        mode: tools.lassoMode, selectAllRequest: selectAllRequest, enablesTwoFingerNavigation: isContinuous,
                        allowed: tools.lassoContent, undoManager: undoManager,
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
            .overlay {
                if active && isMarkingUp && inkTool == .shape {
                    let pageSize = page.geometry.pageSize
                    ShapeDrawOverlay(
                        model: model, page: page,
                        sourceToView: page.geometry.sourceToPage.concatenating(
                            CGAffineTransform(scaleX: size.width / pageSize.width, y: size.height / pageSize.height)),
                        kind: tools.shapeKind, color: tools.shapeColor, width: tools.shapeWidth,
                        locksAspect: tools.shapeLocksAspect, undoManager: undoManager)
                }
            }
            #if os(macOS)
            .overlay {
                if active && isMarkingUp && inkTool != .lasso && inkTool != .shape {
                    let pageSize = page.geometry.pageSize
                    MacInkCanvas(
                        model: model, page: page,
                        sourceToView: page.geometry.sourceToPage.concatenating(
                            CGAffineTransform(scaleX: size.width / pageSize.width,
                                              y: size.height / pageSize.height)),
                        tool: inkTool, color: tools.color(for: inkTool), width: tools.width(for: inkTool),
                        eraserMode: tools.eraserMode, style: tools.drawingStyle(for: inkTool),
                        undoManager: undoManager)
                }
            }
            #endif
            #if os(iOS)
            .overlay {
                if active && isMarkingUp && inkTool != .lasso && inkTool != .shape {
                    let pageSize = page.geometry.pageSize
                    // Only this page's objects: right after a page switch the
                    // previous page's are still loaded.
                    InkCanvas(pageID: page.id, objects: canvasObjects(on: page),
                              sourceToView: page.geometry.sourceToPage.concatenating(
                                  CGAffineTransform(scaleX: size.width / pageSize.width, y: size.height / pageSize.height)),
                              fingerDrawing: fingerDrawing, documentUndoManager: undoManager,
                              studioTool: usesStudioTools ? inkTool : nil, enablesTwoFingerNavigation: isContinuous,
                              studioColor: tools.color(for: inkTool), studioWidth: tools.width(for: inkTool),
                              eraserMode: tools.eraserMode, style: tools.drawingStyle(for: inkTool),
                              zKeyFloor: model.selectedPageObjects.filter { $0.pageID == page.id }.map(\.zKey).max()) { saving, deleting in
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
            // The reader's mark on a bookmarked page. It takes no touches.
            .overlay(alignment: .topTrailing) { PageBookmarkRibbon(pageID: page.id) }
            // Night mode turns the page and everything drawn on it, live
            // ink and typing included. Last, so nothing is left out.
            .nightFilter(isNight)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PanelSection(title: L10n.brightness) {
                    Slider(value: $brightness, in: -0.5...0.5) { editing in
                        if !editing { commit() }
                    } label: {
                        Text(L10n.brightness)
                    }
                }
                PanelSection(title: L10n.contrast) {
                    Slider(value: $contrast, in: 0.5...2) { editing in
                        if !editing { commit() }
                    } label: {
                        Text(L10n.contrast)
                    }
                }
                Button(L10n.resetAdjustments) {
                    brightness = 0
                    contrast = 1
                    commit()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .frame(minWidth: 300)
        .toolPanelAppearance()
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

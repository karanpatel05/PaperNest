import PaperNestCore
import PaperNestExport
import SwiftUI
import UniformTypeIdentifiers

/// Loads an item's current pages, then shows the export options.
struct ExportLoader: View {
    let itemID: ItemID
    let currentPageID: PageID?
    /// Opens with this format chosen — "Convert" in Document Tools opens
    /// here with Word selected. Every gate still applies when it exports.
    var initialFormat: ExportFormat? = nil
    var isEmbedded = false
    var onClose: (() -> Void)? = nil
    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var loaded: (PaperNestCore.LibraryItem, [Page], DocumentPermissions)?
    @State private var failed = false

    var body: some View {
        Group {
            if let (item, pages, permissions) = loaded {
                ExportSheet(itemName: item.name, pages: pages, currentPageID: currentPageID, permissions: permissions,
                            initialFormat: initialFormat, isEmbedded: isEmbedded, onClose: onClose)
            } else if failed {
                VStack(spacing: 12) {
                    Text(L10n.exportFailed)
                    Button(L10n.done) { close() }
                }
                .padding(40)
            } else {
                ProgressView().padding(40)
            }
        }
        .task {
            guard let store = session.environment?.store else { return }
            do {
                guard let item = try await store.item(itemID) else { failed = true; return }
                let pages = try await store.pages(of: itemID)
                // What the sheet offers. The exporter decides again, from the
                // same originals, when the export is made.
                let permissions = (try? await session.environment?.renderer.permissions(for: pages)) ?? .unknown
                loaded = (item, pages, permissions)
            } catch {
                failed = true
            }
        }
    }
    private func close() { if let onClose { onClose() } else { dismiss() } }

}

/// Export, laid out as in the owner's mockup (`ipad-notebook-export.png`):
/// the document, Format tiles, Pages tiles and format options, with the
/// three ways out along the bottom. There is no Export button (owner,
/// 2026-11-13): one tap on a way out does the work. Save opens the save
/// dialog, Copy puts the file on the clipboard, Share opens the share sheet.
struct ExportSheet: View {
    let itemName: String
    let pages: [Page]
    let currentPageID: PageID?
    /// What the authors of these pages allow. A document whose author
    /// switched copying off can only leave as a PDF.
    var permissions = DocumentPermissions.unrestricted
    var initialFormat: ExportFormat? = nil
    var isEmbedded = false
    var onClose: (() -> Void)? = nil

    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var options = ExportOptions()
    @State private var pageChoice: PageChoice = .all
    @State private var rangeStart = 1
    @State private var rangeEnd = 1
    /// The files being handed to the system's share UI, while it is up.
    @State private var shareRequest: ShareRequest?
    @State private var phase: Phase = .configuring
    @State private var exportTask: Task<Void, Never>?
    @State private var isShowingSaver = false
    @State private var proFeature: ProFeature?
    /// Empty means no password, which is not the same as an empty one.
    @State private var password = ""
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    enum PageChoice: Hashable { case all, current, range }

    /// Where an export goes. Each is its own button: choosing one exports
    /// and hands the file over at once (owner, 2026-11-13). No "More" (the
    /// mockup has one): the share sheet already is "more".
    enum Destination: Hashable { case save, copy, share }

    enum Phase {
        case configuring
        case exporting(ExportProgress)
        case ready(ExportOutput)
        case copied
        case failed(String)
    }

    var body: some View {
        Group {
            if isEmbedded {
                VStack(alignment: .leading, spacing: 0) {
                    panelHeader
                    form
                    footer
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(EditorChrome.surface)
                }
            } else {
                standalone
            }
        }
        .toolPanelAppearance(isEmbedded: isEmbedded)
        .modifier(lifecycle)
        .proPaywall($proFeature)
    }

    private var standalone: some View {
        #if os(iOS)
        NavigationStack {
            form
                .navigationTitle(L10n.exportTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { close() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel(L10n.cancel)
                            .accessibilityIdentifier("export-close")
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    footer
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(EditorChrome.surface)
                }
        }
        #else
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            form
            footer.padding(16).background(EditorChrome.surface)
        }
        // A bounded sheet avoids content-driven AppKit constraint cycles.
        .frame(minWidth: 460, idealWidth: 540, minHeight: 360, idealHeight: 620, maxHeight: 680)
        #endif
    }

    private var panelHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.and.arrow.up")
                .font(.title3.weight(.medium))
                .foregroundStyle(EditorChrome.purple)
                .frame(width: 38, height: 38)
                .background(EditorChrome.lavender, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            Text(L10n.exportTitle).font(.headline).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button { close() } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(EditorChrome.lavender, in: Circle())
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.cancel)
            .accessibilityIdentifier("export-close")
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(EditorChrome.surface)
    }

    private func close() { if let onClose { onClose() } else { dismiss() } }

    private var lifecycle: ExportLifecycle {
        ExportLifecycle(onAppear: {
            rangeEnd = pages.count
            if !SubscriptionStore.shared.allows(.textExport) { options.includesRecognizedText = false }
        }, onDisappear: {
            exportTask?.cancel()
            if case .ready(let output) = phase { output.removeTemporaryFiles() }
        }, saver: SaveExportedFiles(isPresented: $isShowingSaver, output: readyOutput, format: options.format) {
            close()
        })
    }

    private var form: some View {
        formContent.onAppear {
            // Once: choosing another format afterwards must stick.
            if let initialFormat, !appliedInitialFormat { options.format = initialFormat }
            appliedInitialFormat = true
        }
    }

    @State private var appliedInitialFormat = false

    private var formContent: some View {
        Form {
            Section {
                documentRow
            }
            Section {
                // Three tiles at a time, so six formats do not squeeze each
                // other into unreadable slivers on a phone.
                ForEach(Array(Self.formats(offeredFor: permissions).chunked(into: 3).enumerated()), id: \.offset) { _, row in
                    tileRow {
                        ForEach(row, id: \.format) { tile in
                            ChoiceTile(title: tile.title, systemImage: tile.systemImage,
                                       iconColor: tile.iconColor ?? .secondary,
                                       isSelected: options.format == tile.format,
                                       identifier: "export-format-\(tile.format.rawValue)") {
                                options.format = tile.format
                            }
                        }
                    }
                }
            } header: {
                Text(L10n.exportFormat)
            } footer: {
                // Under the tiles rather than in `formatOptions`: a Form
                // Section whose content is empty is dropped whole, footer
                // and all, so a caveat with no controls beside it has to
                // live on a section that has some.
                // Word says what each of its layouts keeps under its own
                // tiles, below; TXT has only the one.
                if options.keepsOnlyWords, options.format != .docx { wordsOnlyNote }
                // Why five formats are missing, said where they would be.
                if !permissions.allowsCopying {
                    Text(L10n.restrictedExportNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("export-restricted-note")
                }
            }
            docxLayoutSection
            passwordSection
            Section(L10n.exportPages) {
                tileRow {
                    ChoiceTile(title: L10n.exportAllPages, subtitle: L10n.pageCount(pages.count),
                               isSelected: pageChoice == .all, identifier: "export-pages-all") { pageChoice = .all }
                    if let currentIndex {
                        ChoiceTile(title: L10n.exportCurrentPage, subtitle: L10n.pageLabel(currentIndex + 1, of: pages.count),
                                   isSelected: pageChoice == .current, identifier: "export-pages-current") { pageChoice = .current }
                    }
                    ChoiceTile(title: L10n.exportRange, subtitle: "\(rangeStart)–\(rangeEnd)",
                               isSelected: pageChoice == .range, identifier: "export-pages-range") { pageChoice = .range }
                }
                if pageChoice == .range {
                    Stepper(value: $rangeStart, in: 1...max(pages.count, 1)) {
                        LabeledContent(L10n.exportFrom, value: rangeStart.formatted())
                    }
                    Stepper(value: $rangeEnd, in: 1...max(pages.count, 1)) {
                        LabeledContent(L10n.exportTo, value: rangeEnd.formatted())
                    }
                }
            }
            formatOptions
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(EditorChrome.secondaryBackground)
        .tint(Theme.accent)
        .disabled(isBusyOrDone)
    }

    private var documentRow: some View {
        HStack(spacing: 12) {
            if let cover = pages.first {
                PageImageView(page: cover, pixelSize: 240)
                    .frame(width: 44, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .shadow(color: Theme.paperShadow, radius: 5, y: 3)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(itemName).font(.headline).fixedSize(horizontal: false, vertical: true)
                Text(L10n.pageCount(pages.count)).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Tiles side by side, or stacked when their labels don't fit (long
    /// French and Spanish labels on a phone).
    private func tileRow(@ViewBuilder _ tiles: () -> some View) -> some View {
        #if os(macOS)
        // ViewThatFits inside a grouped Mac Form enters an AttributeGraph
        // preference cycle when this sheet opens. The desktop sheet has
        // room for one stable row; labels can still wrap within each tile.
        HStack(spacing: 10) { tiles() }
            .fixedSize(horizontal: false, vertical: true)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8))
        #else
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) { tiles() }
            } else {
                ViewThatFits(in: .horizontal) {
                    // Tiles in a row share the tallest one's height.
                    HStack(spacing: 10) { tiles() }
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 8) { tiles() }
                }
            }
        }
        .listRowBackground(Color.clear)
        // Inset from the row's edges: rows clip to large rounded corners,
        // which would cut into the tiles' borders.
        .listRowInsets(EdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8))
        #endif
    }

    /// The password to hand the exporter: **nil when the field is empty**,
    /// which means no password rather than an empty one. The engine refuses
    /// `""`, because written as both the user and the owner password it
    /// produces a file that opens with nothing while the caller believes it
    /// is protected — and an untouched field is the likeliest source of it.
    nonisolated static func passwordToUse(_ typed: String) -> String? {
        typed.isEmpty ? nil : typed
    }

    /// What is wrong with a typed password, or nil when it can be used.
    ///
    /// Checked where it is typed rather than after the export fails: the
    /// writer cannot store anything outside ASCII — measured, not inferred,
    /// since `"été-Ñandú-2026"` was refused as well as `"contraseña-密码-1"` —
    /// and that is a real limitation for French and Spanish readers which
    /// deserves to be named rather than returned as "export failed".
    nonisolated static func passwordProblem(in typed: String, format: ExportFormat) -> ExportError? {
        guard let password = passwordToUse(typed) else { return nil }
        guard format.canCarryPassword else { return .passwordNotSupported }
        guard password.allSatisfy(\.isASCII) else { return .passwordNotRepresentable }
        return nil
    }

    /// Whether only part of this password will actually be honoured.
    ///
    /// Revision 4 reads the first 32 **bytes**. The whole password still
    /// opens the file, so this is not a refusal — but someone typing a long
    /// passphrase believes all of it is protecting them, and it is not.
    nonisolated static func passwordIsTruncated(_ typed: String) -> Bool {
        typed.utf8.count > 32
    }

    /// Every format the engine can write, with how it is offered.
    ///
    /// Data rather than hand-written tiles because three working formats —
    /// TXT, HEIC and DOCX — shipped unreachable behind a list of three that
    /// was never updated. `ExportFormatOfferTests` fails if a format is
    /// missing from here.
    ///
    /// The titles are the formats' own names, so they are not translated and
    /// go through `Text(verbatim:)` inside the tile.
    /// The formats offered for a document with these limits. Where copying
    /// is switched off only a PDF is: it is the one format that can carry the
    /// author's limits out with the pages, and offering the others would be
    /// offering something the exporter refuses.
    nonisolated static func formats(offeredFor permissions: DocumentPermissions)
        -> [(format: ExportFormat, title: String, systemImage: String, iconColor: Color?)] {
        permissions.allowsCopying ? offeredFormats : offeredFormats.filter { $0.format == .pdf }
    }

    nonisolated static let offeredFormats: [(format: ExportFormat, title: String, systemImage: String, iconColor: Color?)] = [
        (.pdf, "PDF", "doc.richtext", .red),
        (.jpeg, "JPEG", "photo", nil),
        (.png, "PNG", "photo.artframe", nil),
        (.heic, "HEIC", "photo.badge.checkmark", nil),
        (.txt, "TXT", "doc.plaintext", nil),
        (.docx, "Word", "doc.text", .blue),
    ]

    private var wordsOnlyNote: some View {
        Text(L10n.exportWordsOnlyNote)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("export-words-only-note")
    }

    /// Word's two layouts, which the brief asks for "clearly named": words
    /// to edit, or pictures of the pages. Each says under the tiles what it
    /// keeps and what it gives up, so the picture layout is never taken for
    /// an editable conversion.
    @ViewBuilder private var docxLayoutSection: some View {
        if options.format == .docx {
            Section {
                tileRow {
                    ChoiceTile(title: L10n.exportDocxLayoutText, subtitle: L10n.exportDocxLayoutTextDetail,
                               isSelected: options.docxLayout == .editableText,
                               identifier: "export-docx-layout-editableText") { options.docxLayout = .editableText }
                    ChoiceTile(title: L10n.exportDocxLayoutImages, subtitle: L10n.exportDocxLayoutImagesDetail,
                               isSelected: options.docxLayout == .pageImages,
                               identifier: "export-docx-layout-pageImages") { options.docxLayout = .pageImages }
                }
            } header: {
                Text(L10n.exportDocxLayout)
            } footer: {
                if options.keepsOnlyWords {
                    wordsOnlyNote
                } else {
                    Text(L10n.exportDocxImagesNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("export-docx-images-note")
                }
            }
        }
    }

    /// A password for the exported PDF, and what it cannot be.
    ///
    /// Offered only where it can be kept. The problem is shown as it is
    /// typed rather than after the export fails: the writer stores nothing
    /// outside ASCII, which is a real limitation for anyone whose password
    /// has an accent in it, and finding that out from "export failed" would
    /// send them looking for the wrong thing.
    @ViewBuilder private var passwordSection: some View {
        if options.format.canCarryPassword {
            Section {
                SecureField(L10n.exportPasswordField, text: $password)
                    .accessibilityIdentifier("export-password")
                if let problem = passwordProblem {
                    Text(Self.message(for: problem))
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("export-password-problem")
                } else if Self.passwordIsTruncated(password) {
                    Text(L10n.exportPasswordTruncated)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("export-password-truncated")
                }
            } header: {
                Text(L10n.exportPasswordTitle)
            } footer: {
                Text(L10n.exportPasswordFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var passwordProblem: ExportError? {
        Self.passwordProblem(in: password, format: options.format)
    }

    /// What each refusal means to someone reading it, rather than its name.
    nonisolated static func message(for error: ExportError) -> String {
        switch error {
        case .noTextToExport: L10n.exportNoTextToExport
        case .passwordNotRepresentable: L10n.exportPasswordNotRepresentable
        case .passwordNotSupported: L10n.exportPasswordNotSupported
        case .emptyPassword: L10n.exportPasswordEmpty
        case .copyingNotAllowed: L10n.restrictedExportRefused
        case .printingNotAllowed: L10n.restrictedPrintRefused
        case .noPages, .writeFailed, .archiveTooLarge: L10n.exportFailed
        }
    }

    @ViewBuilder
    private var formatOptions: some View {
        // Nothing at all for a format that holds only the words: no
        // resolution, no quality, no packaging, because none of them touch
        // it. What is lost is said under the format tiles instead.
        if options.keepsOnlyWords {
            EmptyView()
        } else if options.format == .pdf {
            Section {
                paperSizePicker
                Picker(L10n.imageQuality, selection: $options.pdfImageQuality) {
                    Text(L10n.qualityBest).tag(PDFImageQuality.best)
                    Text(L10n.qualityBalanced).tag(PDFImageQuality.balanced)
                    Text(L10n.qualityCompact).tag(PDFImageQuality.compact)
                }
                .choicePickerStyle()
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if options.paperSize != .original { Text(L10n.paperNote) }
                    Text(L10n.exportVectorNote)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } else if options.format == .docx {
            // Word page images: each page is a JPEG on a Word page, so the
            // controls are a picture's — and the paper, as for a PDF. No
            // packaging: it is one Word file however many pages.
            Section {
                paperSizePicker
                resolutionPicker
                LabeledContent(L10n.jpegQuality) {
                    Slider(value: $options.jpegQuality, in: 0.3...1)
                        .frame(minWidth: 160)
                }
            } footer: {
                if options.paperSize != .original {
                    Text(L10n.paperNote).font(.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            Section {
                resolutionPicker
                if options.format == .jpeg {
                    LabeledContent(L10n.jpegQuality) {
                        Slider(value: $options.jpegQuality, in: 0.3...1)
                            .frame(minWidth: 160)
                    }
                }
                if selectedPages.count > 1 {
                    Picker(L10n.multiplePages, selection: $options.packaging) {
                        Text(L10n.packagingZip).tag(ImagePackaging.zip)
                        Text(L10n.packagingSeparate).tag(ImagePackaging.separateFiles)
                    }
                    .choicePickerStyle()
                }
            }
        }
    }

    private var paperSizePicker: some View {
        Picker(L10n.paperSize, selection: $options.paperSize) {
            Text(L10n.paperOriginal).tag(PaperSize.original)
            Text(L10n.paperLetter).tag(PaperSize.usLetter)
            Text(L10n.paperA4).tag(PaperSize.a4)
        }
        .choicePickerStyle()
    }

    private var resolutionPicker: some View {
        Picker(L10n.resolution, selection: $options.imageDPI) {
            ForEach(ExportOptions.imageDPIChoices, id: \.self) { Text(L10n.dpi($0)).tag($0) }
        }
        .choicePickerStyle()
    }

    /// What the sheet says, then the three ways out. Each action exports
    /// with the options above and hands the file over in the same tap; there
    /// is no separate Export button and no second Share or Save to press.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            status
            if showsActions { actions }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch phase {
        case .configuring:
            if !rangeIsValid {
                Text(L10n.exportInvalidRange).font(.caption).foregroundStyle(.red)
            }
            if producesArchive {
                Text(L10n.exportCopyUnavailable).font(.caption).foregroundStyle(.secondary)
            }
        case .exporting(let progress):
            HStack {
                ProgressView(value: progress.fraction) {
                    Text(L10n.exportProgress(min(progress.completedPages + 1, progress.totalPages), progress.totalPages))
                        .font(.caption)
                }
                Button(L10n.cancel, role: .cancel) {
                    exportTask?.cancel()
                    phase = .configuring
                }
            }
        case .ready(let output):
            // Also where a closed save dialog or share sheet lands: the files
            // are kept, so the same three buttons work without exporting again.
            Text(L10n.exportReady(ByteCountFormatter.string(fromByteCount: output.totalByteCount, countStyle: .file)))
                .font(.callout)
                .accessibilityIdentifier("export-ready")
        case .copied:
            HStack {
                Label(L10n.exportCopied, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("export-copied")
                Spacer()
                Button(L10n.done) { close() }
                    .keyboardShortcut(.defaultAction)
            }
        case .failed(let message):
            HStack {
                Text(message).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("export-failed")
                Spacer()
                Button(L10n.done) { close() }
            }
        }
    }

    /// The actions stay on screen while an export is made and handed over,
    /// so the share sheet keeps the Share button to point at.
    private var showsActions: Bool {
        switch phase {
        case .configuring, .exporting, .ready: true
        case .copied, .failed: false
        }
    }

    private var actionsEnabled: Bool {
        switch phase {
        case .configuring: canExport
        case .ready: true
        default: false
        }
    }

    @ViewBuilder
    private var actions: some View {
        #if os(iOS)
        HStack(spacing: 10) {
            actionButton(L10n.exportToFiles, systemImage: "folder", enabled: actionsEnabled,
                         identifier: "export-destination-save") { perform(.save) }
            actionButton(L10n.exportCopy, systemImage: "doc.on.doc", enabled: actionsEnabled && !producesArchive,
                         identifier: "export-destination-copy") { perform(.copy) }
            actionButton(L10n.exportShareTile, systemImage: "square.and.arrow.up", enabled: actionsEnabled,
                         identifier: "export-destination-share") { perform(.share) }
                .background(SystemSharePresenter(request: $shareRequest, finished: shareFinished))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.exportDestination)
        #else
        Group {
            if isEmbedded {
                VStack(spacing: 10) {
                    Button { perform(.copy) } label: {
                        Label(L10n.exportCopy, systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!actionsEnabled || producesArchive)
                    .accessibilityIdentifier("export-destination-copy")
                    Button { perform(.share) } label: {
                        Label(L10n.exportShareTile, systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!actionsEnabled)
                    .background(SystemSharePresenter(request: $shareRequest, finished: shareFinished))
                    .accessibilityIdentifier("export-destination-share")
                    Button { perform(.save) } label: {
                        Label(L10n.exportToDisk, systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!actionsEnabled)
                    .accessibilityIdentifier("export-destination-save")
                }
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            } else {
                HStack {
                    Spacer()
                    if case .configuring = phase {
                        Button(L10n.cancel, role: .cancel) { close() }
                            .keyboardShortcut(.cancelAction)
                    }
                    Button(L10n.exportCopy) { perform(.copy) }
                        .disabled(!actionsEnabled || producesArchive)
                        .accessibilityIdentifier("export-destination-copy")
                    Button(L10n.exportShareTile) { perform(.share) }
                        .disabled(!actionsEnabled)
                        .background(SystemSharePresenter(request: $shareRequest, finished: shareFinished))
                        .accessibilityIdentifier("export-destination-share")
                    // Return saves, as the Export button it replaces did.
                    Button(L10n.exportToDisk) { perform(.save) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!actionsEnabled)
                        .accessibilityIdentifier("export-destination-save")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.exportDestination)
        #endif
    }

    #if os(iOS)
    /// Icon over name, the height of the Export button it replaces.
    private func actionButton(_ title: String, systemImage: String, enabled: Bool, identifier: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.title3)
                Text(title).font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .disabled(!enabled)
        .accessibilityIdentifier(identifier)
    }
    #endif

    /// Exports with the options above and hands the result over; once an
    /// export is made, hands that one over again rather than redoing it.
    private func perform(_ target: Destination) {
        guard case .ready(let output) = phase else { startExport(to: target); return }
        switch target {
        case .save: isShowingSaver = true
        case .share: shareRequest = ShareRequest(files: output.files)
        case .copy:
            do {
                try Clipboard.write(files: output.files)
                output.removeTemporaryFiles()
                phase = .copied
            } catch {
                phase = .failed(L10n.exportFailed)
            }
        }
    }

    /// A share target has the files: the sheet's work is done. Closed without
    /// one, the export stays ready for another try.
    private func shareFinished(_ shared: Bool) {
        if shared { close() }
    }

    private var isBusyOrDone: Bool {
        if case .configuring = phase { return false }
        return true
    }

    private var readyOutput: ExportOutput? {
        if case .ready(let output) = phase { return output }
        return nil
    }

    private var currentIndex: Int? {
        currentPageID.flatMap { id in pages.firstIndex { $0.id == id } }
    }

    /// Nothing is exported while the sheet is showing a reason it cannot be.
    private var canExport: Bool { rangeIsValid && passwordProblem == nil }

    private var rangeIsValid: Bool {
        pageChoice != .range || (1...pages.count).contains(rangeStart) && (rangeStart...pages.count).contains(rangeEnd)
    }

    /// Several image pages packed as one ZIP, which the clipboard can't
    /// usefully hold. The engine's rule rather than a guess: this used to
    /// treat any non-PDF of several pages as a ZIP, and so refused Copy for a
    /// multi-page TXT or Word file, which is one file.
    private var producesArchive: Bool {
        options.writesArchive(pageCount: selectedPages.count)
    }

    /// Selected pages in document order.
    private var selectedPages: [Page] {
        switch pageChoice {
        case .all:
            return pages
        case .current:
            return pages.filter { $0.id == currentPageID }
        case .range:
            guard rangeIsValid else { return [] }
            return Array(pages[(rangeStart - 1)...(rangeEnd - 1)])
        }
    }

    private func startExport(to target: Destination) {
        let needed: ProFeature? = if options.format == .txt || options.format == .docx
            || (options.format == .pdf && options.includesRecognizedText) { .textExport }
            else if options.format == .pdf && !password.isEmpty { .passwordExport } else { nil }
        if let needed, !SubscriptionStore.shared.allows(needed) { proFeature = needed; return }
        guard let exporter = session.environment?.exporter else { return }
        let selection = selectedPages
        let options = options
        let name = itemName
        let password = Self.passwordToUse(password)
        phase = .exporting(ExportProgress(completedPages: 0, totalPages: selection.count))
        exportTask = Task {
            do {
                let output = try await exporter.export(itemName: name, pages: selection, options: options,
                                                       password: password) { progress in
                    Task { @MainActor in
                        if case .exporting = phase { phase = .exporting(progress) }
                    }
                }
                if Task.isCancelled {
                    output.removeTemporaryFiles()
                    return
                }
                switch target {
                case .save:
                    phase = .ready(output)
                    isShowingSaver = true
                case .share:
                    phase = .ready(output)
                    shareRequest = ShareRequest(files: output.files)
                case .copy:
                    try Clipboard.write(files: output.files)
                    output.removeTemporaryFiles()
                    phase = .copied
                }
            } catch is CancellationError {
                phase = .configuring
            } catch let error as ExportError {
                // Each refusal says what it is. "Export failed" on a
                // document of scanned pages nobody has recognised yet, or on
                // a password with an accent in it, sends someone looking for
                // a bug that is not there.
                phase = .failed(Self.message(for: error))
            } catch {
                phase = .failed(L10n.exportFailed)
            }
        }
    }
}

private extension Array {
    /// Fixed-size groups, for laying tiles out a row at a time.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

/// One choice in a row of tiles: an optional icon, a title and an optional
/// detail line; the selected tile has an accent border and a checkmark.
/// Its own button style keeps each tile's tap separate inside a Form row.
struct ChoiceTile: View {
    /// Already localized (format names are the same in every language).
    let title: String
    var subtitle: String?
    var systemImage: String?
    var iconColor: Color = .secondary
    let isSelected: Bool
    var isEnabled = true
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .foregroundStyle(iconColor)
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 68, maxHeight: .infinity)
        }
        .buttonStyle(ChoiceTileStyle(isSelected: isSelected))
        .disabled(!isEnabled)
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.white, Theme.accent)
                    .offset(x: 6, y: -6)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

private struct ChoiceTileStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.primary)
            .background(isSelected ? EditorChrome.lavender : EditorChrome.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? Theme.accent.opacity(0.55) : Theme.separator, lineWidth: 1)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Appear/disappear handling and the save dialog, shared by the iOS and
/// Mac layouts of the sheet.
private struct ExportLifecycle: ViewModifier {
    let onAppear: () -> Void
    let onDisappear: () -> Void
    let saver: SaveExportedFiles

    func body(content: Content) -> some View {
        content
            .onAppear(perform: onAppear)
        .onDisappear(perform: onDisappear)
            .modifier(saver)
    }
}

private extension View {
    /// Settings-style option rows on iOS, where pop-up menus truncate long
    /// French and Spanish values next to their labels; pop-up menus on Mac.
    @ViewBuilder
    func choicePickerStyle() -> some View {
        #if os(iOS)
        pickerStyle(.inline)
        #else
        pickerStyle(.menu)
        #endif
    }
}

/// Presents the system save panel (Mac) or document picker (iOS) for the
/// exported files.
struct SaveExportedFiles: ViewModifier {
    @Binding var isPresented: Bool
    let output: ExportOutput?
    let format: ExportFormat
    let onSaved: () -> Void

    func body(content: Content) -> some View {
        let files = output?.files ?? []
        let type = files.first.map(Self.contentType(for:)) ?? .data
        if files.count > 1 {
            content.fileExporter(isPresented: $isPresented, documents: files.map(ExportedFile.init), contentType: type) { result in
                if case .success = result { onSaved() }
            }
        } else {
            content.fileExporter(isPresented: $isPresented, document: files.first.map(ExportedFile.init), contentType: type,
                                 defaultFilename: files.first?.lastPathComponent) { result in
                if case .success = result { onSaved() }
            }
        }
    }

    static func contentType(for url: URL) -> UTType {
        UTType(filenameExtension: url.pathExtension) ?? .data
    }
}

/// Hands an already-written temporary file to the system save UI.
struct ExportedFile: FileDocument {
    static let readableContentTypes: [UTType] = []
    // This wrapper copies existing bytes; it never converts formats. Every
    // caller supplies the actual type. Advertising a limited format list makes
    // the Mac save panel silently select PDF for an arbitrary file (e.g. TXT).
    static let writableContentTypes: [UTType] = [.data]
    let url: URL

    init(url: URL) {
        self.url = url
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url, options: .immediate)
    }
}

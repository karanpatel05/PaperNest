import PaperNestCore
import PaperNestExport
import SwiftUI
import UniformTypeIdentifiers

/// Loads an item's current pages, then shows the export options.
struct ExportLoader: View {
    let itemID: ItemID
    let currentPageID: PageID?
    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var loaded: (PaperNestCore.LibraryItem, [Page])?
    @State private var failed = false

    var body: some View {
        Group {
            if let (item, pages) = loaded {
                ExportSheet(itemName: item.name, pages: pages, currentPageID: currentPageID)
            } else if failed {
                VStack(spacing: 12) {
                    Text(L10n.exportFailed)
                    Button(L10n.done) { dismiss() }
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
                loaded = (item, try await store.pages(of: itemID))
            } catch {
                failed = true
            }
        }
    }
}

/// Export, laid out as in the owner's mockup (`ipad-notebook-export.png`):
/// the document, Format tiles, Pages tiles, format options, where the
/// export goes, then one Export button. Choosing the destination first
/// means one tap does the work: Save opens the save dialog, Copy puts the
/// file on the clipboard, Share offers the share sheet.
struct ExportSheet: View {
    let itemName: String
    let pages: [Page]
    let currentPageID: PageID?

    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var options = ExportOptions()
    @State private var pageChoice: PageChoice = .all
    @State private var rangeStart = 1
    @State private var rangeEnd = 1
    @State private var destination: Destination = .save
    @State private var phase: Phase = .configuring
    @State private var exportTask: Task<Void, Never>?
    @State private var isShowingSaver = false
    /// Empty means no password, which is not the same as an empty one.
    @State private var password = ""

    enum PageChoice: Hashable { case all, current, range }

    /// No "More" tile (the mockup has one): the share sheet already is
    /// "more". Claude's call, see CLEAN_NATIVE_DESIGN.md.
    enum Destination: Hashable { case save, copy, share }

    enum Phase {
        case configuring
        case exporting(ExportProgress)
        case ready(ExportOutput)
        case copied
        case failed(String)
    }

    var body: some View {
        #if os(iOS)
        NavigationStack {
            form
                .navigationTitle(L10n.exportTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.cancel) { dismiss() }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    footer
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.bar)
                }
        }
        .modifier(lifecycle)
        #else
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.exportTitle)
                .font(.headline)
                .padding([.horizontal, .top])
            form
            footer
                .padding()
        }
        // Sheets on macOS size to their content.
        .frame(minWidth: 460, idealWidth: 500, minHeight: 520)
        .modifier(lifecycle)
        #endif
    }

    private var lifecycle: ExportLifecycle {
        ExportLifecycle(onAppear: { rangeEnd = pages.count }, onDisappear: {
            exportTask?.cancel()
            if case .ready(let output) = phase { output.removeTemporaryFiles() }
        }, saver: SaveExportedFiles(isPresented: $isShowingSaver, output: readyOutput, format: options.format) {
            dismiss()
        })
    }

    private var form: some View {
        Form {
            Section {
                documentRow
            }
            Section {
                // Three tiles at a time, so six formats do not squeeze each
                // other into unreadable slivers on a phone.
                ForEach(Array(Self.offeredFormats.chunked(into: 3).enumerated()), id: \.offset) { _, row in
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
                if options.format.keepsOnlyWords {
                    Text(L10n.exportWordsOnlyNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("export-words-only-note")
                }
            }
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
            Section {
                tileRow {
                    #if os(iOS)
                    ChoiceTile(title: L10n.exportToFiles, systemImage: "folder",
                               isSelected: effectiveDestination == .save, identifier: "export-destination-save") { destination = .save }
                    #else
                    ChoiceTile(title: L10n.exportToDisk, systemImage: "square.and.arrow.down",
                               isSelected: effectiveDestination == .save, identifier: "export-destination-save") { destination = .save }
                    #endif
                    ChoiceTile(title: L10n.exportCopy, systemImage: "doc.on.doc",
                               isSelected: effectiveDestination == .copy, isEnabled: !producesArchive,
                               identifier: "export-destination-copy") { destination = .copy }
                    ChoiceTile(title: L10n.exportShareTile, systemImage: "square.and.arrow.up",
                               isSelected: effectiveDestination == .share, identifier: "export-destination-share") { destination = .share }
                }
            } header: {
                Text(L10n.exportDestination)
            } footer: {
                if producesArchive {
                    Text(L10n.exportCopyUnavailable)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(isBusyOrDone)
    }

    private var documentRow: some View {
        HStack(spacing: 12) {
            if let cover = pages.first {
                PageImageView(page: cover, pixelSize: 120)
                    .frame(width: 34, height: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(itemName).font(.headline).lineLimit(2)
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
        ViewThatFits(in: .horizontal) {
            // Tiles in a row share the tallest one's height.
            HStack(spacing: 10) { tiles() }
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) { tiles() }
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
    static let offeredFormats: [(format: ExportFormat, title: String, systemImage: String, iconColor: Color?)] = [
        (.pdf, "PDF", "doc.richtext", .red),
        (.jpeg, "JPEG", "photo", nil),
        (.png, "PNG", "photo.artframe", nil),
        (.heic, "HEIC", "photo.badge.checkmark", nil),
        (.txt, "TXT", "doc.plaintext", nil),
        (.docx, "Word", "doc.text", .blue),
    ]

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
        case .noPages, .writeFailed, .archiveTooLarge: L10n.exportFailed
        }
    }

    @ViewBuilder
    private var formatOptions: some View {
        // Nothing at all for a format that holds only the words: no
        // resolution, no quality, no packaging, because none of them touch
        // it. What is lost is said under the format tiles instead.
        if options.format.keepsOnlyWords {
            EmptyView()
        } else if options.format == .pdf {
            Section {
                Picker(L10n.paperSize, selection: $options.paperSize) {
                    Text(L10n.paperOriginal).tag(PaperSize.original)
                    Text(L10n.paperLetter).tag(PaperSize.usLetter)
                    Text(L10n.paperA4).tag(PaperSize.a4)
                }
                .choicePickerStyle()
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
        } else {
            Section {
                Picker(L10n.resolution, selection: $options.imageDPI) {
                    ForEach(ExportOptions.imageDPIChoices, id: \.self) { Text(L10n.dpi($0)).tag($0) }
                }
                .choicePickerStyle()
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

    @ViewBuilder
    private var footer: some View {
        switch phase {
        case .configuring:
            VStack(alignment: .leading, spacing: 8) {
                if !rangeIsValid {
                    Text(L10n.exportInvalidRange).font(.caption).foregroundStyle(.red)
                }
                #if os(iOS)
                Button { startExport() } label: {
                    Text(L10n.exportButton).font(.headline).frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canExport)
                .accessibilityIdentifier("export-start")
                #else
                HStack {
                    Spacer()
                    Button(L10n.cancel, role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button(L10n.exportButton) { startExport() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canExport)
                        .accessibilityIdentifier("export-start")
                }
                #endif
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
            // Also where a cancelled save dialog lands: the files are kept,
            // so Save and Share still work without exporting again.
            // Two rows so long French/Spanish labels fit on a phone.
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.exportReady(ByteCountFormatter.string(fromByteCount: output.totalByteCount, countStyle: .file)))
                    .font(.callout)
                HStack {
                    Spacer()
                    if destination == .share {
                        ShareLink(items: output.files) {
                            Label(L10n.exportShare, systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("export-share")
                        Button(L10n.exportSave) { isShowingSaver = true }
                    } else {
                        ShareLink(items: output.files) {
                            Label(L10n.exportShare, systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("export-share")
                        Button(L10n.exportSave) { isShowingSaver = true }
                            .keyboardShortcut(.defaultAction)
                    }
                    Button(L10n.done) { dismiss() }
                }
            }
        case .copied:
            HStack {
                Label(L10n.exportCopied, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("export-copied")
                Spacer()
                Button(L10n.done) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        case .failed(let message):
            HStack {
                Text(message).foregroundStyle(.red)
                Spacer()
                Button(L10n.done) { dismiss() }
            }
        }
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
    /// usefully hold.
    private var producesArchive: Bool {
        options.format != .pdf && selectedPages.count > 1 && options.packaging == .zip
    }

    private var effectiveDestination: Destination {
        destination == .copy && producesArchive ? .save : destination
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

    private func startExport() {
        guard let exporter = session.environment?.exporter else { return }
        let selection = selectedPages
        let options = options
        let name = itemName
        let target = effectiveDestination
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
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Theme.accent : Theme.separator, lineWidth: isSelected ? 2 : 1)
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

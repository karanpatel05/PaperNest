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
    @State private var phase: Phase = .configuring
    @State private var exportTask: Task<Void, Never>?
    @State private var isShowingSaver = false

    enum PageChoice: Hashable { case all, current, range }

    enum Phase {
        case configuring
        case exporting(ExportProgress)
        case ready(ExportOutput)
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.exportTitle)
                .font(.headline)
                .padding([.horizontal, .top])
            Form {
                optionsSection
            }
            .formStyle(.grouped)
            .disabled(isBusyOrReady)
            footer
                .padding()
        }
        #if os(macOS)
        // Sheets on macOS size to their content; on iOS they take the
        // screen width, which can be narrower than this.
        .frame(minWidth: 440, idealWidth: 480, minHeight: 420)
        #endif
        .onAppear { rangeEnd = pages.count }
        .onDisappear {
            exportTask?.cancel()
            if case .ready(let output) = phase { output.removeTemporaryFiles() }
        }
        .modifier(SaveExportedFiles(isPresented: $isShowingSaver, output: readyOutput, format: options.format) {
            dismiss()
        })
    }

    @ViewBuilder
    private var optionsSection: some View {
        Section {
            Picker(L10n.exportFormat, selection: $options.format) {
                Text(verbatim: "PDF").tag(ExportFormat.pdf)
                Text(verbatim: "JPEG").tag(ExportFormat.jpeg)
                Text(verbatim: "PNG").tag(ExportFormat.png)
            }
            .pickerStyle(.segmented)

            Picker(L10n.exportPages, selection: $pageChoice) {
                Text(L10n.exportAllPages).tag(PageChoice.all)
                if currentPageID != nil { Text(L10n.exportCurrentPage).tag(PageChoice.current) }
                Text(L10n.exportRange).tag(PageChoice.range)
            }
            .choicePickerStyle()
            if pageChoice == .range {
                Stepper(value: $rangeStart, in: 1...max(pages.count, 1)) {
                    LabeledContent(L10n.exportFrom, value: rangeStart.formatted())
                }
                Stepper(value: $rangeEnd, in: 1...max(pages.count, 1)) {
                    LabeledContent(L10n.exportTo, value: rangeEnd.formatted())
                }
            }
        }

        if options.format == .pdf {
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
            HStack {
                if !rangeIsValid {
                    Text(L10n.exportInvalidRange).font(.caption).foregroundStyle(.red)
                }
                Spacer()
                Button(L10n.cancel, role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.exportButton) { startExport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!rangeIsValid)
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
            // Two rows so long French/Spanish labels fit on a phone.
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.exportReady(ByteCountFormatter.string(fromByteCount: output.totalByteCount, countStyle: .file)))
                    .font(.callout)
                HStack {
                    Spacer()
                    ShareLink(items: output.files) {
                        Label(L10n.exportShare, systemImage: "square.and.arrow.up")
                    }
                    Button(L10n.exportSave) { isShowingSaver = true }
                        .keyboardShortcut(.defaultAction)
                    Button(L10n.done) { dismiss() }
                }
            }
        case .failed(let message):
            HStack {
                Text(message).foregroundStyle(.red)
                Spacer()
                Button(L10n.done) { dismiss() }
            }
        }
    }

    private var isBusyOrReady: Bool {
        if case .configuring = phase { return false }
        return true
    }

    private var readyOutput: ExportOutput? {
        if case .ready(let output) = phase { return output }
        return nil
    }

    private var rangeIsValid: Bool {
        pageChoice != .range || (1...pages.count).contains(rangeStart) && (rangeStart...pages.count).contains(rangeEnd)
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
        phase = .exporting(ExportProgress(completedPages: 0, totalPages: selection.count))
        exportTask = Task {
            do {
                let output = try await exporter.export(itemName: name, pages: selection, options: options) { progress in
                    Task { @MainActor in
                        if case .exporting = phase { phase = .exporting(progress) }
                    }
                }
                if Task.isCancelled {
                    output.removeTemporaryFiles()
                } else {
                    phase = .ready(output)
                }
            } catch is CancellationError {
                phase = .configuring
            } catch {
                phase = .failed(L10n.exportFailed)
            }
        }
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
    static let writableContentTypes: [UTType] = [.pdf, .jpeg, .png, .zip]
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

import Foundation
import Observation
import PaperNestCore
import PaperNestExport
import PaperNestStore
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
import PDFKit
#endif

/// The document as the print panel receives it: one PDF, made the way an
/// export is made, in a private temporary folder.
struct PrintJob: Sendable {
    /// The document's name: what the print queue calls the job.
    let name: String
    let file: URL
    let pageCount: Int
    fileprivate let output: ExportOutput
}

/// Printing the open document.
///
/// PaperNest draws its own pages, so there is no view to hand the system.
/// Print makes the same PDF Export makes — ink, typed text and placed
/// pictures on it, private comments left off — and gives that to the system's
/// print panel, which owns everything from there: the printer, the copies,
/// the paper, the preview. Nothing is stored and the library is not touched.
@MainActor @Observable
final class DocumentPrinter {
    enum Phase: Equatable {
        case idle
        /// The PDF is being made. Long documents take a moment.
        case preparing
        /// The system's print panel is up.
        case presenting
    }

    /// Shows the print panel and returns once it has been dismissed, whether
    /// by printing or by cancelling. Throws when no panel could be shown.
    typealias Panel = @MainActor (PrintJob) async throws -> Void

    /// The PaperNest mark this print carries, or nil. A free user's printout
    /// carries it like their exports do — the print panel can save a PDF, so
    /// an unmarked print would be an export without it.
    typealias FreeMark = @MainActor () async -> Watermark?

    /// The store's answer, once entitlements have loaded, so a paying user
    /// who prints soon after launch is not marked.
    static let entitlementFreeMark: FreeMark = {
        if !SubscriptionStore.shared.hasLoaded { await SubscriptionStore.shared.refresh() }
        return Watermark.freeExportMark
    }

    private(set) var phase: Phase = .idle
    /// Set when the document could not be made ready or the panel refused it.
    var isShowingFailure = false
    /// What to say about it. Different when the PDF's author is the reason.
    private(set) var failureMessage = L10n.printFailed

    private let panel: Panel
    private let freeMark: FreeMark
    private let temporaryRoot: URL?
    private var task: Task<Void, Never>?

    /// The plain document at the size of its own pages; the print panel fits
    /// it to the paper. No invisible text layer — paper cannot be searched —
    /// which also keeps Print clear of everything Export keeps for Pro.
    nonisolated static let options = ExportOptions(format: .pdf, paperSize: .original, pdfImageQuality: .balanced,
                                                   includesRecognizedText: false)

    /// The same, with the PaperNest mark a free user's print carries.
    nonisolated static func options(attribution: Watermark?) -> ExportOptions {
        var configured = options
        configured.attribution = attribution
        return configured
    }

    init(panel: @escaping Panel = DocumentPrinter.systemPanel, temporaryRoot: URL? = nil,
         freeMark: @escaping FreeMark = DocumentPrinter.entitlementFreeMark) {
        self.panel = panel
        self.freeMark = freeMark
        self.temporaryRoot = temporaryRoot
    }

    /// Makes the document ready and shows the print panel. Returns nil, and
    /// does nothing, while an earlier print is still under way.
    @discardableResult
    func print(_ itemID: ItemID, in environment: AppEnvironment?) -> Task<Void, Never>? {
        guard phase == .idle, let environment else { return nil }
        phase = .preparing
        let exporter = temporaryRoot.map { Exporter(renderer: environment.renderer, temporaryRoot: $0) }
            ?? environment.exporter
        let panel = panel
        let freeMark = freeMark
        let task = Task {
            defer {
                phase = .idle
                self.task = nil
            }
            do {
                let mark = await freeMark()
                // Cancelled while entitlements loaded: nothing is made.
                try Task.checkCancellation()
                guard let job = try await Self.prepare(itemID, store: environment.store, exporter: exporter,
                                                       attribution: mark)
                else { return }
                defer { job.output.removeTemporaryFiles() }
                try Task.checkCancellation()
                phase = .presenting
                try await panel(job)
            } catch is CancellationError {
                // Stopped by the reader. Not a failure, and nothing to say.
            } catch ExportError.printingNotAllowed {
                // Nothing went wrong: the PDF's author switched printing off.
                failureMessage = L10n.restrictedPrintRefused
                isShowingFailure = true
            } catch {
                failureMessage = L10n.printFailed
                isShowingFailure = true
            }
        }
        self.task = task
        return task
    }

    /// Stops making the document ready. Has no effect once the panel is up:
    /// from there the panel's own Cancel is the way out.
    func cancel() {
        guard phase == .preparing else { return }
        task?.cancel()
    }

    /// Reads the document as it is saved now and writes the PDF to print.
    /// Nil when it has no pages: there is nothing to print and nothing wrong.
    nonisolated static func prepare(_ itemID: ItemID, store: LibraryStore, exporter: Exporter,
                                    attribution: Watermark? = nil) async throws -> PrintJob? {
        guard let item = try await store.item(itemID) else { throw ExportError.noPages }
        let pages = try await store.pages(of: itemID)
        guard !pages.isEmpty else { return nil }
        let output = try await exporter.export(itemName: item.name, pages: pages,
                                               options: options(attribution: attribution), purpose: .printing)
        guard let file = output.files.first else {
            output.removeTemporaryFiles()
            throw ExportError.writeFailed
        }
        return PrintJob(name: item.name, file: file, pageCount: pages.count, output: output)
    }
}

// MARK: - The system's print panel

enum PrintPanelError: Error {
    /// This device cannot print, or the panel would not take the file.
    case unavailable
}

extension DocumentPrinter {
    #if os(iOS)
    static func systemPanel(_ job: PrintJob) async throws {
        // Mapped rather than passed by URL: the bytes stay readable for as
        // long as the print system holds them, even after the temporary file
        // is removed, and a long document is not copied into memory.
        guard UIPrintInteractionController.isPrintingAvailable,
              let data = try? Data(contentsOf: job.file, options: .alwaysMapped),
              UIPrintInteractionController.canPrint(data) else { throw PrintPanelError.unavailable }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = job.name
        info.outputType = .general
        controller.printInfo = info
        controller.printingItem = data
        let shown: Bool = await withCheckedContinuation { continuation in
            // The completion handler is not promised when presenting fails,
            // so the continuation is resumed from whichever comes first.
            let once = ResumeOnce(continuation)
            let presented = controller.present(animated: true) { _, _, _ in once.resume(returning: true) }
            if !presented { once.resume(returning: false) }
        }
        controller.printingItem = nil
        if !shown { throw PrintPanelError.unavailable }
    }
    #elseif os(macOS)
    static func systemPanel(_ job: PrintJob) async throws {
        guard let document = PDFDocument(url: job.file),
              let info = NSPrintInfo.shared.copy() as? NSPrintInfo,
              let operation = document.printOperation(for: info, scalingMode: .pageScaleDownToFit, autoRotate: true)
        else { throw PrintPanelError.unavailable }
        operation.jobTitle = job.name
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            await PrintOperationRun().run(operation, in: window)
        } else {
            operation.run()
        }
    }
    #endif
}

#if os(iOS)
/// Resumes a continuation the first time it is asked to, and only then.
@MainActor private final class ResumeOnce {
    private var continuation: CheckedContinuation<Bool, Never>?
    init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }

    func resume(returning value: Bool) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
#endif

#if os(macOS)
/// Waits for a print operation run as a sheet on the document's window.
@MainActor private final class PrintOperationRun: NSObject {
    private var continuation: CheckedContinuation<Void, Never>?
    /// AppKit does not retain the delegate of a print operation.
    private var keepAlive: PrintOperationRun?

    func run(_ operation: NSPrintOperation, in window: NSWindow) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            keepAlive = self
            operation.runModal(for: window, delegate: self,
                               didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
        }
    }

    @objc private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool,
                                            contextInfo: UnsafeMutableRawPointer?) {
        continuation?.resume()
        continuation = nil
        keepAlive = nil
    }
}
#endif

// MARK: - Reaching the printer from the menu bar

/// The focused document's printer, for File > Print… and ⌘P. Its own focused
/// value rather than a field on `DocumentCommandContext`: the printer is the
/// one object both the title menu and the menu bar must share, so a second
/// ⌘P while the first is still being made ready finds it busy.
struct DocumentPrinterKey: FocusedValueKey {
    typealias Value = DocumentPrinter
}

extension FocusedValues {
    var documentPrinter: DocumentPrinter? {
        get { self[DocumentPrinterKey.self] }
        set { self[DocumentPrinterKey.self] = newValue }
    }
}

// MARK: - What the editor shows while printing

extension View {
    /// The "getting ready" card while a document is made ready to print, and
    /// the message when it could not be.
    func documentPrinting(_ printer: DocumentPrinter) -> some View {
        modifier(DocumentPrintPresentation(printer: printer))
    }
}

private struct DocumentPrintPresentation: ViewModifier {
    @Bindable var printer: DocumentPrinter

    func body(content: Content) -> some View {
        content
            .overlay {
                if printer.phase == .preparing {
                    PrintPreparingCard { printer.cancel() }
                }
            }
            .alert(L10n.genericErrorTitle, isPresented: $printer.isShowingFailure) {
                Button(L10n.ok, role: .cancel) {}
            } message: {
                Text(printer.failureMessage)
            }
    }
}

/// Shown only once making the PDF has taken long enough to notice, so a
/// short document goes straight to the print panel without a flash.
private struct PrintPreparingCard: View {
    let cancel: () -> Void
    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(L10n.printPreparing)
                .font(.subheadline)
                .multilineTextAlignment(.center)
            Button(L10n.cancel, role: .cancel, action: cancel)
                .accessibilityIdentifier("print-preparing-cancel")
        }
        .padding(22)
        .frame(maxWidth: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 18, y: 6)
        .opacity(isVisible ? 1 : 0)
        .accessibilityHidden(!isVisible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("print-preparing")
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.15)) { isVisible = true }
        }
    }
}

#if os(iOS)
import PaperNestImport
import PDFKit
import UIKit
import UniformTypeIdentifiers
import WebKit

/// Word and Excel files laid out as PDF pages on iPhone and iPad, so they open
/// in the editor to be marked up (owner, 2026-11-15: "Yes, build both").
///
/// iOS has no Office reader the importer could use, but WebKit can show these
/// files, so one is loaded into a web view that is never seen and paginated
/// with the print system. The layout is close, not exact: a spreadsheet's long
/// cells are clipped at their column edge, as they are on screen. The Mac reads
/// Word in the importer instead (`TextDocumentConverter`).
///
/// Anything that does not come out as at least one page with words on it — a
/// file WebKit cannot read, one that never finishes loading — gives nil, and
/// the caller keeps the file as a file.
@MainActor
enum OfficeDocumentRenderer {
    /// `.docx`, `.doc` and `.xlsx`: the formats a real file was seen to come
    /// out of WebKit as pages with their words. `.xls`, PowerPoint and the
    /// iWork formats were not tried, so they stay files.
    static let types: [UTType] = [
        "org.openxmlformats.wordprocessingml.document",
        "com.microsoft.word.doc",
        "org.openxmlformats.spreadsheetml.sheet",
    ].compactMap { UTType($0) }

    static func handles(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return types.contains { type.conforms(to: $0) }
    }

    /// PDF data for the file, or nil to keep it a file.
    static func pdf(for url: URL, timeout: Duration = .seconds(20)) async -> Data? {
        guard handles(url) else { return nil }
        // WebKit reads files in a process of its own, which a security-scoped
        // file from the picker is not open to. A private copy is.
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("OfficeRender-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: copy)
            return await PageMaker(file: copy, folder: folder).pdf(timeout: timeout)
        } catch {
            return nil
        }
    }
}

/// Loads one file into a hidden web view and prints it to PDF pages.
@MainActor
private final class PageMaker: NSObject, WKNavigationDelegate {
    private let file: URL
    private let folder: URL
    private let web = WKWebView(frame: CGRect(origin: .zero, size: TextToPDF.a4))
    private var loaded: CheckedContinuation<Bool, Never>?

    init(file: URL, folder: URL) {
        self.file = file
        self.folder = folder
    }

    func pdf(timeout: Duration) async -> Data? {
        // A web view lays out only inside a window. It sits behind everything
        // else in it, so it is never seen.
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return nil }
        web.isUserInteractionEnabled = false
        window.insertSubview(web, at: 0)
        defer {
            web.stopLoading()
            web.navigationDelegate = nil
            web.removeFromSuperview()
        }
        web.navigationDelegate = self
        let didLoad = await withCheckedContinuation { continuation in
            loaded = continuation
            web.loadFileURL(file, allowingReadAccessTo: folder)
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.finishLoading(false)
            }
        }
        guard didLoad else { return nil }

        // Loading is done before the content has settled: wait until two
        // readings of the page count agree, for a few seconds at most.
        var previous = -1
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(250))
            let count = renderer().numberOfPages
            if count > 0, count == previous { break }
            previous = count
        }
        return printed()
    }

    private func renderer() -> UIPrintPageRenderer {
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(web.viewPrintFormatter(), startingAtPageAt: 0)
        let paper = CGRect(origin: .zero, size: TextToPDF.a4)
        renderer.setValue(paper, forKey: "paperRect")
        renderer.setValue(paper.insetBy(dx: 36, dy: 36), forKey: "printableRect")
        return renderer
    }

    /// The pages, kept only if at least one carries words: an error page or a
    /// blank render is not the document.
    private func printed() -> Data? {
        let renderer = renderer()
        guard renderer.numberOfPages > 0 else { return nil }
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, CGRect(origin: .zero, size: TextToPDF.a4), nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for index in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: index, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        guard let document = PDFDocument(data: data as Data), document.pageCount > 0,
              !(document.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return data as Data
    }

    /// Called once whichever of loaded, failed or timed out comes first.
    private func finishLoading(_ success: Bool) {
        guard let continuation = loaded else { return }
        loaded = nil
        continuation.resume(returning: success)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoading(true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishLoading(false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishLoading(false)
    }
}
#endif

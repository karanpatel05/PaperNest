import Foundation
import PaperNestCore
import PaperNestStore
import SwiftUI

#if os(iOS)
import QuickLook
import UIKit
#else
import AppKit
import QuickLookUI
#endif

struct FilePreviewRequest: Identifiable {
    let id = UUID()
    let summary: LibraryStore.ItemSummary
}

/// Both library tiles and Recent use the same presentation and dismissal path.
struct FilePreviewPresentation: ViewModifier {
    @Binding var request: FilePreviewRequest?

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(item: $request) { FilePreviewSheet(request: $0) }
        #else
        content.sheet(item: $request) { FilePreviewSheet(request: $0) }
        #endif
    }
}

#if os(iOS)
private struct QuickLookPreview: UIViewControllerRepresentable {
    let copy: PreparedFileCopy
    let title: String

    func makeCoordinator() -> Coordinator { Coordinator(copy: copy, title: title) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        // No editing delegate: the system preview stays read-only.
        return preview
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewItem {
        // Keep the copy alive until the native controller also releases it.
        let copy: PreparedFileCopy
        let title: String

        init(copy: PreparedFileCopy, title: String) {
            self.copy = copy
            self.title = title
        }

        nonisolated var previewItemURL: URL? { copy.url }
        nonisolated var previewItemTitle: String? { title }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { self }
    }
}
#else
private struct QuickLookPreview: NSViewRepresentable {
    let copy: PreparedFileCopy
    let title: String

    func makeCoordinator() -> Coordinator { Coordinator(copy: copy, title: title) }

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.shouldCloseWithWindow = false
        view.previewItem = context.coordinator
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {}

    static func dismantleNSView(_ view: QLPreviewView, coordinator: Coordinator) {
        view.close()
    }

    final class Coordinator: NSObject, QLPreviewItem {
        let copy: PreparedFileCopy
        let title: String

        init(copy: PreparedFileCopy, title: String) {
            self.copy = copy
            self.title = title
        }

        var previewItemURL: URL? { copy.url }
        var previewItemTitle: String? { title }
    }
}
#endif

struct FilePreviewSheet: View {
    let request: FilePreviewRequest
    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var preparedCopy: PreparedFileCopy?
    @State private var failed = false
    @State private var showingDetails = false

    var body: some View {
        NavigationStack {
            Group {
                if let preparedCopy {
                    QuickLookPreview(copy: preparedCopy, title: request.summary.item.name)
                        .accessibilityIdentifier("file-preview")
                } else if failed {
                    ContentUnavailableView(L10n.filePreviewFailed, systemImage: "doc.questionmark",
                                           description: Text(L10n.filePreviewFailedDescription))
                        .accessibilityIdentifier("file-preview-error")
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(request.summary.item.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { showingDetails = true } label: {
                        Label(L10n.fileShowDetails, systemImage: "info.circle")
                    }
                    .accessibilityIdentifier("file-preview-info")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.done) { dismiss() }
                        .accessibilityIdentifier("file-preview-done")
                }
            }
            .sheet(isPresented: $showingDetails) {
                FileDetailsSheet(request: FileDetailsRequest(summary: request.summary), existingCopy: preparedCopy)
            }
            .task {
                guard preparedCopy == nil else { return }
                guard let payload = request.summary.file, let store = session.environment?.store else {
                    failed = true
                    return
                }
                do {
                    preparedCopy = try await FileKind.prepareTemporaryCopy(of: payload, in: store)
                } catch is CancellationError {
                    // The owner can close the preview while a large file is copying.
                } catch { failed = true }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 640, minHeight: 420, idealHeight: 560)
        #endif
    }
}

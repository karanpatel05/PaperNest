import CoreGraphics
import PaperNestCore
import PaperNestRender
import SwiftUI

enum Theme {
    /// Brand accent: a deep ink teal, used sparingly for selection and tint.
    static let accent = Color(red: 0.10, green: 0.42, blue: 0.46)
    static let paperShadow = Color.black.opacity(0.16)
}

/// Shows a rendered page, keeping the page's aspect ratio while it loads so
/// layouts don't jump. Errors are shown in place rather than as a blank page.
struct PageImageView: View {
    let page: Page
    /// Target size of the longer edge, in pixels.
    let pixelSize: CGFloat
    var accessibilityLabel: String?

    @Environment(LibrarySession.self) private var session
    @State private var image: CGImage?
    @State private var failure: String?

    private var pageSize: CGSize { page.geometry.pageSize }

    private var loadKey: ThumbnailCache.Key {
        ThumbnailCache.Key(page: page.id, revision: page.revision, pixelSize: ThumbnailCache.bucket(pixelSize))
    }

    var body: some View {
        ZStack {
            Rectangle().fill(Color.white)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else if let failure {
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                    Text(failure)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .padding(8)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .aspectRatio(pageSize.width / max(pageSize.height, 1), contentMode: .fit)
        .shadow(color: Theme.paperShadow, radius: 2, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel ?? "")
        .accessibilityAddTraits(.isImage)
        .task(id: loadKey) { await load() }
    }

    private func load() async {
        if let cached = session.thumbnails.cached(page, pixelSize: pixelSize) {
            image = cached
            failure = nil
            return
        }
        guard let renderer = session.environment?.renderer else { return }
        do {
            let rendered = try await session.thumbnails.image(for: page, pixelSize: pixelSize, renderer: renderer)
            image = rendered
            failure = nil
        } catch is CancellationError {
            return
        } catch RenderError.sourceUnavailable {
            failure = L10n.pageUnavailable
        } catch {
            failure = L10n.pageLoadFailed
        }
    }
}

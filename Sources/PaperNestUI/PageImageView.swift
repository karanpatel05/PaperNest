import CoreGraphics
import PaperNestCore
import PaperNestRender
import SwiftUI

/// Shows a rendered page, keeping the page's aspect ratio while it loads so
/// layouts don't jump. Errors are shown in place rather than as a blank page.
struct PageImageView: View {
    let page: Page
    /// Target size of the longer edge, in pixels.
    let pixelSize: CGFloat
    var accessibilityLabel: String?
    /// False under the ink canvas, which draws the ink itself.
    var includesInk = true
    var excludingObjectIDs: Set<PageObjectID> = []
    /// Night mode: the picture in its night colours. Only the reader's own
    /// page asks for it, and wraps this view in `nightFilter` when it does;
    /// see `NightMode` for why the picture goes through that filter here too.
    var isNight = false

    @Environment(LibrarySession.self) private var session
    @State private var image: CGImage?
    @State private var failure: String?
    /// The night picture, and the day picture it was made from.
    @State private var night: (source: CGImage, image: CGImage)?

    /// What to draw: the page by day, its night picture by night. While a
    /// new night picture is being made the last one stays up — it is this
    /// same page a moment ago — and only a page never yet shown at night
    /// waits as dark paper.
    private var shown: CGImage? {
        guard isNight, let image else { return image }
        if let night, night.source === image { return night.image }
        return NightPalette.cached(image) ?? night?.image
    }

    private struct NightRequest: Hashable {
        let image: ObjectIdentifier?
        let isNight: Bool
    }

    private var pageSize: CGSize { page.geometry.pageSize }

    private var loadKey: ThumbnailCache.Key {
        ThumbnailCache.Key(page, pixelSize: pixelSize, includesInk: includesInk, excludingObjectIDs: excludingObjectIDs)
    }

    var body: some View {
        ZStack {
            Rectangle().fill(isNight ? Color.black : Color.white)
            if let image = shown {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else if let failure {
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.app(.title2))
                    Text(failure)
                        .font(.app(.caption))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(isNight ? AnyShapeStyle(Color.white.opacity(0.7)) : AnyShapeStyle(.secondary))
                .padding(8)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .nightFilter(isNight)
        .aspectRatio(pageSize.width / max(pageSize.height, 1), contentMode: .fit)
        .shadow(color: isNight ? .clear : Theme.paperShadow, radius: 2, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel ?? "")
        .accessibilityAddTraits(.isImage)
        .task(id: loadKey) { await load() }
        .task(id: NightRequest(image: image.map(ObjectIdentifier.init), isNight: isNight)) {
            guard isNight, let image else { return }
            // Off the main actor: a page at full zoom is millions of pixels.
            let recoloured = await Task.detached(priority: .userInitiated) { NightPalette.image(image) }.value
            guard !Task.isCancelled, let recoloured else { return }
            night = (image, recoloured)
        }
    }

    private func load() async {
        let requestKey = loadKey
        if let cached = session.thumbnails.cached(page, pixelSize: pixelSize, includesInk: includesInk, excludingObjectIDs: excludingObjectIDs) {
            image = cached
            failure = nil
            return
        }
        guard let renderer = session.environment?.renderer else { return }
        do {
            let rendered = try await session.thumbnails.image(for: page, pixelSize: pixelSize, includesInk: includesInk, excludingObjectIDs: excludingObjectIDs, renderer: renderer)
            try Task.checkCancellation()
            guard requestKey == loadKey else { return }
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

#if os(iOS)
import SwiftUI

struct ScannerThumbnail: View {
    let page: ScannerPage
    /// The scan's pages, in order, so the corner mark can say this one
    /// repeats an earlier one. Required: measuring a page also forgets every
    /// page not in this list.
    let pages: [ScannerPage]
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { ProgressView() }
        }
        .overlay(alignment: .topLeading) { ScanQualityBadge(page: page, pages: pages) }
        .task(id: page.drawKey) {
            let draft = page
            let data = await Task.detached(priority: .utility) {
                draft.rendered(maxDimension: 160)?.jpegData(compressionQuality: 0.7)
            }.value
            guard !Task.isCancelled else { return }
            image = data.flatMap { UIImage(data: $0) }
        }
    }
}
#endif

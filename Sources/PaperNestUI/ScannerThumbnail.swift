#if os(iOS)
import SwiftUI

struct ScannerThumbnail: View {
    let page: ScannerPage
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { ProgressView() }
        }
        .task(id: "\(page.id)-\(page.quarterTurns)-\(page.filter)-\(page.enhanced)-\(page.corners)") {
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

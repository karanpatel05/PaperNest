#if os(iOS)
import SwiftUI

/// Review-only viewing transform. Crop replaces this view entirely, so its
/// handles always operate in unzoomed source-image coordinates.
struct ScannerZoomPreview: View {
    let image: UIImage
    let accessibilityValue: String
    @State private var scale: CGFloat = 1
    @State private var scaleStart: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var offsetStart: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let fit = min(geometry.size.width / image.size.width, geometry.size.height / image.size.height)
            let imageSize = CGSize(width: image.size.width * fit, height: image.size.height * fit)
            ZStack(alignment: .topTrailing) {
                Image(uiImage: image).resizable()
                    .frame(width: imageSize.width, height: imageSize.height)
                    .scaleEffect(scale).offset(offset)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .contentShape(Rectangle()).clipped()
                    .gesture(MagnifyGesture()
                        .onChanged { value in
                            scale = min(4, max(1, scaleStart * value.magnification))
                            offset = bounded(offset, image: imageSize, viewport: geometry.size)
                        }
                        .onEnded { _ in scaleStart = scale; offsetStart = offset })
                    .simultaneousGesture(DragGesture()
                        .onChanged { value in
                            guard scale > 1 else { return }
                            offset = bounded(CGSize(width: offsetStart.width + value.translation.width,
                                                    height: offsetStart.height + value.translation.height), image: imageSize, viewport: geometry.size)
                        }
                        .onEnded { _ in offsetStart = offset })
                    .accessibilityLabel(L10n.scannerReview)
                    .accessibilityValue(accessibilityValue + "; \(Int(scale * 100))%; \(Int(offset.width)), \(Int(offset.height))")
                    .accessibilityIdentifier("scanner.preview")
                HStack(spacing: 4) {
                    zoomButton("minus.magnifyingglass", label: L10n.zoomOut, identifier: "scanner.zoom.out") {
                        changeZoom(max(1, scale / 1.5), image: imageSize, viewport: geometry.size)
                    }.disabled(scale <= 1)
                    zoomButton("arrow.up.left.and.arrow.down.right", label: L10n.zoomToFit, identifier: "scanner.zoom.fit") {
                        changeZoom(1, image: imageSize, viewport: geometry.size)
                    }.accessibilityValue("\(Int(scale * 100))%")
                    zoomButton("plus.magnifyingglass", label: L10n.zoomIn, identifier: "scanner.zoom.in") {
                        changeZoom(min(4, scale * 1.5), image: imageSize, viewport: geometry.size)
                    }.disabled(scale >= 4)
                }.padding(4).background(.regularMaterial, in: Capsule()).padding(8)
            }
            .onChange(of: geometry.size) { _, _ in reset() }
        }.padding(.horizontal, 20)
    }

    private func zoomButton(_ symbol: String, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 44, height: 44) }
            .accessibilityLabel(label).accessibilityIdentifier(identifier)
    }

    private func bounded(_ value: CGSize, image: CGSize, viewport: CGSize) -> CGSize {
        let x = max(0, (image.width * scale - viewport.width) / 2)
        let y = max(0, (image.height * scale - viewport.height) / 2)
        return CGSize(width: min(x, max(-x, value.width)), height: min(y, max(-y, value.height)))
    }

    private func changeZoom(_ value: CGFloat, image: CGSize, viewport: CGSize) {
        scale = value
        scaleStart = value
        offset = bounded(offset, image: image, viewport: viewport)
        offsetStart = offset
    }

    private func reset() {
        scale = 1; scaleStart = 1; offset = .zero; offsetStart = .zero
    }
}
#endif

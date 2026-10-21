import PaperNestCore
import SwiftUI

/// Rectangular crop over the page as the user sees it: rotated, with any
/// existing crop removed so it can be widened again. The result is stored in
/// source space through `PageGeometry`, so it stays correct after later
/// rotation and is applied identically on export. The original is untouched.
struct CropEditor: View {
    let page: Page
    let onApply: (NormalizedRect) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    /// The crop in uncropped-page points.
    @State private var rect: CGRect
    @State private var drag: (handle: CropHandle, start: CGRect)?

    /// Touch slop around edges and corners, in on-screen points.
    private static let grabTolerance: CGFloat = 22

    init(page: Page, onApply: @escaping (NormalizedRect) -> Void) {
        self.page = page
        self.onApply = onApply
        _rect = State(initialValue: page.geometry.cropRectInUncroppedPage)
    }

    private var pageSize: CGSize { page.geometry.uncropped.pageSize }
    private var bounds: CGRect { CGRect(origin: .zero, size: pageSize) }

    private var preview: Page {
        var copy = page
        copy.transform.crop = .full
        return copy
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    let scale = min(proxy.size.width / pageSize.width, proxy.size.height / pageSize.height)
                    let shown = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
                    ZStack(alignment: .topLeading) {
                        PageImageView(page: preview, pixelSize: max(shown.width, shown.height) * displayScale)
                        CropOverlay(cropRect: rect.scaled(by: scale), size: shown)
                    }
                    .frame(width: shown.width, height: shown.height)
                    .contentShape(Rectangle())
                    .gesture(dragGesture(scale: scale))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.cropArea)
                    .accessibilityValue(keptDescription)
                    .accessibilityHint(L10n.cropHint)
                    .accessibilityAction(named: L10n.cropReset) { rect = bounds }
                    .accessibilityIdentifier("crop-area")
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
                .padding(24)
                .background(Color(white: 0.12))

                HStack {
                    Button(L10n.cropReset) { rect = bounds }
                        .disabled(rect == bounds)
                    Spacer()
                }
                .padding()
            }
            .navigationTitle(L10n.crop)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.done) {
                        onApply(page.geometry.crop(fromUncroppedPageRect: rect))
                        dismiss()
                    }
                    .accessibilityIdentifier("crop-done")
                }
            }
        }
        // A drag near the sheet's edge must crop, not dismiss.
        .interactiveDismissDisabled()
        #if os(iOS)
        // The editor canvas is dark; with light bars the title was black
        // on near-black. Dark appearance applies to this sheet only.
        .preferredColorScheme(.dark)
        #endif
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 620, idealHeight: 760)
        #endif
    }

    /// "70% wide by 75% tall": how much of the page the crop keeps, for
    /// VoiceOver (and UI tests).
    private var keptDescription: String {
        let format = FloatingPointFormatStyle<Double>.Percent().precision(.fractionLength(0))
        return L10n.cropKept(width: (rect.width / pageSize.width).formatted(format),
                             height: (rect.height / pageSize.height).formatted(format))
    }

    private func dragGesture(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if drag == nil {
                    let start = CGPoint(x: value.startLocation.x / scale, y: value.startLocation.y / scale)
                    guard let handle = CropFrame.handle(at: start, in: rect, tolerance: Self.grabTolerance / scale) else { return }
                    drag = (handle, rect)
                }
                guard let drag else { return }
                rect = CropFrame.adjust(
                    drag.start,
                    with: drag.handle,
                    by: CGSize(width: value.translation.width / scale, height: value.translation.height / scale),
                    within: bounds,
                    minSize: CropFrame.minimumSize(for: pageSize)
                )
            }
            .onEnded { _ in drag = nil }
    }
}

/// Dims what will be cropped away and draws the frame, thirds guide and
/// corner handles. Purely visual; the editor handles input.
private struct CropOverlay: View {
    let cropRect: CGRect
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(cropRect)
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))

            // Every line is drawn twice, dark under light, so the frame and
            // handles stay visible over white paper and dark photos alike.
            thirdsGuide.stroke(Color.black.opacity(0.35), lineWidth: 1.5)
            thirdsGuide.stroke(Color.white.opacity(0.8), lineWidth: 0.5)

            Path { $0.addRect(cropRect) }
                .stroke(Color.black.opacity(0.5), lineWidth: 3)
            Path { $0.addRect(cropRect) }
                .stroke(Color.white, lineWidth: 1.5)

            cornerHandles.stroke(Color.black.opacity(0.55), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            cornerHandles.stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }
}

private extension CropOverlay {
    var thirdsGuide: Path {
        Path { path in
            for i in 1...2 {
                let x = cropRect.minX + cropRect.width * CGFloat(i) / 3
                let y = cropRect.minY + cropRect.height * CGFloat(i) / 3
                path.move(to: CGPoint(x: x, y: cropRect.minY))
                path.addLine(to: CGPoint(x: x, y: cropRect.maxY))
                path.move(to: CGPoint(x: cropRect.minX, y: y))
                path.addLine(to: CGPoint(x: cropRect.maxX, y: y))
            }
        }
    }

    var cornerHandles: Path {
        Path { path in
            let arm = min(18, cropRect.width / 3, cropRect.height / 3)
            let corners: [(CGPoint, CGFloat, CGFloat)] = [
                (CGPoint(x: cropRect.minX, y: cropRect.minY), 1, 1),
                (CGPoint(x: cropRect.maxX, y: cropRect.minY), -1, 1),
                (CGPoint(x: cropRect.minX, y: cropRect.maxY), 1, -1),
                (CGPoint(x: cropRect.maxX, y: cropRect.maxY), -1, -1),
            ]
            for (corner, dx, dy) in corners {
                path.move(to: CGPoint(x: corner.x + arm * dx, y: corner.y))
                path.addLine(to: corner)
                path.addLine(to: CGPoint(x: corner.x, y: corner.y + arm * dy))
            }
        }
    }
}

private extension CGRect {
    func scaled(by factor: CGFloat) -> CGRect {
        CGRect(x: minX * factor, y: minY * factor, width: width * factor, height: height * factor)
    }
}

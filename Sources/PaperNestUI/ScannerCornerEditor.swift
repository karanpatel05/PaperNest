#if os(iOS)
import SwiftUI

/// Four source-space crop corners. Handles remain within their respective
/// quadrants, preventing inverted/self-intersecting perspective quadrilaterals.
struct ScannerCornerEditor: View {
    @Binding var page: ScannerPage
    var body: some View {
        GeometryReader { geometry in
            if let image = UIImage(data: page.original) {
                let scale = min(geometry.size.width / image.size.width, geometry.size.height / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                ZStack {
                    Image(uiImage: image).resizable().frame(width: size.width, height: size.height)
                    Path { path in
                        let points = page.corners.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
                        path.addLines(points)
                        path.closeSubpath()
                    }.stroke(Theme.accent, lineWidth: 3)
                    ForEach(0..<4) { index in
                        Circle().fill(.white).overlay(Circle().stroke(Theme.accent, lineWidth: 3))
                            .frame(width: 24, height: 24).frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .position(x: page.corners[index].x * size.width, y: page.corners[index].y * size.height)
                            .gesture(DragGesture(coordinateSpace: .named("scanner.crop")).onChanged { value in
                                let left = index == 0 || index == 3
                                let top = index < 2
                                page.corners[index] = CGPoint(
                                    x: min(left ? 0.49 : 1, max(left ? 0 : 0.51, value.location.x / size.width)),
                                    y: min(top ? 0.49 : 1, max(top ? 0 : 0.51, value.location.y / size.height)))
                            })
                            .accessibilityIdentifier("scanner.corner.\(index)")
                            .accessibilityAction(named: Text(L10n.inlineMoveLeft)) { move(index, dx: -0.025, dy: 0) }
                            .accessibilityAction(named: Text(L10n.inlineMoveRight)) { move(index, dx: 0.025, dy: 0) }
                            .accessibilityAction(named: Text(L10n.inlineMoveUp)) { move(index, dx: 0, dy: -0.025) }
                            .accessibilityAction(named: Text(L10n.inlineMoveDown)) { move(index, dx: 0, dy: 0.025) }
                            .accessibilityLabel(L10n.crop + " " + String(index + 1))
                            .accessibilityValue("\(Int(page.corners[index].x * 100)), \(Int(page.corners[index].y * 100))")
                    }
                }.frame(width: size.width, height: size.height).coordinateSpace(name: "scanner.crop")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.padding(24)
    }
    private func move(_ index: Int, dx: CGFloat, dy: CGFloat) {
        let left = index == 0 || index == 3
        let top = index < 2
        page.corners[index] = CGPoint(
            x: min(left ? 0.49 : 1, max(left ? 0 : 0.51, page.corners[index].x + dx)),
            y: min(top ? 0.49 : 1, max(top ? 0 : 0.51, page.corners[index].y + dy)))
    }
}
#endif

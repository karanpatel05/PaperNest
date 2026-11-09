import PaperNestCore
import PaperNestStore
import SwiftUI

/// A decorative binding around real notebook metadata. No sample pages or titles.
struct NotebookCover: View {
    let summary: LibraryStore.ItemSummary
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var tint: Color { summary.item.colorLabel?.tint ?? Theme.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                tint.opacity(0.13)
                Canvas { context, size in
                    for index in 0..<8 {
                        let offset = CGFloat(index) * 22
                        var path = Path()
                        path.move(to: CGPoint(x: -20, y: offset))
                        path.addCurve(to: CGPoint(x: size.width + 20, y: offset - 25),
                                      control1: CGPoint(x: size.width * 0.4, y: offset + 65),
                                      control2: CGPoint(x: size.width * 0.6, y: offset - 70))
                        context.stroke(path, with: .color(tint.opacity(0.13)), lineWidth: 9)
                    }
                }.accessibilityHidden(true)
            }.frame(height: dynamicTypeSize.isAccessibilitySize ? 100 : 112).clipped()
            VStack(alignment: .leading, spacing: 10) {
                Text(summary.item.name).font(.headline).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    Image(systemName: "doc")
                    Text(L10n.pageCount(summary.pageCount))
                    if summary.item.isFavorite { Image(systemName: "star.fill").foregroundStyle(Theme.accent) }
                }.font(.caption).foregroundStyle(.secondary)
            }.padding(.leading, 22).padding(.trailing, 12).padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 106, alignment: .topLeading)
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.25), lineWidth: 1) }
        .overlay(alignment: .leading) {
            VStack(spacing: 9) {
                ForEach(0..<12, id: \.self) { _ in
                    Capsule().fill(Theme.secondaryText.opacity(0.65)).frame(width: 13, height: 4)
                        .overlay(alignment: .trailing) { Circle().fill(Theme.surface).frame(width: 3, height: 3) }
                }
            }.offset(x: -4).accessibilityHidden(true)
        }
        .shadow(color: Theme.paperShadow.opacity(0.5), radius: 3, y: 2)
    }
}

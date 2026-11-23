import SwiftUI

/// PaperNest's one signature detail (owner, 2026-11-22): a document of
/// several pages shows the edges of one or two more sheets behind its first
/// page, so its size reads at a glance. Paper stays white in both
/// appearances, like the pages themselves.
struct PaperStack: ViewModifier {
    let pages: Int
    /// How far each sheet behind sits down and to the right.
    var step: CGFloat = 3

    private var sheets: Int { min(max(pages - 1, 0), 2) }

    func body(content: Content) -> some View {
        content
            .background(alignment: .topLeading) {
                GeometryReader { proxy in
                    ZStack(alignment: .topLeading) {
                        ForEach((1...max(sheets, 1)).reversed(), id: \.self) { index in
                            if index <= sheets {
                                Rectangle()
                                    .fill(Color.white)
                                    .overlay { Rectangle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5) }
                                    .shadow(color: Theme.paperShadow.opacity(0.4), radius: 1.5, y: 1)
                                    .frame(width: proxy.size.width, height: proxy.size.height)
                                    .offset(x: step * CGFloat(index), y: step * CGFloat(index))
                            }
                        }
                    }
                }
            }
            .padding(.trailing, step * CGFloat(sheets))
            .padding(.bottom, step * CGFloat(sheets))
    }
}

extension View {
    /// Sheets behind a first page, one per extra page, two at most.
    func paperStack(pages: Int, step: CGFloat = 3) -> some View {
        modifier(PaperStack(pages: pages, step: step))
    }
}

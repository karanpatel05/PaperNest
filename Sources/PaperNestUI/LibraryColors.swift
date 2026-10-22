import PaperNestCore
import SwiftUI

extension ItemColor {
    var title: String {
        switch self {
        case .red: L10n.colorRed
        case .orange: L10n.colorOrange
        case .yellow: L10n.colorYellow
        case .green: L10n.colorGreen
        case .blue: L10n.colorBlue
        case .purple: L10n.colorPurple
        case .gray: L10n.colorGray
        }
    }

    var tint: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .gray: .gray
        }
    }
}

struct ColorLabelMenu: View {
    var apply: (ItemColor?) -> Void

    var body: some View {
        Menu(L10n.colorLabel) {
            Button(L10n.noColorLabel) { apply(nil) }
            ForEach(ItemColor.allCases, id: \.self) { color in
                Button { apply(color) } label: {
                    Label { Text(color.title) } icon: {
                        Image(systemName: "circle.fill").foregroundStyle(color.tint)
                    }
                }
            }
        }
    }
}

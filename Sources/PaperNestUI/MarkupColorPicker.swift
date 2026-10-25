import PaperNestCore
import SwiftUI

/// Concrete sRGB swatches keep saved colors independent of light/dark mode.
struct MarkupColorPicker: View {
    @Binding var color: RGBAColor

    static var presets: [(id: String, name: String, color: RGBAColor)] {
        [("yellow", L10n.colorYellow, .init(red: 1, green: 0.82, blue: 0)),
         ("green", L10n.colorGreen, .init(red: 0, green: 0.65, blue: 0.25)),
         ("blue", L10n.colorBlue, .init(red: 0.1, green: 0.35, blue: 0.8)),
         ("red", L10n.colorRed, .init(red: 0.85, green: 0.15, blue: 0.2)),
         ("purple", L10n.colorPurple, .init(red: 0.55, green: 0.25, blue: 0.8))]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], alignment: .leading, spacing: 8) {
                ForEach(Self.presets, id: \.id) { preset in
                    Button { color = preset.color } label: {
                        ZStack {
                            Circle().fill(preset.color.swiftUIColor).frame(width: 28, height: 28)
                            Circle().strokeBorder(.primary.opacity(color == preset.color ? 1 : 0), lineWidth: 2)
                                .frame(width: 36, height: 36)
                        }.frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset.name)
                    .accessibilityValue(color == preset.color ? L10n.selectionOn : L10n.selectionOff)
                    .accessibilityIdentifier("markup-color-\(preset.id)")
                }
            }
            ColorPicker(L10n.markupCustomColor, selection: Binding(get: { color.swiftUIColor }, set: { value in
                #if os(iOS)
                color = InkConversion.rgba(UIColor(value))
                #else
                color = InkConversion.rgba(NSColor(value))
                #endif
                color.alpha = 1
            }), supportsOpacity: false)
            .accessibilityIdentifier("markup-custom-color")
        }
    }
}

extension RGBAColor {
    var swiftUIColor: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}

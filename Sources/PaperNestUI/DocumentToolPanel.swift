import SwiftUI

/// Shared header and pinned footer for document operations, with no navigation or edit state.
struct DocumentToolPanel<Content: View, Footer: View>: View {
    let title: String
    let symbol: String
    let closeID: String
    var busy = false
    let close: () -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(EditorChrome.purple).font(.title3)
                    .accessibilityHidden(true)
                Text(verbatim: title).font(.headline).fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                Button(action: close) {
                    Image(systemName: "xmark").font(.body.weight(.semibold))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).keyboardShortcut(.cancelAction)
                .accessibilityLabel(L10n.cancel).accessibilityIdentifier(closeID)
                .disabled(busy)
            }.padding(.horizontal, 16).padding(.vertical, 8)
                .background(EditorChrome.surface)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) { content() }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            VStack(spacing: 8) { footer() }
                .padding(16).frame(maxWidth: .infinity).background(EditorChrome.surface)
        }
        .foregroundStyle(EditorChrome.navy)
        .background(EditorChrome.secondaryBackground)
        .tint(EditorChrome.purple)
    }
}

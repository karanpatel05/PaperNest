import SwiftUI

/// Inspector tools keep their own local header and actions. Sheet tools keep
/// native navigation chrome; no nested toolbar can migrate into the Mac window.
struct EditorToolNavigation<Content: View>: View {
    let isEmbedded: Bool
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isEmbedded {
            content()
        } else {
            NavigationStack { content().navigationTitle(title) }
        }
    }
}

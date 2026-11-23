import SwiftUI

/// New Note and Import on the Documents screens (owner, 2026-11-22): New Note
/// is a white button with a lavender tile, Import the filled primary. They
/// show in All Documents and in folders. On a phone they share the width
/// under the title; wider, they sit at the trailing edge.
struct DocumentActionButtons: View {
    var showsNewNote: Bool
    var showsImport: Bool
    /// Two equal halves instead of hugging their labels.
    var fillsWidth: Bool
    var newNoteID = "library-new-note"
    var importID = "library-import"
    let newNote: () -> Void
    let importFiles: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = 32
    @ScaledMetric(relativeTo: .body) private var glyphSize: CGFloat = 22
    /// Solid enough behind white in both appearances (the dark accent is too light).
    private static let filledAction = Theme.adaptive(0x7545F8, 0x6839D8)

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            if showsNewNote {
                Button(action: newNote) {
                    label(L10n.homeNewNote, glyph: .newNote, primary: false, stacked: stacked)
                }
                .accessibilityIdentifier(newNoteID)
            }
            if showsImport {
                Button(action: importFiles) {
                    label(L10n.homeImportFile, glyph: .importFile, primary: true, stacked: stacked)
                }
                .accessibilityIdentifier(importID)
            }
        }
        // Both as tall as the taller when one label wraps.
        .fixedSize(horizontal: false, vertical: true)
        .buttonStyle(PremiumButtonStyle())
    }

    private func label(_ title: String, glyph: TwoToneGlyph, primary: Bool, stacked: Bool) -> some View {
        HStack(spacing: 10) {
            TwoToneIcon(glyph: glyph, palette: primary ? .onFilled : .slate, size: glyphSize)
                .frame(width: tileSize, height: tileSize)
                .background(primary ? Color.white.opacity(0.16) : Theme.raised, in: RoundedRectangle(cornerRadius: 6))
            Text(title)
                .font(.app(.callout).weight(.semibold))
                .foregroundStyle(primary ? Color.white : Theme.navy)
                // Two lines rather than "Importer un fichi…" at iPhone width in French.
                .lineLimit(stacked ? nil : 2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if stacked { Spacer(minLength: 0) }
        }
        .padding(.leading, 6).padding(.trailing, 16).padding(.vertical, 6)
        .frame(maxWidth: fillsWidth || stacked ? .infinity : nil, minHeight: 44, maxHeight: stacked ? nil : .infinity)
        .background(primary ? Self.filledAction : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        .overlay {
            if !primary { RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border, lineWidth: 1) }
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
    }
}

/// The system empty state in the app's face. `ContentUnavailableView` sets
/// its own fonts, so without this its title stayed SF Bold beside Plus
/// Jakarta Sans (seen 2026-11-22).
struct AppEmptyState<Actions: View>: View {
    let title: String
    let systemImage: String
    var description: String?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title).font(.app(.title2).weight(.semibold)).foregroundStyle(Theme.navy)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(Theme.secondaryText)
            }
        } description: {
            if let description {
                Text(description).font(.app(.subheadline)).foregroundStyle(Theme.secondaryText)
            }
        } actions: {
            actions()
        }
    }
}

extension AppEmptyState where Actions == EmptyView {
    init(title: String, systemImage: String, description: String? = nil) {
        self.init(title: title, systemImage: systemImage, description: description) { EmptyView() }
    }
}

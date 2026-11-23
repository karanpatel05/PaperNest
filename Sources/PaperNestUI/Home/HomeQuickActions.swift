import SwiftUI

/// One of Home's quick actions.
struct HomeQuickAction: Identifiable {
    let id: String
    let title: String
    let glyph: TwoToneGlyph
    var isEnabled = true
    /// Read out when the action is unavailable on this device.
    var hint = ""
    let action: () -> Void
}

/// The single row of quick actions under the greeting. Every platform shows
/// this once and nowhere else on Home.
struct HomeQuickActionsRow: View {
    let actions: [HomeQuickAction]
    /// The phone's cards are tinted lavender; the wide dashboard's are white.
    var tinted = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var glyphSize: CGFloat = 24
    @ScaledMetric(relativeTo: .title2) private var tileSize: CGFloat = 36

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) { cards }
            } else {
                // Every card is as tall as the tallest, so a label that wraps
                // in French or Spanish does not leave its neighbours short.
                HStack(alignment: .top, spacing: 12) { cards }
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(PremiumButtonStyle())
    }

    private var cards: some View {
        ForEach(actions) { item in
            Button(action: item.action) { label(item) }
                .disabled(!item.isEnabled)
                .accessibilityLabel(item.title)
                .accessibilityHint(item.hint)
                .accessibilityIdentifier(item.id)
        }
    }

    @ViewBuilder private func label(_ item: HomeQuickAction) -> some View {
        let large = dynamicTypeSize.isAccessibilitySize
        Group {
            if large {
                HStack(spacing: 12) { icon(item); title(item); Spacer(minLength: 0) }
            } else if !tinted {
                HStack(spacing: 10) { icon(item); title(item) }
            } else {
                VStack(spacing: 8) { icon(item); title(item) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: large || !tinted ? 48 : 80, maxHeight: large ? nil : .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay { RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border, lineWidth: 1) }
        .opacity(item.isEnabled ? 1 : 0.45)
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    /// The two-tone glyph in slate: violet is for the selection and the
    /// primary action only (owner, 2026-11-22). Wide cards set it on a tile.
    @ViewBuilder private func icon(_ item: HomeQuickAction) -> some View {
        if tinted {
            TwoToneIcon(glyph: item.glyph, palette: .slate, size: glyphSize + 4)
        } else {
            TwoToneIcon(glyph: item.glyph, palette: .slate, size: glyphSize)
                .frame(width: tileSize, height: tileSize)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func title(_ item: HomeQuickAction) -> some View {
        Text(item.title)
            .font(.app(.subheadline).weight(.medium))
            .foregroundStyle(Theme.navy)
            .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .center)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
    }
}

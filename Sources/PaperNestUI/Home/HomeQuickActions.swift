import SwiftUI

/// One of Home's quick actions.
struct HomeQuickAction: Identifiable {
    let id: String
    let title: String
    let symbol: String
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
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: large || !tinted ? 44 : 72, maxHeight: large ? nil : .infinity)
        .background(Theme.lavender.opacity(tinted ? 0.7 : 0.35), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border, lineWidth: tinted ? 0.5 : 1) }
        .opacity(item.isEnabled ? 1 : 0.45)
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    private func icon(_ item: HomeQuickAction) -> some View {
        Image(systemName: item.symbol)
            .font(.title2.weight(.medium))
            .foregroundStyle(Theme.accent)
            .frame(height: 28)
            .accessibilityHidden(true)
    }

    private func title(_ item: HomeQuickAction) -> some View {
        Text(item.title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.navy)
            .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .center)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
    }
}

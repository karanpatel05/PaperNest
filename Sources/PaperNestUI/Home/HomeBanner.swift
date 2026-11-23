import SwiftUI

/// The greeting Home opens with, chosen from the local hour. It names nobody:
/// the app has no account and so no name it could trust.
enum HomeGreeting {
    static func text(at date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: L10n.premiumMorning
        case 12..<18: L10n.premiumAfternoon
        default: L10n.premiumEvening
        }
    }
}

/// The wide welcome banner on iPad and Mac.
struct HomeBanner: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: 6) {
                    Text(HomeGreeting.text(at: context.date))
                        .font(.app(.title2).bold())
                        .foregroundStyle(Theme.navy)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("home-greeting")
                    Text(L10n.homeSubtitle)
                        .font(.app(.subheadline))
                        .foregroundStyle(Theme.navy.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            if !dynamicTypeSize.isAccessibilitySize {
                HomeBannerArt().frame(width: 150, height: 96)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.radius)
                .fill(LinearGradient(colors: [Theme.lavender, Theme.accent.opacity(0.32)],
                                     startPoint: .leading, endPoint: .trailing))
        }
        .overlay { RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border.opacity(0.6), lineWidth: 0.5) }
    }
}

/// Two sheets of paper and a pen, drawn in code so it follows light and dark
/// mode and needs no bitmap. Decoration only.
private struct HomeBannerArt: View {
    var body: some View {
        ZStack {
            sheet.rotationEffect(.degrees(-12)).offset(x: -18, y: 8).opacity(0.7)
            sheet.rotationEffect(.degrees(8)).offset(x: 10, y: 0)
            Image(systemName: "pencil")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.deepAccent)
                .offset(x: 52, y: 6)
        }
        .accessibilityHidden(true)
    }

    private var sheet: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Theme.surface)
            .frame(width: 74, height: 88)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<4, id: \.self) { index in
                        Capsule().fill(Theme.accent.opacity(0.55))
                            .frame(width: index == 3 ? 28 : 46, height: 5)
                    }
                }.padding(14)
            }
            .shadow(color: Theme.deepAccent.opacity(0.22), radius: 8, y: 4)
    }
}

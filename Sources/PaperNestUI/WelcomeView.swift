import SwiftUI

/// A single introduction; permissions are requested only when a tool needs them.
struct WelcomeView: View {
    let onContinue: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 760 && !dynamicTypeSize.isAccessibilitySize
            ScrollView {
                Group {
                    if wide {
                        HStack(spacing: 56) {
                            introduction.frame(maxWidth: 380)
                            details.frame(maxWidth: 420)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 28) {
                            introduction
                            details
                        }
                        .frame(maxWidth: 480)
                    }
                }
                .padding(wide ? 48 : 24)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .accessibilityIdentifier("welcome-content")
        }
        .clipped()
        .background(Theme.libraryBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                Button(action: onContinue) {
                    Text(L10n.welcomeContinue)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                        .foregroundStyle(.white)
                        .background(Theme.headerGradient, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(PremiumButtonStyle())
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("welcome-continue")
                Text(L10n.welcomeNoAccount)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(Theme.libraryBackground)
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(L10n.welcomeBrand, systemImage: "square.stack.3d.up.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.accent)
            if !dynamicTypeSize.isAccessibilitySize {
                paperIllustration
                    .scaleEffect(0.85)
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
            Text(L10n.welcomeTitle)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("welcome-title")
            Text(welcomeSubtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var welcomeSubtitle: String {
        #if os(iOS)
        L10n.welcomeSubtitle
        #else
        L10n.welcomeMacSubtitle
        #endif
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 24) {
            #if os(iOS)
            feature("doc.viewfinder", title: L10n.welcomeCaptureTitle, detail: L10n.welcomeCaptureDetail)
            #else
            feature("square.and.arrow.down", title: L10n.welcomeCaptureTitle, detail: L10n.welcomeImportDetail)
            #endif
            feature("pencil.tip", title: L10n.welcomeNoteTitle, detail: L10n.welcomeNoteDetail)
            feature("folder", title: L10n.welcomeOrganizeTitle, detail: L10n.welcomeOrganizeDetail)
        }
    }

    private func feature(_ symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var paperIllustration: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.violet.opacity(0.18))
                .frame(width: 145, height: 150)
                .rotationEffect(.degrees(-12))
                .offset(x: -26, y: 5)
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.accent.opacity(0.18))
                .frame(width: 145, height: 150)
                .rotationEffect(.degrees(9))
                .offset(x: 24, y: -3)
            VStack(alignment: .leading, spacing: 13) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.bottom, 4)
                ForEach(0..<3) { row in
                    Capsule().fill(Theme.separator)
                        .frame(width: row == 2 ? 62 : 100, height: 3)
                }
            }
            .padding(24)
            .frame(width: 150, height: 165)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: Theme.paperShadow, radius: 12, y: 8)
        }
        .frame(height: 190)
    }
}

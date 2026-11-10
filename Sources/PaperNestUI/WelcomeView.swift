import SwiftUI

/// Where the brand mark lives.
///
/// Named here rather than inline so a test can prove the asset is really in
/// the built resource bundle. A missing image is a silent failure in SwiftUI:
/// `Image(_:bundle:)` draws nothing, the lockup still lays out, and the only
/// sign is a mark that is not there.
enum BrandMark {
    static let assetName = "BrandMark"
    static var bundle: Bundle { .module }
}

/// A single introduction; permissions are requested only when a tool needs them.
struct WelcomeView: View {
    let onContinue: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Grows with the brand name beside it instead of staying a fixed size.
    @ScaledMetric(relativeTo: .title2) private var markSize: CGFloat = 27

    var body: some View {
        // Two readers on purpose. This one sees the whole area and decides
        // where the action goes; `scrollBody` measures again *inside* the
        // bottom inset, so the scrolling content is centred in the room left
        // over rather than in the full height. Measuring only out here pushed
        // the phone's last feature row behind the button.
        GeometryReader { outer in
            let wide = outer.size.width >= 760 && !dynamicTypeSize.isAccessibilitySize
            // On a tall, wide screen a pinned button ends up marooned at the
            // bottom of the window, a long way from the words it belongs to —
            // on a 13-inch iPad that gap was most of a hand's width of empty
            // space. There the action reads better directly under the copy. A
            // short window keeps it pinned, where it can never scroll out of
            // reach.
            let inlineAction = wide && outer.size.height >= 900
            if inlineAction {
                scrollBody(wide: wide, inlineAction: true)
            } else {
                scrollBody(wide: wide, inlineAction: false)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        actionBlock.background(Theme.libraryBackground)
                    }
            }
        }
        .clipped()
        .background(Theme.libraryBackground)
    }

    private func scrollBody(wide: Bool, inlineAction: Bool) -> some View {
        GeometryReader { geometry in
            let scale = illustrationScale(wide: wide, height: geometry.size.height)
            ScrollView {
                Group {
                    if wide {
                        HStack(spacing: 72) {
                            VStack(alignment: .leading, spacing: 30) {
                                introduction(illustrationScale: scale)
                                if inlineAction { actionBlock }
                            }
                            .frame(maxWidth: 420)
                            details.frame(maxWidth: 460)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 28) {
                            introduction(illustrationScale: scale)
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
    }

    /// Get started, and the line that reassures nothing is being asked for.
    ///
    /// One definition, used either pinned to the bottom edge or inline under
    /// the copy, so the button carries the same identifier, shortcut and
    /// styling in both places and only its position changes.
    private var actionBlock: some View {
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
    }

    /// How much room the illustration gets.
    ///
    /// On a phone it stays the size it has always been. On iPad and Mac it
    /// grows with the window: at the old fixed 160 points it was a stamp
    /// adrift in a 13-inch screen, with the content stranded in a band and
    /// everything below it empty. Tied to height rather than width because
    /// that is the space actually going spare, and clamped at both ends so a
    /// short Mac window does not get an illustration taller than its content.
    private func illustrationScale(wide: Bool, height: CGFloat) -> CGFloat {
        guard wide else { return 0.85 }
        return min(1.55, max(0.95, height / 900))
    }

    /// The mark and the name, as one lockup.
    ///
    /// The mark is the app icon's, generated into `Brand.xcassets` by
    /// `scripts/make-app-icon.py` from the same brand art, so the first
    /// screen after launch shows the icon the user just tapped rather than a
    /// different glyph. It is a *template* image, which is why it can take
    /// `Theme.accent` and follow light and dark mode.
    private var brandLockup: some View {
        HStack(spacing: 9) {
            Image(BrandMark.assetName, bundle: BrandMark.bundle)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: markSize, height: markSize)
                .accessibilityHidden(true)
            Text(L10n.welcomeBrand)
        }
        .font(.title2.weight(.bold))
        .foregroundStyle(Theme.accent)
    }

    private func introduction(illustrationScale scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            brandLockup
            if !dynamicTypeSize.isAccessibilitySize {
                paperIllustration
                    .scaleEffect(scale)
                    .frame(height: 190 * scale)
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

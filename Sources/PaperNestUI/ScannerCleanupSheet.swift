#if os(iOS)
import SwiftUI
import PaperNestCore
import PaperNestRender

/// The Cleanup tool: three amounts, tried on a small picture of the page and
/// handed back only when the person applies them. Nothing changes a page
/// until then, and never more pages than the button pressed says.
struct ScannerCleanupSheet: View {
    enum Scope: Equatable {
        /// One page out of `total`. With more than one, "all pages" is offered too.
        case page(total: Int)
        /// The pages picked in the filmstrip.
        case selection(count: Int)
    }

    enum Target { case page, allPages, selection }

    /// The page shown. For a selection it stands for the others.
    let page: ScannerPage
    let scope: Scope
    let onApply: (ScanCleanup, Target) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ScanCleanup
    @State private var showsBefore = false
    @State private var base: CGImage?
    @State private var picture: UIImage?
    @State private var detent = PresentationDetent.large

    init(page: ScannerPage, scope: Scope, onApply: @escaping (ScanCleanup, Target) -> Void) {
        self.page = page
        self.scope = scope
        self.onApply = onApply
        _draft = State(initialValue: page.appearance.cleanup)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Picker(L10n.scannerCompare, selection: $showsBefore) {
                    Text(L10n.scannerBefore).tag(true)
                    Text(L10n.scannerAfter).tag(false)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("scanner.cleanup.compare")
                preview
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        amount(L10n.scannerRemoveShadows, value: $draft.removeShadows, id: "shadows")
                        amount(L10n.scannerWhitenBackground, value: $draft.whitenBackground, id: "whiten")
                        amount(L10n.scannerSharpenText, value: $draft.sharpenText, id: "sharpen")
                        Button(L10n.cropReset) { draft = .none }
                            .buttonStyle(.bordered)
                            .disabled(!draft.isActive)
                            .accessibilityIdentifier("scanner.cleanup.reset")
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 12)
            .foregroundStyle(.white)
            .background(ScannerChrome.background.ignoresSafeArea())
            .navigationTitle(L10n.scannerCleanup)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }.accessibilityIdentifier("scanner.cleanup.cancel")
                }
                // In the bar, where it is always in reach. Below the sliders
                // it ended up underneath the Apply buttons on a short screen,
                // and a tap meant for it applied and closed the sheet.
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.scannerRecommended) { draft = .recommended }
                        .accessibilityIdentifier("scanner.cleanup.recommended")
                }
            }
            .safeAreaInset(edge: .bottom) { applyButtons }
        }
        .tint(Theme.accent)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .environment(\.colorScheme, .dark)
        // Moving an amount while looking at Before would change nothing on
        // screen, so the picture goes back to After.
        .onChange(of: draft) { _, _ in showsBefore = false }
        .task {
            let source = page
            base = await Task.detached(priority: .userInitiated) { source.base(maxDimension: 900) }.value
        }
    }

    /// What the page looks like with the amounts on screen, or without any.
    private var preview: some View {
        ZStack {
            if let picture {
                Image(uiImage: picture).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 280)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel(showsBefore ? L10n.scannerBefore : L10n.scannerAfter)
        .accessibilityValue(Self.describe(showsBefore ? .none : draft))
        .accessibilityIdentifier("scanner.cleanup.preview")
        .task(id: PreviewKey(cleanup: showsBefore ? .none : draft, ready: base != nil)) {
            guard let base else { return }
            // A slider sends many values; draw only the one it rests on.
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            let appearance = ScanAppearance(preset: page.appearance.preset, cleanup: showsBefore ? .none : draft)
            let image = await Task.detached(priority: .userInitiated) { ScanImageProcessor.apply(appearance, to: base) }.value
            guard !Task.isCancelled, let image else { return }
            picture = ScannerPage.turned(image, quarterTurns: page.quarterTurns)
        }
    }

    private struct PreviewKey: Hashable {
        let cleanup: ScanCleanup
        let ready: Bool
    }

    /// The three amounts as whole percentages, for tests and for VoiceOver.
    static func describe(_ cleanup: ScanCleanup) -> String {
        [cleanup.removeShadows, cleanup.whitenBackground, cleanup.sharpenText]
            .map { String(Int(($0 * 100).rounded())) }.joined(separator: "/")
    }

    private func amount(_ title: String, value: Binding<Double>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.app(.subheadline).weight(.medium))
                Spacer()
                Text(verbatim: "\(Int((value.wrappedValue * 100).rounded()))%")
                    .font(.app(.caption).monospacedDigit())
                    .foregroundStyle(ScannerChrome.secondaryText)
                    .accessibilityHidden(true)
            }
            Slider(value: value, in: 0...1) { Text(title) }
                .accessibilityIdentifier("scanner.cleanup.\(id)")
        }
    }

    @ViewBuilder private var applyButtons: some View {
        VStack(spacing: 8) {
            switch scope {
            case .page(let total):
                apply(L10n.scannerApplyToPage, to: .page, prominent: true, id: "apply-page")
                // Never every page without being asked: it is its own button.
                if total > 1 { apply(L10n.scannerApplyToAll, to: .allPages, prominent: false, id: "apply-all") }
            case .selection:
                apply(L10n.scannerApplyToSelected, to: .selection, prominent: true, id: "apply-selected")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(ScannerChrome.panel)
    }

    @ViewBuilder private func apply(_ title: String, to target: Target, prominent: Bool, id: String) -> some View {
        let button = Button {
            onApply(draft, target)
            dismiss()
        } label: {
            Text(title).font(.app(.subheadline).weight(.semibold)).frame(maxWidth: .infinity, minHeight: 30)
        }
        .accessibilityIdentifier("scanner.cleanup.\(id)")
        if prominent { button.buttonStyle(.borderedProminent).tint(ScannerChrome.purple) }
        else { button.buttonStyle(.bordered) }
    }
}
#endif

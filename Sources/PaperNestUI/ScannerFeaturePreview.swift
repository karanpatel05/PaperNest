#if os(iOS)
import SwiftUI
import PaperNestCore

/// Scan Studio's review controls. The preset strip and the batch bar act on
/// the pages themselves (`ScannerPage.appearance`, `ScanPageBatch`); the
/// Cleanup sheet is in `ScannerCleanupSheet.swift`.

extension ScanPreset {
    var title: String {
        switch self {
        case .original: L10n.scannerOriginal
        case .auto: L10n.scannerAutoPreset
        case .enhanced: L10n.scannerEnhancedPreset
        case .grayscale: L10n.filterGrayscale
        case .blackAndWhite: L10n.filterBlackAndWhite
        case .highContrast: L10n.scannerHighContrast
        }
    }

    var symbol: String {
        switch self {
        case .original: "circle.lefthalf.filled"
        case .auto: "wand.and.stars"
        case .enhanced: "sparkles"
        case .grayscale: "circle.grid.cross"
        case .blackAndWhite: "circle.righthalf.filled"
        case .highContrast: "circle.dotted"
        }
    }
}

/// One tile per preset, showing which the page has, and Cleanup at the end:
/// Cleanup is several amounts rather than one look, so it opens its own sheet.
struct ScannerPresetStrip: View {
    /// The preset of the page being shown. Nil when there is no page.
    let selection: ScanPreset?
    /// Whether that page has any Cleanup applied.
    let cleanupActive: Bool
    let onSelect: (ScanPreset) -> Void
    let onCleanup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.scannerPresets)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ScannerChrome.secondaryText)
                .padding(.horizontal, 2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ScanPreset.allCases, id: \.self) { preset in
                        tile(preset.rawValue, symbol: preset.symbol, title: preset.title, isOn: selection == preset) {
                            onSelect(preset)
                        }
                    }
                    tile("cleanup", symbol: "slider.horizontal.3", title: L10n.scannerCleanup, isOn: cleanupActive, action: onCleanup)
                }
            }
        }
        .foregroundStyle(.white)
    }

    private func tile(_ id: String, symbol: String, title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(ScannerChrome.raised)
                        .frame(width: 58, height: 42)
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundStyle(isOn ? Theme.accent : .white)
                }
                Text(title)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 64, height: 28, alignment: .top)
            }
            .padding(4)
            .background(isOn ? ScannerChrome.purple.opacity(0.24) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isOn ? Theme.accent : ScannerChrome.stroke, lineWidth: isOn ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("scanner.preset.\(id)")
        .accessibilityValue(isOn ? L10n.selectionOn : L10n.selectionOff)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// What can be done to the pages picked in the filmstrip. The count stays
/// in view; every action waits until at least one page is picked.
struct ScannerBatchToolbar: View {
    let count: Int
    let canMoveEarlier: Bool
    let canMoveLater: Bool
    let onClose: () -> Void
    let onFilter: (ScanPreset) -> Void
    let onCleanup: () -> Void
    let onDuplicate: () -> Void
    let onMove: (ScanPageBatch.Direction) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onClose) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.done)
                .accessibilityIdentifier("scanner.batch.close")
            Text(L10n.scannerSelectedCount(count))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .accessibilityIdentifier("scanner.batch.count")
                .accessibilityValue(String(count))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    Menu {
                        ForEach(ScanPreset.allCases, id: \.self) { preset in
                            Button(preset.title) { onFilter(preset) }
                        }
                    } label: { ScannerToolLabel(symbol: "camera.filters", title: L10n.filter) }
                    .accessibilityLabel(L10n.filter)
                    .accessibilityIdentifier("scanner.batch.filter")
                    action("slider.horizontal.3", L10n.scannerCleanup, id: "cleanup", perform: onCleanup)
                    action("plus.square.on.square", L10n.duplicate, id: "duplicate", perform: onDuplicate)
                    action("arrow.backward", L10n.scannerMoveEarlier, id: "earlier") { onMove(.earlier) }
                        .disabled(!canMoveEarlier)
                    action("arrow.forward", L10n.scannerMoveLater, id: "later") { onMove(.later) }
                        .disabled(!canMoveLater)
                    action("trash", L10n.delete, id: "delete", perform: onDelete)
                }
                .padding(.horizontal, 4)
            }
            .disabled(count == 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .foregroundStyle(.white)
        .background(ScannerChrome.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(ScannerChrome.stroke, lineWidth: 1) }
        // Icon over name here, on iPad too: these sit in a row, not a column.
        .environment(\.scannerToolsVertical, false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.scannerSelectPages)
    }

    private func action(_ symbol: String, _ title: String, id: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { ScannerToolLabel(symbol: symbol, title: title) }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityIdentifier("scanner.batch.\(id)")
    }
}
#endif

#if os(iOS)
import SwiftUI

/// The scanner's own dark surface. These are fixed, not adaptive: capture and
/// review stay dark in both appearances, like a camera.
enum ScannerChrome {
    static let background = Color(red: 0.055, green: 0.051, blue: 0.086)
    static let panel = Color(red: 0.110, green: 0.102, blue: 0.161)
    static let raised = Color(red: 0.165, green: 0.153, blue: 0.235)
    static let stroke = Color.white.opacity(0.12)
    /// Behind white text: the owner palette's primary purple, #7438F5.
    static let purple = Color(red: 0.455, green: 0.220, blue: 0.961)
    static let secondaryText = Color.white.opacity(0.70)
}

/// What the camera is pointed at.
///
/// Only modes that change what the scanner does are here. A document has its
/// edges found, outlined and cropped to; a photo keeps the whole frame.
enum ScanKind: String, CaseIterable, Identifiable {
    case document, photo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .document: L10n.scannerKindDocument
        case .photo: L10n.scannerKindPhoto
        }
    }

    /// Whether edges are detected, drawn over the preview and cropped to.
    var findsEdges: Bool { self == .document }
}

/// The capture screen's mode picker.
struct ScannerKindSelector: View {
    @Binding var kind: ScanKind

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ScanKind.allCases) { option in
                Button { kind = option } label: {
                    Text(option.title).font(.footnote.weight(.semibold))
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(kind == option ? ScannerChrome.purple : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("scanner.kind.\(option.rawValue)")
                .accessibilityAddTraits(kind == option ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.black.opacity(0.6), in: Capsule())
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.scannerKind)
    }
}

/// The review tools run down a side panel on iPad and along the bottom on a phone.
private struct ScannerToolsVerticalKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var scannerToolsVertical: Bool {
        get { self[ScannerToolsVerticalKey.self] }
        set { self[ScannerToolsVerticalKey.self] = newValue }
    }
}

/// One review tool: a full-width row in the side panel, icon over name in the strip.
struct ScannerToolLabel: View {
    let symbol: String
    let title: String
    var active = false
    @Environment(\.scannerToolsVertical) private var vertical
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Group {
            if vertical {
                HStack(spacing: 10) {
                    Image(systemName: symbol).frame(width: 24)
                    Text(title).font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(active ? ScannerChrome.purple : ScannerChrome.raised, in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(ScannerChrome.stroke, lineWidth: 1) }
            } else {
                VStack(spacing: 5) {
                    Image(systemName: symbol)
                    Text(title).font(.caption)
                }
                .foregroundStyle(active ? Theme.accent : .white)
                .frame(minWidth: 44, minHeight: 44)
            }
        }
        .foregroundStyle(.white)
        .opacity(isEnabled ? 1 : 0.4)
        .contentShape(Rectangle())
    }
}
#endif

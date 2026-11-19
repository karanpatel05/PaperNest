#if os(iOS)
import SwiftUI
import PaperNestCore
import PaperNestRender

/// What `ScanQualityAnalyzer` found on each page of the scan in progress,
/// measured once per page and crop. A draft's own advice, not a record:
/// nothing here is saved, and a page with a report pending simply shows none.
@MainActor @Observable final class ScanQualityMemo {
    static let shared = ScanQualityMemo()

    /// The latest report for each page, with the crop it was measured on.
    private var reports: [UUID: (key: String, report: ScanQualityReport)] = [:]
    @ObservationIgnored private var measuring: Set<String> = []

    /// Changes when the measurement would: a new crop changes the page
    /// measured and the angle. A turn or a look does not.
    nonisolated static func key(of page: ScannerPage) -> String { "\(page.id)-\(page.corners)" }

    /// The issues found on `page` as it is cropped now; none until measured.
    func issues(for page: ScannerPage) -> [ScanQualityIssue] {
        guard let stored = reports[page.id], stored.key == Self.key(of: page) else { return [] }
        return stored.report.issues
    }

    /// Measures `page` off the main thread, unless its crop already was.
    func measure(_ page: ScannerPage) async {
        let key = Self.key(of: page)
        guard reports[page.id]?.key != key, !measuring.contains(key) else { return }
        measuring.insert(key)
        defer { measuring.remove(key) }
        let draft = page
        let report = await Task.detached(priority: .utility) { () -> ScanQualityReport? in
            guard let base = draft.base(maxDimension: CGFloat(ScanQualityAnalyzer.longSide)) else { return nil }
            return ScanQualityAnalyzer.report(page: base, corners: draft.corners,
                                              photoSize: ScanQualityAnalyzer.photoSize(of: draft.original))
        }.value
        if let report { reports[page.id] = (key, report) }
    }
}

extension ScanQualityIssue {
    var title: String {
        switch self {
        case .blurry: L10n.scannerQualityBlurry
        case .steepAngle: L10n.scannerQualitySteepAngle
        case .tooDark: L10n.scannerQualityTooDark
        }
    }
}

/// The corner mark on a page's thumbnail when something about it is worth a
/// second look. Silent to VoiceOver: the page's own label names the issues.
struct ScanQualityBadge: View {
    let page: ScannerPage

    var body: some View {
        Group {
            if !ScanQualityMemo.shared.issues(for: page).isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.palette).foregroundStyle(.black, .yellow)
                    .font(.caption.weight(.bold))
                    .padding(3)
                    .background(Circle().fill(Color.black.opacity(0.55)))
                    .padding(2)
                    .accessibilityHidden(true)
            }
        }
        .task(id: ScanQualityMemo.key(of: page)) { await ScanQualityMemo.shared.measure(page) }
    }
}

/// What the corner mark means, said under the page being reviewed, clear of
/// the zoom controls at its top.
struct ScanQualityNote: View {
    let page: ScannerPage

    var body: some View {
        let issues = ScanQualityMemo.shared.issues(for: page)
        Group {
            if !issues.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow).accessibilityHidden(true)
                    Text(issues.map(\.title).joined(separator: " · "))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.footnote.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.black.opacity(0.75), in: Capsule())
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("scanner.quality")
            }
        }
        .task(id: ScanQualityMemo.key(of: page)) { await ScanQualityMemo.shared.measure(page) }
    }
}
#endif

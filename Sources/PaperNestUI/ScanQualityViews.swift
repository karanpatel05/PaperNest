#if os(iOS)
import CryptoKit
import SwiftUI
import PaperNestCore
import PaperNestRender

/// What `ScanQualityAnalyzer` found on each page of the scan in progress,
/// measured once per page and crop, and which pages repeat which. A draft's
/// own advice, not a record: nothing here is saved, and a page with a
/// measurement pending simply shows none.
@MainActor @Observable final class ScanQualityMemo {
    static let shared = ScanQualityMemo()

    /// The latest report for each page, with the crop it was measured on.
    private var reports: [UUID: (key: String, report: ScanQualityReport)] = [:]
    /// Each page's fingerprint, with its crop and a digest of its bytes.
    private var prints: [UUID: (key: String, print: ScanFingerprint, digest: Data)] = [:]
    /// Whether two crops (their keys, in order) are the same page photographed twice.
    private var alike: [String: Bool] = [:]
    @ObservationIgnored private var measuring: Set<String> = []

    /// Changes when the measurement would: a new crop changes the page
    /// measured and the angle. A turn or a look does not.
    nonisolated static func key(of page: ScannerPage) -> String { "\(page.id)-\(page.corners)" }

    nonisolated private static func pair(_ a: String, _ b: String) -> String { a < b ? "\(a)|\(b)" : "\(b)|\(a)" }

    /// The issues found on `page` as it is cropped now, as far as its
    /// capture mode lets them be said; none until measured.
    func issues(for page: ScannerPage) -> [ScanQualityIssue] {
        guard let stored = reports[page.id], stored.key == Self.key(of: page) else { return [] }
        return stored.report.issues(in: page.mode)
    }

    /// Where in `pages` the first earlier page is that `page` repeats: the
    /// same paper photographed again. A page with the very same bytes as an
    /// earlier one is a copy made on purpose (Duplicate, or one file brought
    /// in twice), never a second photograph, so it says nothing.
    func repeated(_ page: ScannerPage, among pages: [ScannerPage]) -> Int? {
        guard let index = pages.firstIndex(where: { $0.id == page.id }),
              let mine = prints[page.id], mine.key == Self.key(of: page) else { return nil }
        let earlier = pages[..<index].compactMap { other in
            prints[other.id].flatMap { $0.key == Self.key(of: other) ? $0 : nil }
        }
        guard !earlier.contains(where: { $0.digest == mine.digest }) else { return nil }
        return pages[..<index].firstIndex { other in
            guard let theirs = prints[other.id], theirs.key == Self.key(of: other) else { return false }
            return alike[Self.pair(mine.key, theirs.key)] == true
        }
    }

    /// What is worth saying about `page`, in words: its issues, then the
    /// page it repeats.
    func notes(for page: ScannerPage, among pages: [ScannerPage]) -> [String] {
        var notes = issues(for: page).map(\.title)
        if let earlier = repeated(page, among: pages) { notes.append(L10n.scannerQualitySameAs(earlier + 1)) }
        return notes
    }

    /// Measures `page` off the main thread, unless its crop already was,
    /// then compares it with every other page measured so far.
    func measure(_ page: ScannerPage) async {
        let key = Self.key(of: page)
        guard reports[page.id]?.key != key, !measuring.contains(key) else { return }
        measuring.insert(key)
        defer { measuring.remove(key) }
        let draft = page
        let measured = await Task.detached(priority: .utility) { () -> (ScanQualityReport, ScanFingerprint, Data)? in
            guard let base = draft.base(maxDimension: CGFloat(ScanQualityAnalyzer.longSide)),
                  let found = ScanQualityAnalyzer.examine(page: base, corners: draft.corners,
                                                          photoSize: ScanQualityAnalyzer.photoSize(of: draft.original))
            else { return nil }
            return (found.report, found.fingerprint, Data(SHA256.hash(data: draft.original)))
        }.value
        guard let (report, print, digest) = measured else { return }
        reports[page.id] = (key, report)
        prints[page.id] = (key, print, digest)
        let others = prints.filter { $0.key != page.id }.map(\.value)
        guard !others.isEmpty else { return }
        let results = await Task.detached(priority: .utility) { () -> [(String, Bool)] in
            others.map { other in
                (Self.pair(key, other.key), other.digest != digest && ScanLikeness.isSamePage(print, other.print))
            }
        }.value
        for (pair, same) in results { alike[pair] = same }
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
    /// The scan's pages, in order, for telling which one this repeats.
    let pages: [ScannerPage]

    var body: some View {
        Group {
            if !ScanQualityMemo.shared.notes(for: page, among: pages).isEmpty {
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
    let pages: [ScannerPage]

    var body: some View {
        let notes = ScanQualityMemo.shared.notes(for: page, among: pages)
        Group {
            if !notes.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow).accessibilityHidden(true)
                    Text(notes.joined(separator: " · "))
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

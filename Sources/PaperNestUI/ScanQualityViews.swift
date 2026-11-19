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

    /// Where in `pages` the page is that `page` repeats — the same paper
    /// photographed again — when `page` is the one of the two worth deleting:
    /// the one with something wrong with it, when only one has; otherwise the
    /// later, the extra copy. So a blurred page retaken is marked, naming its
    /// good retake, and the retake is left alone: marking the retake, as the
    /// first version did, invited deleting the good page.
    ///
    /// A page with the very same bytes and crop as an earlier one is a copy
    /// made on purpose (Duplicate, or one file brought in twice), never a
    /// second photograph, so it says nothing. Bytes alone are not enough: a
    /// book's two pages come from one photo.
    func repeated(_ page: ScannerPage, among pages: [ScannerPage]) -> Int? {
        func current(_ page: ScannerPage) -> (key: String, print: ScanFingerprint, digest: Data)? {
            prints[page.id].flatMap { $0.key == Self.key(of: page) ? $0 : nil }
        }
        guard let index = pages.firstIndex(where: { $0.id == page.id }), let mine = current(page) else { return nil }
        guard !pages[..<index].contains(where: { current($0)?.digest == mine.digest && $0.corners == page.corners })
        else { return nil }
        let flawed = !issues(for: page).isEmpty
        return pages.indices.first { other in
            guard other != index, let theirs = current(pages[other]), alike[Self.pair(mine.key, theirs.key)] == true
            else { return false }
            let theyAreFlawed = !issues(for: pages[other]).isEmpty
            return flawed != theyAreFlawed ? flawed : other < index
        }
    }

    /// What is worth saying about `page`, in words: its issues, then the
    /// page it repeats.
    func notes(for page: ScannerPage, among pages: [ScannerPage]) -> [String] {
        var notes = issues(for: page).map(\.title)
        if let earlier = repeated(page, among: pages) { notes.append(L10n.scannerQualitySameAs(earlier + 1)) }
        return notes
    }

    /// How many pages are measured and how many pairs compared: for tests.
    var measuredCount: Int { prints.count }
    var comparedCount: Int { alike.count }

    /// Measures `page` off the main thread, unless its crop already was,
    /// then compares it with the other pages of the scan, `pages`. The memo
    /// lives as long as the app, so it then forgets every page not in
    /// `pages` — an earlier scan's, a deleted one — and every pair with
    /// one: otherwise each capture would be compared with everything scanned
    /// since launch.
    func measure(_ page: ScannerPage, among pages: [ScannerPage]) async {
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
        forget(allBut: Set(pages.map(\.id)).union([page.id]))
        let others = prints.filter { $0.key != page.id }.map(\.value)
        guard !others.isEmpty else { return }
        let results = await Task.detached(priority: .utility) { () -> [(String, Bool)] in
            others.map { other in
                (Self.pair(key, other.key), other.digest != digest && ScanLikeness.isSamePage(print, other.print))
            }
        }.value
        // Only pairs whose pages are still measured as they are now.
        let current = Set(prints.values.map(\.key))
        for (pair, same) in results where pair.split(separator: "|").allSatisfy({ current.contains(String($0)) }) {
            alike[pair] = same
        }
    }

    /// Drops what is known about pages other than `kept`, and pairs with a
    /// page no longer measured as it is now (deleted, or cropped again).
    private func forget(allBut kept: Set<UUID>) {
        if reports.keys.contains(where: { !kept.contains($0) }) { reports = reports.filter { kept.contains($0.key) } }
        if prints.keys.contains(where: { !kept.contains($0) }) { prints = prints.filter { kept.contains($0.key) } }
        let current = Set(prints.values.map(\.key))
        let stale = alike.keys.filter { !$0.split(separator: "|").allSatisfy { current.contains(String($0)) } }
        for pair in stale { alike[pair] = nil }
    }
}

extension ScanQualityIssue {
    var title: String {
        switch self {
        case .blurry: L10n.scannerQualityBlurry
        case .steepAngle: L10n.scannerQualitySteepAngle
        case .tooDark: L10n.scannerQualityTooDark
        case .glare: L10n.scannerQualityGlare
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
        .task(id: ScanQualityMemo.key(of: page)) { await ScanQualityMemo.shared.measure(page, among: pages) }
    }
}

/// What the corner mark means, said under the page being reviewed, clear of
/// the zoom controls at its top.
struct ScanQualityNote: View {
    let page: ScannerPage
    let pages: [ScannerPage]
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var widthClass
    @State private var expanded = false

    var body: some View {
        let notes = ScanQualityMemo.shared.notes(for: page, among: pages)
        Group {
            if !notes.isEmpty {
                if typeSize.isAccessibilitySize && widthClass == .compact { mark(notes) } else { inline(notes) }
            }
        }
        .task(id: ScanQualityMemo.key(of: page)) { await ScanQualityMemo.shared.measure(page, among: pages) }
    }

    private func inline(_ notes: [String]) -> some View {
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

    /// At the accessibility text sizes on a phone the page preview is small
    /// (about 120 points on an iPhone 17), and the note in full covered it,
    /// zoom controls and all. So there the note is a mark of a fixed size
    /// that opens it in a sheet; VoiceOver reads the whole note from the
    /// mark. (A popover was tried first: at these sizes it clipped the note
    /// top and bottom, and drew it light on light.)
    private func mark(_ notes: [String]) -> some View {
        Button { expanded = true } label: {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.palette).foregroundStyle(.black, .yellow)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.75), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(notes.joined(separator: " · "))
        .accessibilityIdentifier("scanner.quality")
        .sheet(isPresented: $expanded) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(notes, id: \.self) { note in
                            Label {
                                Text(note).fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                            }
                        }
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("scanner.quality.full")
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.done) { expanded = false }.accessibilityIdentifier("scanner.quality.done")
                    }
                }
            }
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            .presentationBackground(ScannerChrome.panel)
            .presentationDetents([.medium, .large])
        }
    }
}
#endif

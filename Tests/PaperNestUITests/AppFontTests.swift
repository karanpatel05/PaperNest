import Foundation
import SwiftUI
import Testing
@testable import PaperNestUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Plus Jakarta Sans is the app's typeface (owner, 2026-11-22). Each failure
/// here is silent in the app: a missing file or a failed registration makes
/// `Font.custom` fall back to SF with no error, and a weight that does not
/// resolve to a real instance draws faux-bold or regular text.
@Suite struct AppFontTests {
    @Test func theFaceAndItsLicenceAreInTheResourceBundle() throws {
        let font = try #require(Bundle.module(for: AppFont.self).url(forResource: AppFont.resourceName, withExtension: "ttf"))
        #expect(try Data(contentsOf: font).count > 100_000)
        let licence = try #require(Bundle.module(for: AppFont.self).url(forResource: "PlusJakartaSans-OFL", withExtension: "txt"))
        #expect(try String(contentsOf: licence, encoding: .utf8).contains("SIL Open Font License"))
    }

    @Test func theFaceRegistersForTheProcess() {
        #expect(AppFont.isAvailable)
    }

    @Test func everyWeightTheAppUsesIsARealInstance() throws {
        #expect(AppFont.isAvailable)
        for (weight, name) in [(5, "Regular"), (6, "Medium"), (8, "SemiBold"), (9, "Bold"), (11, "ExtraBold")] {
            #if canImport(AppKit)
            let font = try #require(NSFontManager.shared.font(withFamily: AppFont.family, traits: [], weight: weight, size: 17))
            #expect(font.familyName == AppFont.family)
            #expect(name == "Regular" ? !font.fontName.contains("_") : font.fontName.hasSuffix(name), "\(font.fontName)")
            #elseif canImport(UIKit)
            let uiWeight: UIFont.Weight = [5: .regular, 6: .medium, 8: .semibold, 9: .bold, 11: .heavy][weight]!
            let font = AppFont.uiFont(.body, size: 17, weight: uiWeight)
            #expect(font.familyName == AppFont.family)
            #expect(name == "Regular" ? !font.fontName.contains("_") : font.fontName.hasSuffix(name), "\(font.fontName)")
            #endif
        }
    }

    /// Sizes follow the platform's own text styles: scaled on iPhone and iPad
    /// so the wider face keeps existing line lengths, never under 11 points
    /// on the Mac.
    @Test func sizesFollowThePlatformTextStyles() {
        #expect(AppFont.size(for: .body) == (AppFont.baseSize(for: .body) * AppFont.opticalScale * 10).rounded() / 10)
        #if os(macOS)
        #expect(AppFont.opticalScale == 1)
        for style in [Font.TextStyle.footnote, .caption, .caption2, .subheadline, .callout] {
            #expect(AppFont.size(for: style) >= 11, "\(style)")
        }
        #else
        #expect(AppFont.opticalScale == 0.95)
        #endif
        #expect(AppFont.size(for: .largeTitle) > AppFont.size(for: .title))
        #expect(AppFont.size(for: .title) > AppFont.size(for: .headline))
        #expect(AppFont.size(for: .headline) == AppFont.size(for: .body))
        #expect(AppFont.size(for: .caption2) <= AppFont.size(for: .caption))
    }

    /// "Whole app": a view that sets `.font(.headline)` and the like draws SF
    /// beside Plus Jakarta Sans. Read from source the way `BrandMarkTests`
    /// does. Lines that size an SF Symbol keep the system styles on purpose,
    /// as do monospaced and fixed-size icon fonts and page content.
    @Test func noViewSetsASystemTextStyle() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PaperNestUI")
        let styles = "largeTitle|title2|title3|title|headline|subheadline|body|callout|footnote|caption2|caption"
        let pattern = try Regex("\\.font\\(\\.(\(styles))(?![A-Za-z0-9_])")
        var offenders: [String] = []
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        #expect(files.count > 50)
        for file in files {
            for (index, line) in try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains(pattern) && !line.contains("Image(systemName") {
                offenders.append("\(file.lastPathComponent):\(index + 1)")
            }
        }
        #expect(offenders.isEmpty, "use .app(_:) instead: \(offenders.joined(separator: ", "))")
    }

    /// Measured: on iPhone and iPad, Plus Jakarta Sans at the scaled size is
    /// within a few percent of SF's width for a long French label, so layouts
    /// tuned for SF hold. The Mac keeps full size, a little wider than SF.
    @Test func theScaledFaceKeepsSFsLineLength() throws {
        #expect(AppFont.isAvailable)
        let text = "Supprimés récemment" as NSString
        #if canImport(AppKit)
        let face = try #require(NSFont(name: AppFont.family, size: 17 * AppFont.opticalScale))
        let sf = NSFont.systemFont(ofSize: 17)
        #elseif canImport(UIKit)
        let face = try #require(UIFont(name: AppFont.family, size: 17 * AppFont.opticalScale))
        let sf = UIFont.systemFont(ofSize: 17)
        #endif
        let ratio = text.size(withAttributes: [.font: face]).width / text.size(withAttributes: [.font: sf]).width
        #if os(macOS)
        #expect(ratio > 1 && ratio < 1.09, "width ratio \(ratio)")
        #else
        #expect(abs(ratio - 1) < 0.04, "width ratio \(ratio)")
        #endif
    }
}

private extension Bundle {
    /// The PaperNestUI resource bundle, reached from the test target.
    static func module(for _: Any.Type) -> Bundle { BrandMark.bundle }
}

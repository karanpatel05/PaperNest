import Foundation
import Testing
@testable import PaperNestUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// The welcome screen's lockup must show the app's own mark.
///
/// Both of these guard the same promise from different sides, because either
/// failure is silent. A missing asset makes `Image(_:bundle:)` draw nothing
/// while the layout still looks sane, and swapping back to a system symbol
/// compiles perfectly and leaves the first screen after launch showing a
/// different logo from the icon the user just tapped.
@Suite struct BrandMarkTests {
    @Test func theBrandMarkIsInTheBuiltResourceBundle() throws {
        #if canImport(AppKit)
        #expect(BrandMark.bundle.image(forResource: BrandMark.assetName) != nil)
        #elseif canImport(UIKit)
        #expect(UIImage(named: BrandMark.assetName, in: BrandMark.bundle, compatibleWith: nil) != nil)
        #endif
    }

    /// Read from source the way `LocalizationTests` already reads source, so
    /// the check survives views that cannot be instantiated in a unit test.
    ///
    /// Stated as an invariant over the whole module rather than a list of
    /// known places: the failure this guards against is someone reaching for
    /// a lookalike SF Symbol in a view that does not exist yet.
    @Test func nothingInTheModuleDrawsALookalikeSymbolInsteadOfTheMark() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // PaperNestUITests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // repository root
            .appendingPathComponent("Sources/PaperNestUI")
        let files = try FileManager.default
            .contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)

        // Glyphs that have stood in for the mark. `BrandMark.swift` names
        // them in prose to say why they are wrong, so it is exempt.
        for symbol in ["leaf.circle", "square.stack.3d.up.fill"] {
            var offenders: [String] = []
            for file in files where file.lastPathComponent != "BrandMark.swift" {
                let source = try String(contentsOf: file, encoding: .utf8)
                if source.contains("\"\(symbol)\"") { offenders.append(file.lastPathComponent) }
            }
            #expect(offenders.isEmpty, "\(symbol) is drawn in \(offenders)")
        }
    }

    @Test func theLockupsDrawTheMarkThroughTheSharedBuilder() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PaperNestUI")
        for view in ["WelcomeView.swift", "LibraryHome.swift", "SubscriptionViews.swift"] {
            let source = try String(contentsOf: sources.appendingPathComponent(view), encoding: .utf8)
            #expect(source.contains("BrandMark.image(size:"), "\(view) no longer draws the brand mark")
        }
    }
}

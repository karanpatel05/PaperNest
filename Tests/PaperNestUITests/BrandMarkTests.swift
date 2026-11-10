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
    /// the check survives a view that cannot be instantiated in a unit test.
    @Test func theWelcomeLockupDrawsThatMarkRatherThanASystemSymbol() throws {
        let view = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // PaperNestUITests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // repository root
            .appendingPathComponent("Sources/PaperNestUI/WelcomeView.swift")
        let source = try String(contentsOf: view, encoding: .utf8)
        #expect(source.contains("Image(BrandMark.assetName, bundle: BrandMark.bundle)"))
        // The glyph the lockup used before the icon existed.
        #expect(!source.contains("square.stack.3d.up.fill"))
    }
}

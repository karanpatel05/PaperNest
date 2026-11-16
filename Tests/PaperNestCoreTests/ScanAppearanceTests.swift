import Testing
@testable import PaperNestCore

@Suite struct ScanAppearanceTests {
    @Test func amountsOutsideTheSliderRangeAreClamped() {
        let cleanup = ScanCleanup(removeShadows: 1.7, whitenBackground: -0.2, sharpenText: 0.45)
        #expect(cleanup.removeShadows == 1)
        #expect(cleanup.whitenBackground == 0)
        #expect(cleanup.sharpenText == 0.45)
    }

    /// A slider binding writes straight to the property, so the property
    /// has to hold the range itself, not only the initializer.
    @Test func amountsAssignedLaterAreClampedToo() {
        var cleanup = ScanCleanup()
        cleanup.removeShadows = 3
        cleanup.whitenBackground = -1
        cleanup.sharpenText = 0.2
        #expect(cleanup.removeShadows == 1)
        #expect(cleanup.whitenBackground == 0)
        #expect(cleanup.sharpenText == 0.2)
    }

    /// NaN compares false with everything, so a plain min/max would keep it
    /// and every filter downstream would produce an empty page.
    @Test func anAmountThatIsNotANumberMeansNoCleanup() {
        var cleanup = ScanCleanup(removeShadows: .nan, whitenBackground: .infinity, sharpenText: -.infinity)
        #expect(cleanup.removeShadows == 0)
        #expect(cleanup.whitenBackground == 1)
        #expect(cleanup.sharpenText == 0)
        cleanup.sharpenText = .nan
        #expect(cleanup.sharpenText == 0)
    }

    @Test func cleanupIsActiveOnlyWhenSomeAmountIsAboveZero() {
        #expect(!ScanCleanup.none.isActive)
        #expect(!ScanCleanup(removeShadows: 0, whitenBackground: 0, sharpenText: 0).isActive)
        #expect(ScanCleanup(removeShadows: 0.01).isActive)
        #expect(ScanCleanup(whitenBackground: 0.5).isActive)
        #expect(ScanCleanup(sharpenText: 1).isActive)
        #expect(ScanCleanup.recommended.isActive)
    }

    @Test func aPageIsOriginalOnlyWithNoPresetAndNoCleanup() {
        #expect(ScanAppearance.original.isOriginal)
        #expect(!ScanAppearance(preset: .grayscale).isOriginal)
        #expect(!ScanAppearance(cleanup: ScanCleanup(sharpenText: 0.3)).isOriginal)
        var appearance = ScanAppearance(preset: .highContrast, cleanup: .recommended)
        appearance = .original
        #expect(appearance.preset == .original)
        #expect(appearance.cleanup == .none)
    }

    /// The preview and the thumbnails redraw when this value changes, so two
    /// pages that would draw differently must not compare equal.
    @Test func appearancesThatDrawDifferentlyAreNotEqual() {
        let base = ScanAppearance(preset: .auto, cleanup: ScanCleanup(removeShadows: 0.5))
        #expect(base == ScanAppearance(preset: .auto, cleanup: ScanCleanup(removeShadows: 0.5)))
        #expect(base != ScanAppearance(preset: .enhanced, cleanup: ScanCleanup(removeShadows: 0.5)))
        #expect(base != ScanAppearance(preset: .auto, cleanup: ScanCleanup(removeShadows: 0.51)))
    }
}

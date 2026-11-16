/// One named look for a scanned page. A page has exactly one at a time.
///
/// The cases are in the order the scanner offers them.
public enum ScanPreset: String, Sendable, CaseIterable {
    /// The capture as it was taken.
    case original
    /// Automatic tone and colour correction.
    case auto
    /// Auto, with firmer contrast, fuller colour and a little sharpening.
    case enhanced
    case grayscale
    /// Ink black on paper white, judged against the paper around each mark
    /// so a shadow across the page does not turn into a black patch.
    case blackAndWhite
    /// Strong contrast with colour kept: faint pencil, marker on a board.
    case highContrast
}

/// The Cleanup tool's three amounts. Each runs from 0, which leaves the page
/// alone, to 1.
public struct ScanCleanup: Hashable, Sendable {
    /// Evens out lighting: darker stretches of paper are lifted to the level
    /// of the best-lit paper.
    public var removeShadows: Double { didSet { removeShadows = Self.amount(removeShadows) } }
    /// Lifts the paper toward white and takes its colour cast with it.
    public var whitenBackground: Double { didSet { whitenBackground = Self.amount(whitenBackground) } }
    /// Sharpens edges, for typed and printed pages.
    public var sharpenText: Double { didSet { sharpenText = Self.amount(sharpenText) } }

    public init(removeShadows: Double = 0, whitenBackground: Double = 0, sharpenText: Double = 0) {
        self.removeShadows = Self.amount(removeShadows)
        self.whitenBackground = Self.amount(whitenBackground)
        self.sharpenText = Self.amount(sharpenText)
    }

    public static let none = ScanCleanup()

    /// What the Cleanup sheet's Recommended button sets. Chosen on synthetic
    /// pages with a shadow across them; not yet tried on a photographed page.
    public static let recommended = ScanCleanup(removeShadows: 0.85, whitenBackground: 0.5, sharpenText: 0.4)

    public var isActive: Bool { removeShadows > 0 || whitenBackground > 0 || sharpenText > 0 }

    /// NaN compares false with everything, so it is named before clamping.
    private static func amount(_ value: Double) -> Double {
        value.isNaN ? 0 : min(max(value, 0), 1)
    }
}

/// Everything about how a scanned page looks that is not its geometry.
/// Never stored: a scan's edits are drawn into the page it is saved as.
public struct ScanAppearance: Hashable, Sendable {
    public var preset: ScanPreset
    public var cleanup: ScanCleanup

    public init(preset: ScanPreset = .original, cleanup: ScanCleanup = .none) {
        self.preset = preset
        self.cleanup = cleanup
    }

    public static let original = ScanAppearance()

    public var isOriginal: Bool { preset == .original && !cleanup.isActive }
}

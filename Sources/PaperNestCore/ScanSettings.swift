/// The scanner's defaults. They decide how the scanner opens and what look a
/// new capture starts with; they never change a page already scanned.
public struct ScanSettings: Equatable, Sendable {
    public var mode: ScanCaptureMode
    /// The default filter, for paper: see `ScanCaptureMode.startingAppearance`.
    public var preset: ScanPreset
    /// Whether the automatic shutter is on when the scanner opens.
    public var startsAutomatic: Bool

    public init(mode: ScanCaptureMode = .document, preset: ScanPreset = .original, startsAutomatic: Bool = false) {
        self.mode = mode
        self.preset = preset
        self.startsAutomatic = startsAutomatic
    }

    public static let standard = ScanSettings()

    /// From whatever was stored. A value that is missing, or that this
    /// version does not know, falls back by itself.
    public init(storedMode: String?, storedPreset: String?, storedStartsAutomatic: Bool?) {
        self.init(mode: storedMode.flatMap(ScanCaptureMode.init(rawValue:)) ?? ScanSettings.standard.mode,
                  preset: storedPreset.flatMap(ScanPreset.init(rawValue:)) ?? ScanSettings.standard.preset,
                  startsAutomatic: storedStartsAutomatic ?? ScanSettings.standard.startsAutomatic)
    }

    public var stored: (mode: String, preset: String, startsAutomatic: Bool) {
        (mode.rawValue, preset.rawValue, startsAutomatic)
    }

    /// The automatic shutter waits for a rectangle to hold still, so it can
    /// only start in a mode that looks for one.
    public var automaticOnEntry: Bool { startsAutomatic && mode.findsEdges }
}

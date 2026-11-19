import Testing
@testable import PaperNestCore

@Suite struct ScanSettingsTests {
    @Test func nothingStoredMeansADocumentAsTakenWithTheShutterManual() {
        let settings = ScanSettings(storedMode: nil, storedPreset: nil, storedStartsAutomatic: nil)
        #expect(settings == .standard)
        #expect(settings.mode == .document && settings.preset == .original && !settings.startsAutomatic)
    }

    /// A value written by a later version, or damaged, must not stop the
    /// scanner opening: each falls back by itself.
    @Test func aValueThisVersionDoesNotKnowFallsBackAlone() {
        let settings = ScanSettings(storedMode: "hologram", storedPreset: "grayscale", storedStartsAutomatic: true)
        #expect(settings.mode == .document)
        #expect(settings.preset == .grayscale)
        #expect(settings.startsAutomatic)
        #expect(ScanSettings(storedMode: "card", storedPreset: "sepia", storedStartsAutomatic: nil)
            == ScanSettings(mode: .card, preset: .original, startsAutomatic: false))
        // Book was once the example of a mode from another version; it is this version's now.
        #expect(ScanSettings(storedMode: "book", storedPreset: nil, storedStartsAutomatic: nil).mode == .book)
    }

    @Test func whatIsStoredReadsBackTheSame() {
        let settings = ScanSettings(mode: .whiteboard, preset: .blackAndWhite, startsAutomatic: true)
        let stored = settings.stored
        #expect(stored.mode == "whiteboard" && stored.preset == "blackAndWhite" && stored.startsAutomatic)
        #expect(ScanSettings(storedMode: stored.mode, storedPreset: stored.preset, storedStartsAutomatic: stored.startsAutomatic) == settings)
    }

    /// A photo has no sheet to wait for, so there is no automatic shutter to start.
    @Test func autoStartsOnlyInAModeThatHasAnAutomaticShutter() {
        #expect(ScanSettings(mode: .document, preset: .original, startsAutomatic: true).automaticOnEntry)
        #expect(ScanSettings(mode: .card, preset: .original, startsAutomatic: true).automaticOnEntry)
        #expect(!ScanSettings(mode: .photo, preset: .original, startsAutomatic: true).automaticOnEntry)
        #expect(!ScanSettings(mode: .document, preset: .original, startsAutomatic: false).automaticOnEntry)
    }
}

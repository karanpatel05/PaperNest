import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestUI

/// What the toolbar remembers, and whether it survives being put away.
@MainActor @Suite struct EditorToolSettingsTests {
    /// A defaults domain of this test's own, emptied before and after, so no
    /// run can read what another left and nothing reaches the real one.
    private func scratchDefaults() -> UserDefaults {
        let name = "papernest.tests.toolsettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func aFreshStoreStartsFromTheShippedTools() {
        let settings = EditorToolSettingsStore(defaults: scratchDefaults()).settings
        #expect(settings == EditorToolSettings())
        // The pen in hand on first launch draws what the pen always drew.
        #expect(settings.penPreset == .gel)
        #expect(settings.currentPen.width == 2 && settings.currentPen.color == .black)
        #expect(settings.currentHighlighter.width == 20)
        #expect(settings.eraserSize == 36 && settings.eraserMode == .precision)
    }

    @Test func everyChangeIsOnDiskBeforeTheCallReturns() {
        let defaults = scratchDefaults()
        let store = EditorToolSettingsStore(defaults: defaults)
        store.update {
            $0.penPreset = .fountain
            $0.currentPen.width = 5.5
            $0.eraserTarget = .highlights
            $0.shapeKind = .hexagon
            $0.lassoContent = [.images]
        }
        // A second store is the app, opened again.
        let reopened = EditorToolSettingsStore(defaults: defaults).settings
        #expect(reopened == store.settings)
        #expect(reopened.penPreset == .fountain && reopened.currentPen.width == 5.5)
        #expect(reopened.eraserTarget == .highlights && reopened.shapeKind == .hexagon)
        #expect(reopened.lassoContent == [.images])
    }

    /// "Persist each pen preset independently."
    @Test func eachPenKeepsItsOwnWidthAndColour() {
        let store = EditorToolSettingsStore(defaults: scratchDefaults())
        let red = RGBAColor(red: 0.85, green: 0.15, blue: 0.2, alpha: 0.4)
        store.update { $0.penPreset = .brush; $0.currentPen.width = 9; $0.currentPen.color = red }
        store.update { $0.penPreset = .ballpoint }
        #expect(store.settings.currentPen.width == PenPreset.ballpoint.defaultWidth)
        #expect(store.settings.currentPen.color == .black)
        store.update { $0.penPreset = .brush }
        #expect(store.settings.currentPen.width == 9 && store.settings.currentPen.color == red)
        // The same holds for highlighter styles.
        store.update { $0.highlighterStyle = .underline; $0.currentHighlighter.width = 7 }
        store.update { $0.highlighterStyle = .standard }
        #expect(store.settings.currentHighlighter.width == 20)
        #expect(store.settings.highlighter(.underline).width == 7)
    }

    @Test func restoringOneToolLeavesEveryOtherToolAlone() {
        let store = EditorToolSettingsStore(defaults: scratchDefaults())
        store.update {
            $0.penPreset = .marker; $0.currentPen.width = 11; $0.smoothing = 0.9
            $0.eraserSize = 60
            $0.noteColorUsed(RGBAColor(red: 0.2, green: 0.4, blue: 0.6))
        }
        store.update { $0.restoreDefaults(for: .pen) }
        #expect(store.settings.currentPen.width == PenPreset.marker.defaultWidth)
        #expect(store.settings.smoothing == EditorToolSettings().smoothing)
        #expect(store.settings.penPreset == .marker, "restoring a pen does not change which pen is in hand")
        #expect(store.settings.eraserSize == 60)
        #expect(store.settings.recentColors.count == 1)
    }

    /// A blob from an older build is missing whatever was added since. One
    /// absent or unreadable key must not cost the user everything else.
    @Test func anOlderOrDamagedBlobKeepsWhatItCanRead() throws {
        let defaults = scratchDefaults()
        let partial = #"{"penPreset":"brush","eraserSize":50,"eraserTarget":"somethingNew","shapeWidth":900}"#
        defaults.set(Data(partial.utf8), forKey: EditorToolSettingsStore.key)
        let settings = EditorToolSettingsStore(defaults: defaults).settings
        #expect(settings.penPreset == .brush)
        #expect(settings.eraserSize == 50)
        #expect(settings.eraserTarget == .all, "an unknown value falls back for that key alone")
        #expect(settings.shapeWidth == 20, "out-of-range numbers are brought back into range")
        #expect(settings.lassoContent == Set(LassoContent.allCases))

        defaults.set(Data("not json".utf8), forKey: EditorToolSettingsStore.key)
        #expect(EditorToolSettingsStore(defaults: defaults).settings == EditorToolSettings())
    }

    @Test func aStoreWithNowhereToWriteStillWorksForTheSession() {
        let store = EditorToolSettingsStore(defaults: nil)
        store.update { $0.penPreset = .pencil }
        #expect(store.settings.penPreset == .pencil)
    }

    /// Every UI test and dev run points at a throwaway library. Those start
    /// from the shipped tools, so one test's settings cannot become the next
    /// test's starting state.
    @Test func aThrowawayLibraryKeepsToolSettingsInMemory() {
        let defaults = scratchDefaults()
        #expect(EditorToolSettingsStore.standardStorage(defaults) === defaults)
        defaults.set("/tmp/some-test-library", forKey: "PaperNestLibraryPath")
        #expect(EditorToolSettingsStore.standardStorage(defaults) == nil)
        defaults.set(true, forKey: "PaperNestDebugPersistToolSettings")
        #expect(EditorToolSettingsStore.standardStorage(defaults) === defaults)
    }

    @Test func recentColoursAreNewestFirstWithoutRepeatsOrOpacity() {
        var settings = EditorToolSettings()
        let blue = RGBAColor(red: 0, green: 0, blue: 1), green = RGBAColor(red: 0, green: 1, blue: 0)
        settings.noteColorUsed(blue)
        settings.noteColorUsed(green)
        settings.noteColorUsed(RGBAColor(red: 0, green: 0, blue: 1, alpha: 0.3))
        #expect(settings.recentColors == [blue, green])
        for index in 0..<20 { settings.noteColorUsed(RGBAColor(red: Double(index) / 20, green: 0, blue: 0)) }
        #expect(settings.recentColors.count == EditorToolSettings.recentColorLimit)
        settings.toggleFavorite(blue)
        #expect(settings.isFavorite(RGBAColor(red: 0, green: 0, blue: 1, alpha: 0.5)))
        settings.toggleFavorite(blue)
        #expect(settings.favoriteColors.isEmpty)
    }

    @Test func theCanvasReadsWidthAndColourForTheToolInHand() {
        var settings = EditorToolSettings()
        settings.currentPen.width = 3
        settings.currentHighlighter.strength = 0.5
        settings.eraserSize = 44
        settings.shapeWidth = 6
        #expect(settings.width(for: .pen) == 3 && settings.width(for: .eraser) == 44 && settings.width(for: .shape) == 6)
        #expect(settings.width(for: .lasso) == 0)
        #expect(settings.color(for: .highlighter).alpha == 0.5)
        #expect(settings.color(for: .highlighter).red == settings.highlighterColor.red)
    }
}

/// How a drag becomes the stroke that is saved.
@Suite struct InkDrawingStyleTests {
    private func drag(seconds: Double = 0.2) -> [PenSample] {
        (0...20).map { PenSample(x: Double($0) * 10, y: $0.isMultiple(of: 2) ? 1 : -1, time: seconds * Double($0) / 20) }
    }

    @Test func aStraightLineHighlighterAlwaysSavesTheLineBetweenItsEnds() throws {
        var settings = EditorToolSettings()
        settings.highlighterStyle = .straight
        let style = settings.drawingStyle(for: .highlighter)
        let stroke = try #require(style.stroke(from: drag(), endTime: 0.2, grip: 5, tool: .highlighter,
                                                color: .black, width: 20))
        #expect(stroke.points.map { CGPoint(x: $0.x, y: $0.y) } == [CGPoint(x: 0, y: 1), CGPoint(x: 200, y: 1)])
        #expect(stroke.tool == .highlighter && stroke.cap == nil)
    }

    @Test func aFlatHighlighterSavesAFlatTipAndAFreehandPath() throws {
        var settings = EditorToolSettings()
        settings.highlighterStyle = .flat
        let stroke = try #require(settings.drawingStyle(for: .highlighter)
            .stroke(from: drag(), endTime: 0.2, grip: 5, tool: .highlighter, color: .black, width: 20))
        #expect(stroke.cap == .flat)
        #expect(stroke.points.count == 21)
        #expect(stroke.points.allSatisfy { $0.widthScale == 1 }, "a highlighter is one even band")
    }

    /// The pause is the request. Lifted straight away, the same wobbly line is
    /// kept as drawn; rested on, it is straightened.
    @Test func aPenOnlySnapsWhenTheHandRested() throws {
        var settings = EditorToolSettings()
        settings.penPreset = .ballpoint
        settings.smoothing = 0
        let style = settings.drawingStyle(for: .pen)
        let lifted = try #require(style.stroke(from: drag(), endTime: 0.2, grip: 5, tool: .pen, color: .black, width: 2))
        #expect(lifted.points.count == 21)
        let rested = try #require(style.stroke(from: drag(), endTime: 0.9, grip: 5, tool: .pen, color: .black, width: 2))
        #expect(rested.points.count == 2)

        settings.snapsOnHold = false
        let off = try #require(settings.drawingStyle(for: .pen)
            .stroke(from: drag(), endTime: 0.9, grip: 5, tool: .pen, color: .black, width: 2))
        #expect(off.points.count == 21, "switched off, a rest changes nothing")
    }

    @Test func thePenInHandShapesWhatIsSaved() throws {
        var settings = EditorToolSettings()
        settings.snapsOnHold = false
        settings.smoothing = 0
        func widths(_ preset: PenPreset) throws -> [Double] {
            settings.penPreset = preset
            return try #require(settings.drawingStyle(for: .pen)
                .stroke(from: drag(), endTime: 0.2, grip: 5, tool: .pen, color: .black, width: 4)).points.map(\.widthScale)
        }
        #expect(try widths(.ballpoint).allSatisfy { $0 == 1 })
        #expect(try widths(.brush) != widths(.fountain))
        #expect(try widths(.brush).contains { $0 < 0.9 })
    }

    @Test func nothingDrawnSavesNothing() {
        #expect(InkDrawingStyle().stroke(from: [], endTime: 0, grip: 5, tool: .pen, color: .black, width: 2) == nil)
    }
}

/// What the eraser and the lasso are allowed to touch.
@Suite struct ToolTargetTests {
    private let page = PageID.make()

    private func object(_ payload: PageObject.Payload) -> PageObject {
        PageObject(pageID: page, zKey: "a", payload: payload, modifiedAt: Date(timeIntervalSince1970: 0))
    }

    private var everything: [PageObject] {
        [object(.ink(InkStroke(tool: .pen, color: .black, width: 2, points: [InkPoint(x: 0, y: 0)]))),
         object(.ink(InkStroke(tool: .highlighter, color: .black, width: 20, points: [InkPoint(x: 0, y: 0)]))),
         object(.text(TextBox(frame: CGRect(x: 0, y: 0, width: 10, height: 10), text: "typed"))),
         object(.image(PlacedImage(assetID: AssetID(sha256: String(repeating: "a", count: 64)), frame: CGRect(x: 0, y: 0, width: 10, height: 10)))),
         object(.comment("private"))]
    }

    /// Whatever the eraser is set to, it is only ever handed ink. That is the
    /// whole protection for text, images and the page: they are not offered.
    @Test(arguments: EraserTarget.allCases) func theEraserIsOnlyEverGivenInk(_ target: EraserTarget) {
        let erasable = target.erasable(in: everything)
        #expect(erasable.allSatisfy { if case .ink = $0.payload { true } else { false } })
        let tools = erasable.compactMap { object -> InkStroke.Tool? in
            if case .ink(let ink) = object.payload { return ink.tool }
            return nil
        }
        switch target {
        case .all: #expect(tools == [.pen, .highlighter])
        case .handwriting: #expect(tools == [.pen])
        case .highlights: #expect(tools == [.highlighter])
        }
    }

    @Test func theLassoSortsContentIntoItsFourKinds() {
        #expect(everything.map(LassoContent.kind(of:)) == [.handwriting, .highlights, .textBoxes, .images, nil])
    }

    @Test func everyToolbarToolHasItsDrawingModeOrNone() {
        #expect(EditorTool.allCases.compactMap(\.markupTool) == [.pen, .highlighter, .eraser, .lasso, .shape])
        #expect(EditorTool.allCases.count == 9)
    }
}

/// The app's own sticker artwork.
@Suite struct StickerLibraryTests {
    @Test func everyStickerHasAUniqueIdentifier() {
        #expect(Set(StickerLibrary.all.map(\.id)).count == StickerLibrary.all.count)
        #expect(StickerLibrary.all.count == 16)
        for category in StickerCategory.allCases {
            #expect(StickerLibrary.all.contains { $0.category == category }, "\(category) is empty")
        }
    }

    /// A sticker that drew nothing would place an invisible image. Every one
    /// has to put real, coloured pixels on a transparent ground.
    @Test(arguments: StickerLibrary.all) func everyStickerDrawsSomethingOnATransparentGround(_ sticker: Sticker) throws {
        let image = try #require(StickerLibrary.image(for: sticker, pixels: 64))
        #expect(image.width == 64 && image.height == 64)
        let data = try #require(image.dataProvider?.data as Data?)
        let alphas = stride(from: 3, to: data.count, by: 4).map { data[$0] }
        let covered = Double(alphas.filter { $0 > 200 }.count) / Double(alphas.count)
        #expect(covered > 0.12, "\(sticker.id) covers only \(covered)")
        #expect(alphas.contains(0), "\(sticker.id) has no transparent ground")
        // Top-left pixel is outside every drawing.
        #expect(alphas[0] == 0, "\(sticker.id)")
    }

    @Test func aStickerIsStoredAsAPNGThatIsTheSameEveryTime() throws {
        let sticker = try #require(StickerLibrary.sticker("star"))
        let first = try #require(StickerLibrary.pngData(for: sticker))
        #expect(first.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        // Content-addressed storage keeps one copy only if the bytes match.
        #expect(StickerLibrary.pngData(for: sticker) == first)
        #expect(DocumentModel.pixelSize(of: first) == CGSize(width: 320, height: 320))
    }

    @Test func searchIgnoresCaseAndAccents() {
        #expect(StickerLibrary.search("").count == StickerLibrary.all.count)
        #expect(StickerLibrary.search("   ").count == StickerLibrary.all.count)
        let star = StickerLibrary.all.first { $0.id == "star" }!
        let query = String(star.name.prefix(3)).uppercased().folding(options: .diacriticInsensitive, locale: nil)
        #expect(StickerLibrary.search(query).contains(star))
        #expect(StickerLibrary.search("zzzzzz").isEmpty)
    }
}

import SwiftUI
import Testing
@testable import PaperNestUI

/// The glyphs are hand-placed coordinates on a 24-point grid. A slip in one
/// number draws a shape off the grid or an empty layer, and nothing else
/// would notice: the icon is decorative and hidden from accessibility.
@Suite struct TwoToneIconTests {
    @Test(arguments: TwoToneGlyph.allCases)
    func everyGlyphHasTwoTonesInsideItsGrid(_ glyph: TwoToneGlyph) {
        let layers = glyph.layers
        #expect(layers.count >= 2, "\(glyph) has \(layers.count) layer")
        #expect(Set(layers.map { "\($0.tone)" }).count >= 2, "\(glyph) is one tone")
        for layer in layers {
            let box = layer.path.boundingRect
            #expect(!layer.path.isEmpty && box.width > 1 && box.height > 1, "\(glyph) has an empty layer")
            // Round stroke caps reach half a point past their line.
            #expect(box.minX >= 1 && box.minY >= 1 && box.maxX <= 23 && box.maxY <= 23, "\(glyph) leaves its grid: \(box)")
        }
    }

    /// Selected and unselected places must be told apart by more than a
    /// slightly different grey.
    @Test func selectedAndUnselectedPalettesDiffer() {
        #expect("\(IconPalette.accent.strong)" != "\(IconPalette.inactive.strong)")
        #expect("\(IconPalette.accent.mid)" != "\(IconPalette.inactive.mid)")
    }

    /// The home's door, the pencil's band and the folder's front are the
    /// strong tone; the body behind them is lighter.
    @Test func theFrontLayerIsTheStrongTone() {
        for glyph in [TwoToneGlyph.home, .notes, .folder, .newNote, .importFile] {
            #expect(glyph.layers.last?.tone == .strong, "\(glyph)")
        }
    }
}

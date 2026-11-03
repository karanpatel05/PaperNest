import Foundation
import Testing
import PaperNestExport
@testable import PaperNestUI

/// Which export formats the sheet actually offers.
///
/// TXT, HEIC and DOCX all worked in the engine, were unit-tested, and could
/// not be chosen by anyone: the sheet listed PDF, JPEG and PNG as three
/// hand-written tiles, so a format added to `ExportFormat` reached no screen
/// and nothing said so. The list is data now, and this is the test that
/// notices the next time one is left out.
@Suite struct ExportFormatOfferTests {
    @Test func everyFormatTheEngineCanWriteIsOffered() {
        let offered = Set(ExportSheet.offeredFormats.map(\.format))

        #expect(offered == Set(ExportFormat.allCases),
                "a format the engine writes that the sheet will not offer is a feature nobody can reach")
    }

    @Test func noFormatIsOfferedTwice() {
        let offered = ExportSheet.offeredFormats.map(\.format)

        #expect(offered.count == Set(offered).count)
    }

    @Test func everyTileHasSomethingToShow() {
        for tile in ExportSheet.offeredFormats {
            #expect(!tile.title.isEmpty, "\(tile.format) has no title")
            #expect(!tile.systemImage.isEmpty, "\(tile.format) has no icon")
        }
    }

    /// PDF stays first: it is what nearly every export is, and a reordering
    /// that buried it would be a regression nobody would call one.
    @Test func pdfIsOfferedFirst() {
        #expect(ExportSheet.offeredFormats.first?.format == .pdf)
    }

    /// The two formats that carry the words alone are the two that must not
    /// show resolution, quality or packaging — controls that would do
    /// nothing. Kept on the format itself so the sheet cannot disagree with
    /// the engine about which is which.
    @Test func onlyTextFormatsCarryWordsAlone() {
        let wordsOnly = ExportFormat.allCases.filter(\.keepsOnlyWords)

        #expect(Set(wordsOnly) == Set([.txt, .docx]))
    }

    @Test func everyFormatKnowsWhichItIs() {
        // No case may be forgotten when the next format is added: this fails
        // to compile-or-pass rather than silently treating it as an image.
        for format in ExportFormat.allCases {
            let isImage = !format.keepsOnlyWords
            #expect(isImage == [.pdf, .jpeg, .png, .heic].contains(format), "\(format)")
        }
    }
}

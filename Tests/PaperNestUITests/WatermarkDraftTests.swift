import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestExport
@testable import PaperNestUI

/// The export sheet's watermark, before it is a `Watermark`: what each preset
/// fills in, when the sheet refuses to export, and what an export is given.
@Suite struct WatermarkDraftTests {
    @Test func noneIsTheDefaultAndExportsNothing() {
        let draft = WatermarkDraft()
        #expect(draft.preset == nil)
        #expect(draft.watermark() == nil)
        #expect(draft.problem == nil)
        #expect(draft.previewDescription == L10n.exportWatermarkNone)
    }

    @Test func aPresetFillsInItsOwnWordAndLook() throws {
        var draft = WatermarkDraft()
        draft.choose(.confidential)
        #expect(draft.text == L10n.exportWatermarkWordConfidential)
        #expect(draft.placement == .center)
        #expect(draft.opacity == WatermarkPreset.confidential.defaultOpacity)
        #expect(draft.rotation == -32)
        let mark = try #require(draft.watermark())
        #expect(mark.preset == .confidential)
        #expect(mark.text == L10n.exportWatermarkWordConfidential)
        #expect(mark.dateLine == nil)

        draft.choose(.approved)
        #expect(draft.text == L10n.exportWatermarkWordApproved)
        #expect(draft.placement == .bottomRight)
    }

    @Test func switchingPresetStartsAgain() {
        var draft = WatermarkDraft()
        draft.choose(.draft)
        draft.text = "Typed"
        draft.placement = .tiled
        draft.includesDate = true
        draft.choose(.confidential)
        #expect(draft.text == L10n.exportWatermarkWordConfidential)
        #expect(draft.placement == .center)
        #expect(!draft.includesDate)
        draft.choose(nil)
        #expect(draft.watermark() == nil)
    }

    @Test func choosingTheSamePresetAgainKeepsWhatWasSet() {
        var draft = WatermarkDraft()
        draft.choose(.custom)
        draft.text = "Acme Ltd"
        draft.placement = .tiled
        draft.opacity = 0.4
        draft.choose(.custom)
        #expect(draft.text == "Acme Ltd")
        #expect(draft.placement == .tiled)
        #expect(draft.opacity == 0.4)
    }

    /// Text that draws nothing is named as such, not as missing text.
    @Test func textThatDrawsNothingSaysSo() {
        var draft = WatermarkDraft()
        draft.choose(.custom)
        draft.text = "🔒"
        #expect(draft.problem == L10n.exportWatermarkTextUndrawable)
        draft.text = "TOP 🔒 SECRET"
        #expect(draft.problem == nil)
    }

    @Test func customWithNoTextCannotBeExported() {
        var draft = WatermarkDraft()
        draft.choose(.custom)
        #expect(draft.text.isEmpty)
        #expect(draft.problem == L10n.exportWatermarkTextMissing)
        draft.text = "   "
        #expect(draft.problem == L10n.exportWatermarkTextMissing)
        draft.text = "Acme Ltd"
        #expect(draft.problem == nil)
        #expect(draft.watermark()?.text == "Acme Ltd")
    }

    @Test func everyControlReachesTheExport() throws {
        var draft = WatermarkDraft()
        draft.choose(.draft)
        draft.placement = .bottomRight
        draft.opacity = 0.4
        draft.rotation = 15
        let mark = try #require(draft.watermark())
        #expect(mark.placement == .bottomRight)
        #expect(mark.opacity == 0.4)
        #expect(mark.rotation == 15)
    }

    /// Save, Copy and Share all export with what this hands them.
    @Test func everyExportCarriesTheDraftWhereItCanBeDrawn() throws {
        var draft = WatermarkDraft()
        draft.choose(.confidential)
        draft.placement = .tiled
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        for format in [ExportFormat.pdf, .jpeg, .png, .heic] {
            let options = ExportSheet.optionsToExport(ExportOptions(format: format), watermark: draft, on: day)
            #expect(options.watermark == draft.watermark(on: day), "\(format) lost the watermark")
            #expect(options.watermark?.placement == .tiled)
        }
        for options in [ExportOptions(format: .txt), ExportOptions(format: .docx),
                        ExportOptions(format: .docx, docxLayout: .pageImages)] {
            #expect(ExportSheet.optionsToExport(options, watermark: draft).watermark == nil)
        }
        #expect(ExportSheet.optionsToExport(ExportOptions(format: .pdf), watermark: WatermarkDraft()).watermark == nil)
    }

    @Test func theDateIsWrittenInTheReadersLanguage() throws {
        var draft = WatermarkDraft()
        draft.choose(.approved)
        draft.includesDate = true
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 12)))
        #expect(draft.watermark(on: day, locale: Locale(identifier: "en_US"))?.dateLine == "Nov 16, 2026")
        #expect(draft.watermark(on: day, locale: Locale(identifier: "fr_FR"))?.dateLine == "16 nov. 2026")
        draft.includesDate = false
        #expect(draft.watermark(on: day)?.dateLine == nil)
    }

    @Test func thePreviewSaysWhatIsDrawn() {
        var draft = WatermarkDraft()
        draft.choose(.draft)
        let said = draft.previewDescription
        #expect(said.contains(L10n.exportWatermarkDraft))
        #expect(said.contains(L10n.exportWatermarkPlacementTopRight))
        #expect(said.contains(WatermarkDraft.percent(draft.opacity)))
    }

    /// The preview is the page on its paper with the export's own drawing
    /// over the paper: on Letter, a Draft capsule sits in the paper's corner,
    /// above a square page that does not reach it.
    @Test func thePreviewPutsTheMarkOnThePaper() throws {
        let page = try #require(CGContext(data: nil, width: 300, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        page.setFillColor(CGColor(srgbRed: 0.9, green: 0.9, blue: 0.9, alpha: 1))
        page.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
        let layout = PaperLayout(pageSize: CGSize(width: 600, height: 600), paper: .usLetter)
        let mark = Watermark(preset: .draft, text: "DRAFT")
        let composed = try #require(WatermarkPreview.draw(page.makeImage()!, layout: layout, watermark: mark))
        #expect(abs(Double(composed.width) / Double(composed.height) - 612.0 / 792.0) < 0.01)

        var buffer = [UInt8](repeating: 0, count: composed.width * composed.height * 4)
        let ctx = CGContext(data: &buffer, width: composed.width, height: composed.height, bitsPerComponent: 8,
                            bytesPerRow: composed.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(composed, in: CGRect(x: 0, y: 0, width: composed.width, height: composed.height))
        func pixel(_ x: Double, _ y: Double) -> (Int, Int, Int) {
            let px = Int(Double(composed.width) * x), py = Int(Double(composed.height) * y)
            let i = (py * composed.width + px) * 4
            return (Int(buffer[i]), Int(buffer[i + 1]), Int(buffer[i + 2]))
        }
        // The paper band above the page is white at its left…
        #expect(pixel(0.1, 0.05) == (255, 255, 255))
        // …the page is in the middle…
        #expect(pixel(0.5, 0.5).0 < 240)
        // …and the capsule's tint is in the paper's top-right corner.
        var tinted = 0
        for y in stride(from: 0.02, to: 0.09, by: 0.005) {
            for x in stride(from: 0.75, to: 0.97, by: 0.01) {
                let (r, g, b) = pixel(x, y)
                if b > g + 10, r < 250 { tinted += 1 }
            }
        }
        #expect(tinted > 10, "no capsule in the paper's corner")
    }
}

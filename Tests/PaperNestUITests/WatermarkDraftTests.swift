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
            let options = ExportSheet.optionsToExport(ExportOptions(format: format), watermark: draft, includesBrandMark: false, on: day)
            #expect(options.watermark == draft.watermark(on: day), "\(format) lost the watermark")
            #expect(options.watermark?.placement == .tiled)
        }
        for options in [ExportOptions(format: .txt), ExportOptions(format: .docx),
                        ExportOptions(format: .docx, docxLayout: .pageImages)] {
            #expect(ExportSheet.optionsToExport(options, watermark: draft, includesBrandMark: false).watermark == nil)
        }
        #expect(ExportSheet.optionsToExport(ExportOptions(format: .pdf), watermark: WatermarkDraft(), includesBrandMark: false).watermark == nil)
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

    // MARK: - The PaperNest watermark

    /// The branded preset stamps the brand's own name beside its real mark,
    /// and offers nothing to retype.
    @Test func thePaperNestPresetUsesTheBrandsNameAndMark() throws {
        var draft = WatermarkDraft()
        draft.choose(.paperNest)
        #expect(draft.text == Brand.displayName)
        #expect(draft.problem == nil)
        let mark = try #require(draft.watermark())
        #expect(mark.shape == .brand)
        #expect(mark.text == Brand.displayName)
        #expect(mark.logo != nil, "the brand mark's logo did not load")
        // Even if the text were changed under it, the name stays the brand's.
        draft.text = "Someone else"
        #expect(draft.watermark()?.text == Brand.displayName)
    }

    /// The app's real mark loads as a mask: some of it paints, some does not.
    @Test func theBrandLogoLoadsAsAMask() throws {
        let logo = try #require(BrandMark.watermarkLogo)
        let mask = logo.mask
        var buffer = [UInt8](repeating: 0, count: mask.width * mask.height)
        let ctx = try #require(CGContext(data: &buffer, width: mask.width, height: mask.height, bitsPerComponent: 8,
                                         bytesPerRow: mask.width, space: CGColorSpaceCreateDeviceGray(),
                                         bitmapInfo: CGImageAlphaInfo.none.rawValue))
        ctx.draw(mask, in: CGRect(x: 0, y: 0, width: mask.width, height: mask.height))
        #expect(buffer.contains { $0 > 240 }, "no part of the mark paints")
        #expect(buffer.contains { $0 < 15 }, "every part of the mark paints")
        #expect(mask.width >= 64, "the logo is a thumbnail")
    }

    /// The mark free exports carry goes on every format that can hold one,
    /// and only when the sheet's switch is on.
    @Test func theFreeMarkReachesEveryExportThatCanCarryIt() throws {
        for format in [ExportFormat.pdf, .jpeg, .png, .heic] {
            let options = ExportSheet.optionsToExport(ExportOptions(format: format), watermark: WatermarkDraft(),
                                                      includesBrandMark: true)
            let mark = try #require(options.attribution, "\(format) lost the PaperNest mark")
            #expect(mark.placement == .bottomLeft)
            #expect(mark.text == Brand.displayName)
            #expect(mark.logo != nil)
            #expect(options.watermark == nil, "None is still None beside the mark")
        }
        for options in [ExportOptions(format: .txt), ExportOptions(format: .docx)] {
            #expect(ExportSheet.optionsToExport(options, watermark: WatermarkDraft(), includesBrandMark: true).attribution == nil)
        }
        #expect(ExportSheet.optionsToExport(ExportOptions(format: .pdf), watermark: WatermarkDraft(), includesBrandMark: false).attribution == nil)
    }

    /// Where the switch starts, and what bulk export and Compress are given.
    @Test func freeUsersAreMarkedAndProIsNot() {
        #expect(ExportSheet.defaultIncludesBrandMark(allowsRemoval: false))
        #expect(!ExportSheet.defaultIncludesBrandMark(allowsRemoval: true))
        #expect(Watermark.freeExportMark(allowsRemoval: true) == nil)
        #expect(Watermark.freeExportMark(allowsRemoval: false)?.placement == .bottomLeft)
    }

    /// The export checks the entitlement again as it starts: a switch left
    /// off by someone whose subscription has since lapsed still marks.
    @Test func theExportChecksTheEntitlementAgain() {
        #expect(ExportSheet.brandMarkToExport(switchOn: true, allowsRemoval: true))
        #expect(!ExportSheet.brandMarkToExport(switchOn: false, allowsRemoval: true))
        #expect(ExportSheet.brandMarkToExport(switchOn: false, allowsRemoval: false))
        #expect(ExportSheet.brandMarkToExport(switchOn: true, allowsRemoval: false))
    }

    @Test func thePreviewSaysWhenTheMarkIsThere() {
        var draft = WatermarkDraft()
        #expect(draft.previewDescription(includesBrandMark: true) == L10n.exportWatermarkPreviewMarkOnly)
        draft.choose(.draft)
        let said = draft.previewDescription(includesBrandMark: true)
        #expect(said.contains(L10n.exportWatermarkDraft))
        #expect(said.contains(Brand.displayName))
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
        let composed = try #require(WatermarkPreview.draw(page.makeImage()!, layout: layout, marks: [mark]))
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

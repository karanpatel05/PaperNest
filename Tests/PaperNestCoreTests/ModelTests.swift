import CoreGraphics
import Foundation
import Testing
@testable import PaperNestCore

@Suite struct NameDeduplicatorTests {
    @Test func appendsTheNextFreeNumber() {
        #expect(NameDeduplicator.uniqueName("Receipt", existing: []) == "Receipt")
        #expect(NameDeduplicator.uniqueName("Receipt", existing: ["Receipt"]) == "Receipt 2")
        #expect(NameDeduplicator.uniqueName("Receipt", existing: ["Receipt", "Receipt 2"]) == "Receipt 3")
    }

    @Test func comparesIgnoringCaseAndAccents() {
        #expect(NameDeduplicator.uniqueName("Résumé", existing: ["resume"]) == "Résumé 2")
        #expect(NameDeduplicator.uniqueName("Año", existing: ["Ano"]) == "Año 2")
    }

    @Test func cleansControlCharactersAndEmptyNames() {
        #expect(NameDeduplicator.normalizedDisplayName("  Tax\u{0007} form \n") == "Tax form")
        #expect(NameDeduplicator.normalizedDisplayName("   ") == "Untitled")
    }
}

@Suite struct CodableRoundTripTests {
    @Test func pageObjectPayloadsRoundTrip() throws {
        let page = PageID.make()
        let objects = [
            PageObject(pageID: page, zKey: "V", payload: .ink(InkStroke(
                tool: .pen, color: RGBAColor(red: 0.1, green: 0.2, blue: 0.3), width: 2.5,
                points: [InkPoint(x: 1, y: 2, widthScale: 0.5, time: 0), InkPoint(x: 3, y: 4, widthScale: 0.7, time: 0.016)]
            )), modifiedAt: Date(timeIntervalSince1970: 1000)),
            PageObject(pageID: page, zKey: "k", payload: .text(TextBox(
                frame: CGRect(x: 10, y: 10, width: 200, height: 40), text: "Façade — ¿Qué tal? 1 234,56 €"
            )), modifiedAt: Date(timeIntervalSince1970: 1000)),
            PageObject(pageID: page, zKey: "s", payload: .image(PlacedImage(
                assetID: AssetID(sha256: String(repeating: "ab", count: 32)), frame: CGRect(x: 0, y: 0, width: 50, height: 50)
            )), modifiedAt: Date(timeIntervalSince1970: 1000)),
        ]
        let data = try JSONEncoder().encode(objects)
        #expect(try JSONDecoder().decode([PageObject].self, from: data) == objects)
    }

    @Test func pageRoundTripsWithAllContentKinds() throws {
        let item = ItemID.make()
        let asset = AssetID(sha256: String(repeating: "0f", count: 32))
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let pages = [
            Page(itemID: item, sortKey: "V", sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset, index: 3),
                 transform: PageTransform(crop: NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8), rotation: .clockwise90, filter: .blackAndWhite),
                 createdAt: date, modifiedAt: date),
            Page(itemID: item, sortKey: "k", sourceSize: CGSize(width: 500, height: 700), content: .image(asset), createdAt: date, modifiedAt: date),
            Page(itemID: item, sortKey: "s", sourceSize: CGSize(width: 612, height: 792), content: .template(.grid), createdAt: date, modifiedAt: date),
        ]
        #expect(try JSONDecoder().decode([Page].self, from: JSONEncoder().encode(pages)) == pages)
    }

    @Test func transformClampsAdjustments() {
        let t = PageTransform(brightness: 3, contrast: 0)
        #expect(t.brightness == 1)
        #expect(t.contrast == 0.25)
        #expect(t.needsPixelProcessing)
        #expect(!PageTransform.identity.needsPixelProcessing)
    }

    @Test func pdfRotateDegreesNormalize() {
        #expect(QuarterTurns(normalizingDegrees: -90) == .clockwise270)
        #expect(QuarterTurns(normalizingDegrees: 450) == .clockwise90)
        #expect(QuarterTurns(normalizingDegrees: 180) == .half)
    }

    @Test func retentionCutoffIsThirtyDaysBack() {
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        #expect(RetentionPolicy.purgeCutoff(now: now) == Date(timeIntervalSince1970: 70 * 86_400))
    }
}

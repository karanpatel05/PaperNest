import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import PDFKit
import Testing
import PaperNestCore
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestExport

/// A placed signature on the way out, read back from the exported file: a
/// signed form comes out flat with its answers and the signature drawn and
/// the original untouched; a password protects a signed copy without hiding
/// the signature; and on a cropped, turned page the signature lands where it
/// was placed on the page as shown.
@Suite struct SignedExportTests {
    private let password = "correct-horse"

    /// A thick zigzag, so it shows plainly in a picture of the page.
    private func signature() throws -> SavedSignature {
        try #require(SavedSignature(name: "Ana", capturing: [
            InkStroke(tool: .pen, color: .black, width: 10, points: [
                InkPoint(x: 0, y: 40), InkPoint(x: 50, y: 0), InkPoint(x: 100, y: 40), InkPoint(x: 150, y: 0),
                InkPoint(x: 200, y: 40),
            ]),
        ]))
    }

    /// A page of `document` drawn 2 pixels per point, white behind it.
    private func picture(_ document: PDFDocument) throws -> CGImage {
        let page = try #require(document.page(at: 0))
        let bounds = page.bounds(for: .cropBox)
        let turned = page.rotation % 180 != 0
        let size = turned ? CGSize(width: bounds.height * 2, height: bounds.width * 2) : CGSize(width: bounds.width * 2, height: bounds.height * 2)
        let image = page.thumbnail(of: size, for: .cropBox)
        return try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }

    /// Dark pixels in a rectangle given as shares of the picture, from the top-left.
    private func dark(_ image: CGImage, _ rect: NormalizedRect) -> Int {
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var count = 0
        for py in Int(rect.y * Double(height))..<Int((rect.y + rect.height) * Double(height)) {
            for px in Int(rect.x * Double(width))..<Int((rect.x + rect.width) * Double(width)) {
                let i = (py * width + px) * 4
                if buffer[i] < 90 && buffer[i + 1] < 90 && buffer[i + 2] < 90 { count += 1 }
            }
        }
        return count
    }

    private func fieldCount(_ data: Data) -> Int {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider),
              let catalog = document.catalog else { return 0 }
        var form: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(catalog, "AcroForm", &form), let form else { return 0 }
        var fields: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(form, "Fields", &fields), let fields else { return 0 }
        return CGPDFArrayGetCount(fields)
    }

    private let target = NormalizedRect(x: 0.5, y: 0.75, width: 0.35, height: 0.1)

    @Test func aSignedFormComesOutFlatWithItsAnswersAndTheOriginalUntouched() async throws {
        let fixture = try ExportFixture()
        let filled = try PDFForm.filled(SyntheticDocuments.acroFormPDF(fields: [.init(name: "customer")]),
                                        with: ["customer": .text("Ana Ruiz")])
        let item = try await fixture.importer.importItem(.data(filled, name: "Agreement"))
        let page = try await fixture.store.pages(of: item.id)[0]
        guard case .pdfPage(let asset, _) = page.content else { Issue.record("not a PDF page"); return }
        _ = try await fixture.store.placeSignature(try signature(), on: page, target: target)
        let signed = try await fixture.store.pages(of: item.id)

        #expect(try await fixture.exporter.formFieldFate(of: signed, options: ExportOptions(format: .pdf), password: nil) == .lost)
        let output = try await fixture.exporter.export(itemName: item.name, pages: signed,
                                                       options: ExportOptions(format: .pdf, paperSize: .original))
        defer { output.removeTemporaryFiles() }
        let data = try Data(contentsOf: output.files[0])

        #expect(fieldCount(data) == 0, "a drawn-on page kept fields it cannot honour")
        let document = try #require(PDFDocument(data: data))
        #expect(document.string?.contains("Ana Ruiz") == true, "the answer was not drawn on the page")
        let image = try picture(document)
        #expect(dark(image, target) > 400, "the signature is not where it was placed")
        #expect(dark(image, NormalizedRect(x: 0.05, y: 0.75, width: 0.35, height: 0.1)) == 0, "ink where nothing was placed")
        // The original is exactly as imported: its bytes still hash to its name.
        let original = try Data(contentsOf: fixture.store.assets.url(for: asset, kind: .pdf))
        #expect(original == filled)
        #expect(SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined() == asset.sha256)
    }

    @Test func aPasswordProtectsASignedCopyWithoutHidingTheSignature() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["Contract for three hours of work"])
        _ = try await fixture.store.placeSignature(try signature(), on: pages[0], target: target)
        let signed = try await fixture.store.pages(of: item.id)

        let output = try await fixture.exporter.export(itemName: item.name, pages: signed,
                                                       options: ExportOptions(format: .pdf, paperSize: .original),
                                                       password: password)
        defer { output.removeTemporaryFiles() }
        let data = try Data(contentsOf: output.files[0])

        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("/AESV2") || text.contains("/AESV3"), "not AES")
        let locked = try #require(PDFDocument(data: data))
        #expect(locked.isLocked && !locked.unlock(withPassword: "wrong"))
        let document = try #require(PDFDocument(data: data))
        #expect(document.unlock(withPassword: password))
        #expect(dark(try picture(document), target) > 400, "the signature is not in the protected copy")
    }

    /// Placed on the page as shown — cropped, then turned a quarter — the
    /// signature is exported there, not where the same numbers fall on the scan.
    @Test func aSignatureOnACroppedTurnedPageLandsWhereItWasPlaced() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["Lease agreement"])
        var transform = pages[0].transform
        transform.crop = NormalizedRect(x: 0.05, y: 0.1, width: 0.9, height: 0.8)
        transform.rotation = .clockwise90
        let turned = try await fixture.store.updateTransform(pages[0].id, to: transform)
        let corner = NormalizedRect(x: 0.08, y: 0.1, width: 0.35, height: 0.12)
        _ = try await fixture.store.placeSignature(try signature(), on: turned, target: corner)
        let signed = try await fixture.store.pages(of: item.id)

        let output = try await fixture.exporter.export(itemName: item.name, pages: signed,
                                                       options: ExportOptions(format: .pdf, paperSize: .original))
        defer { output.removeTemporaryFiles() }
        let image = try picture(try #require(PDFDocument(url: output.files[0])))

        #expect(image.width > image.height, "the page did not come out turned")
        #expect(dark(image, corner) > 300, "the signature is not in the corner it was placed in")
        let opposite = NormalizedRect(x: 1 - corner.x - corner.width, y: 1 - corner.y - corner.height,
                                      width: corner.width, height: corner.height)
        #expect(dark(image, opposite) == 0, "the signature landed in the opposite corner")
    }
}

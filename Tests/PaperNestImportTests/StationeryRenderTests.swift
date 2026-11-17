import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestStore
@testable import PaperNestRender

/// Each paper drawn by the renderer, as it is on screen and in exports.
@Suite struct StationeryRenderTests {
    private func picture(_ template: PageTemplate) async throws -> GrayPicture {
        let lib = try TestLibrary()
        let book = try await lib.store.createNotebook(named: template.rawValue, folderID: nil, template: template)
        let page = try #require(try await lib.store.pages(of: book.id).first)
        let image = try await lib.renderer.renderImage(page, pixelsPerPoint: 2)
        return try #require(DocumentComparer.gray(image))
    }

    @Test(arguments: PageTemplate.allCases)
    func everyPaperButBlankPrintsSomething(_ template: PageTemplate) async throws {
        let printed = try await picture(template).pixels.filter { $0 < 245 }.count
        if template == .blank { #expect(printed == 0) } else { #expect(printed > 500, "\(template): \(printed) pixels") }
    }

    /// A dot where the layout puts one (18, 18 points), and paper between dots.
    @Test func dottedPaperHasItsDotsWhereTheLayoutSays() async throws {
        let page = try await picture(.dotted)
        func shade(_ x: Int, _ y: Int) -> UInt8 { page.pixels[y * page.width + x] }
        #expect(shade(36, 36) < 230, "no dot at 18, 18")
        #expect(shade(54, 54) > 250, "a mark between dots")
    }

    /// Lined paper's first rule is where it always was: 72 points down.
    @Test func linedPaperStillStartsAt72Points() async throws {
        let page = try await picture(.lined)
        func rowIsRuled(_ y: Int) -> Bool { (0..<page.width).filter { page.pixels[y * page.width + $0] < 245 }.count > page.width / 2 }
        #expect(rowIsRuled(144))
        #expect(!rowIsRuled(130) && !rowIsRuled(100))
    }
}

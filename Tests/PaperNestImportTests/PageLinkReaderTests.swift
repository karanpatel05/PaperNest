import CoreGraphics
import Foundation
import PDFKit
import Testing
import PaperNestCore
import PaperNestImport
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestRender

/// Links inside a PDF, as the reader of a PaperNest document can follow them.
@Suite struct PageLinkReaderTests {
    private func library() -> (URL, LibraryStore)? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestLinks-\(UUID().uuidString)", isDirectory: true)
        return (try? LibraryStore(directory: url)).map { (url, $0) }
    }

    private func importing(_ data: Data, into store: LibraryStore) async throws -> [Page] {
        let item = try await DocumentImporter(store: store).importItem(.data(data, name: "Fixture"))
        return try await store.pages(of: item.id)
    }

    /// Three pages; page 1 links to page 3 and to the web, page 2 to page 1.
    private func linkedPDF(extra: (PDFPage) -> Void = { _ in }) throws -> Data {
        let document = try #require(PDFDocument(data: SyntheticDocuments.textPDF(pages: ["One", "Two", "Three"])))
        let first = try #require(document.page(at: 0)), second = try #require(document.page(at: 1))
        let third = try #require(document.page(at: 2))
        let toThird = PDFAnnotation(bounds: CGRect(x: 72, y: 500, width: 120, height: 20), forType: .link,
                                    withProperties: nil)
        toThird.destination = PDFDestination(page: third, at: CGPoint(x: 0, y: 792))
        first.addAnnotation(toThird)
        let web = PDFAnnotation(bounds: CGRect(x: 72, y: 600, width: 140, height: 22), forType: .link,
                                withProperties: nil)
        web.url = URL(string: "https://example.com/invoice")
        first.addAnnotation(web)
        let toFirst = PDFAnnotation(bounds: CGRect(x: 72, y: 500, width: 120, height: 20), forType: .link,
                                    withProperties: nil)
        toFirst.destination = PDFDestination(page: first, at: CGPoint(x: 0, y: 792))
        second.addAnnotation(toFirst)
        extra(first)
        return try #require(document.dataRepresentation())
    }

    @Test func aWebLinkComesBackWithItsAddressAndItsPlaceOnThePage() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let pages = try await importing(try linkedPDF(), into: store)

        let links = try await PageRenderer(store: store).links(on: pages[0], in: pages)

        let web = try #require(links.first { $0.target == .url(URL(string: "https://example.com/invoice")!) })
        // Drawn at x 72…212, y 600…622 from the bottom of a 612 × 792 sheet:
        // 170…192 from the top.
        #expect(abs(web.box.x - 72.0 / 612) < 1e-6 && abs(web.box.width - 140.0 / 612) < 1e-6)
        #expect(abs(web.box.y - 170.0 / 792) < 1e-6 && abs(web.box.height - 22.0 / 792) < 1e-6)
    }

    /// The fixture the iOS UI tests use, read here on the Mac: bytes written
    /// by hand, so a failure on one platform is that platform's reading.
    @Test func aPDFWrittenByHandYieldsBothOfItsLinks() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let pages = try await importing(SyntheticDocuments.handBuiltLinkedPDF(), into: store)
        #expect(pages.count == 3)

        let links = try await PageRenderer(store: store).links(on: pages[0], in: pages)

        #expect(Set(links.map(\.target)) == [.page(pages[2].id), .url(URL(string: "https://example.com/invoice")!)])
        let toThird = try #require(links.first { $0.target == .page(pages[2].id) })
        // x 72…232, y 500…530 from the bottom: 262…292 from the top.
        #expect(abs(toThird.box.x - 72.0 / 612) < 1e-6 && abs(toThird.box.width - 160.0 / 612) < 1e-6)
        #expect(abs(toThird.box.y - 262.0 / 792) < 1e-6 && abs(toThird.box.height - 30.0 / 792) < 1e-6)
        // And its text is real text.
        #expect(try await PageRenderer(store: store).textLayout(for: pages[2]).text == "Three")
    }

    @Test func anInternalLinkLeadsToThePageInThisDocument() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let pages = try await importing(try linkedPDF(), into: store)
        let renderer = PageRenderer(store: store)

        #expect(try await renderer.links(on: pages[0], in: pages).contains { $0.target == .page(pages[2].id) })
        #expect(try await renderer.links(on: pages[1], in: pages).map(\.target) == [.page(pages[0].id)])
        #expect(try await renderer.links(on: pages[2], in: pages).isEmpty)
    }

    /// The file says "page 3". After a reorder that is a different place in
    /// the document, and the link has to follow the page, not the number.
    @Test func anInternalLinkFollowsItsPageThroughAReorder() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let pages = try await importing(try linkedPDF(), into: store)
        let third = pages[2]
        // The reader sees the document back to front.
        let shown = Array(pages.reversed())

        let links = try await PageRenderer(store: store).links(on: pages[0], in: shown)

        #expect(links.contains { $0.target == .page(third.id) })
    }

    /// A link that leads to a page the reader deleted leads nowhere.
    @Test func anInternalLinkToADeletedPageIsDropped() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        var pages = try await importing(try linkedPDF(), into: store)
        let itemID = pages[0].itemID
        _ = try await store.deletePages([pages[2].id])
        pages = try await store.pages(of: itemID)

        let links = try await PageRenderer(store: store).links(on: pages[0], in: pages)

        #expect(links.map(\.target) == [.url(URL(string: "https://example.com/invoice")!)])
    }

    /// A document is not a trusted source of instructions: only the kinds of
    /// address a reader expects a PDF to open are made tappable.
    @Test func linksToAnythingButTheWebMailOrAPhoneAreNotOffered() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try linkedPDF { page in
            for (offset, address) in ["file:///etc/passwd", "javascript:alert(1)", "someapp://do/thing",
                                      "mailto:hello@example.com", "tel:+15550100"].enumerated() {
                let link = PDFAnnotation(bounds: CGRect(x: 300, y: 100 + offset * 30, width: 100, height: 20),
                                         forType: .link, withProperties: nil)
                link.url = URL(string: address)
                page.addAnnotation(link)
            }
        }
        let pages = try await importing(data, into: store)

        let addresses = try await PageRenderer(store: store).links(on: pages[0], in: pages).compactMap { link -> String? in
            if case .url(let url) = link.target { return url.absoluteString }
            return nil
        }

        #expect(Set(addresses) == ["https://example.com/invoice", "mailto:hello@example.com", "tel:+15550100"])
        #expect(PageLink.opens(URL(string: "HTTPS://EXAMPLE.COM")!))
        #expect(!PageLink.opens(URL(string: "file:///etc/passwd")!))
        #expect(!PageLink.opens(URL(string: "relative/path")!))
    }

    /// The reader cannot tap what a crop hides.
    @Test func aLinkHiddenByACropIsNotReturned() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        var pages = try await importing(try linkedPDF(), into: store)
        // Both links sit in the upper half; keep the lower.
        pages[0] = try await store.updateTransform(
            pages[0].id, to: PageTransform(crop: NormalizedRect(x: 0, y: 0.5, width: 1, height: 0.5)))

        #expect(try await PageRenderer(store: store).links(on: pages[0], in: pages).isEmpty)
    }

    @Test func aPageThatIsNotFromAPDFHasNoLinks() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let pages = try await importing(SyntheticDocuments.image(width: 800, height: 1000, type: .png), into: store)

        #expect(try await PageRenderer(store: store).links(on: pages[0], in: pages).isEmpty)
    }
}

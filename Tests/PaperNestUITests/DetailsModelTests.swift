import Foundation
import Testing
import PaperNestCore
import PaperNestImport
import PaperNestTestSupport
@testable import PaperNestUI

/// The review of a page's details: read, edited, saved, and shown again.
@MainActor @Suite(.serialized) struct DetailsModelTests {
    private func library() async throws -> (URL, LibrarySession) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestDetails-\(UUID())")
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        return (root, session)
    }

    @Test func aDigitalInvoiceIsReadEditedSavedAndShownAgain() async throws {
        let (root, session) = try await library()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try #require(session.environment?.store)
        let item = try await DocumentImporter(store: store).importItem(.data(SyntheticDocuments.textPDF(pages: [
            "Northwind Supplies Invoice No. A-17 Amount due 99.50 EUR"]), name: "Invoice"))
        let page = try #require(try await store.pages(of: item.id).first)
        let model = DetailsModel(itemID: item.id, pageID: page.id, session: session)

        await model.load()

        #expect(model.phase == .ready)
        #expect(model.kind == .invoice, "the page says it is an invoice")
        #expect(model.texts[.invoiceNumber] == "A-17")
        #expect(model.texts[.total] == "99.50 EUR")

        model.texts[.total] = "99.50 €"
        #expect(model.reviewed.values[.total] == DetailValue(text: "99.50 €", confidence: 1), "an edit is certain")
        #expect(await model.save())
        #expect(try await store.documentDetails(of: item.id)?.details[.total] == "99.50 €")

        let reopened = DetailsModel(itemID: item.id, pageID: page.id, session: session)
        await reopened.load()
        #expect(reopened.texts[.total] == "99.50 €", "the kept details, not a fresh reading")
        #expect(!reopened.isStale)
    }

    @Test func choosingAnotherKindReadsThePageForItsFields() async throws {
        let (root, session) = try await library()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try #require(session.environment?.store)
        let item = try await DocumentImporter(store: store).importItem(.data(SyntheticDocuments.textPDF(pages: [
            "Jo Smith jo@example.com"]), name: "Card"))
        let page = try #require(try await store.pages(of: item.id).first)
        let model = DetailsModel(itemID: item.id, pageID: page.id, session: session)
        await model.load()
        #expect(model.kind == .businessCard)
        #expect(model.texts[.email] == "jo@example.com")

        model.choose(.receipt)

        #expect(model.kind == .receipt)
        #expect(Set(model.texts.keys) == Set(DetailKind.receipt.fields))
    }

    /// A scan nobody has read has no text, and the review says so rather
    /// than reading it behind the person's back.
    @Test func aPageWithNoTextSaysSo() async throws {
        let (root, session) = try await library()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try #require(session.environment?.store)
        let item = try await DocumentImporter(store: store).importItem(.data(SyntheticDocuments.textImage(lines: ["TOTAL 6.00"]),
                                                                             name: "Scan"))
        let page = try #require(try await store.pages(of: item.id).first)
        let model = DetailsModel(itemID: item.id, pageID: page.id, session: session)

        await model.load()

        #expect(model.phase == .noText)
        #expect(try await store.recognition(for: page.id) == nil, "nothing was recognized to read it")
    }

    @Test func aGuessIsFlaggedUntilItIsEdited() async throws {
        let (root, session) = try await library()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try #require(session.environment?.store)
        let item = try await DocumentImporter(store: store).importItem(.data(SyntheticDocuments.textPDF(pages: [
            "Corner Cafe"]), name: "Receipt"))
        let page = try #require(try await store.pages(of: item.id).first)
        let model = DetailsModel(itemID: item.id, pageID: page.id, session: session)
        await model.load()
        model.choose(.receipt)
        #expect(model.texts[.merchant] == "Corner Cafe")
        #expect(model.needsCheck(.merchant))

        model.texts[.merchant] = "Corner Café"

        #expect(!model.needsCheck(.merchant))
    }
}

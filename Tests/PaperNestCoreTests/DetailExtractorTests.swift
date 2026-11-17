import Foundation
import Testing
@testable import PaperNestCore

/// Reading receipt, invoice and business-card details off a page's lines.
@Suite struct DetailExtractorTests {
    /// Lines down the page, one per row unless given an x; heights in points of an A4 page.
    private func line(_ text: String, row: Int, x: Double = 0.08, width: Double = 0.4, height: Double = 0.018,
                      confidence: Double = 1) -> CaptureLine {
        CaptureLine(text: text, box: .exact(x: x, y: 0.05 + Double(row) * 0.03, width: width, height: height),
                    confidence: confidence)
    }

    // MARK: - Rows

    /// Recognition often returns a label and its amount as two lines: they
    /// are one row, read left to right.
    @Test func aLabelAndItsAmountSideBySideAreOneRow() {
        let rows = DetailExtractor.rows([line("42.18", row: 3, x: 0.7, width: 0.2), line("TOTAL", row: 3),
                                         line("Thank you", row: 5)])
        #expect(rows.map(\.text) == ["TOTAL 42.18", "Thank you"])
    }

    // MARK: - Money

    @Test(arguments: [("42.18", "42.18", nil), ("42,18 €", "42.18", "€"), ("1,234.56", "1234.56", nil),
                      ("1.234,56", "1234.56", nil), ("1\u{00A0}234,56", "1234.56", nil), ("1 234,56 €", "1234.56", "€"),
                      ("EUR 42.18", "42.18", "EUR"), ("42.18 USD", "42.18", "USD"), ("$42.18", "42.18", "$")] as [(String, String, String?)])
    func everyWayOfWritingAnAmountIsReadExactly(_ written: String, _ value: String, _ currency: String?) throws {
        let money = try #require(DetailExtractor.amounts(in: "Total \(written)").first)
        #expect(money.value == Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")))
        #expect(money.currency == currency, "the currency as written, never inferred")
        #expect(money.text == written, "kept as read")
    }

    @Test func ratesDatesAndWholeNumbersAreNotAmounts() {
        #expect(DetailExtractor.amounts(in: "VAT 20.00 %").isEmpty)
        #expect(DetailExtractor.amounts(in: "Date 16.11.2026").isEmpty)
        #expect(DetailExtractor.amounts(in: "Table 12, 3 guests").isEmpty)
    }

    // MARK: - Dates

    @Test(arguments: [("2026-11-16", "2026-11-16"), ("16 Nov 2026", "2026-11-16"), ("Nov 16, 2026", "2026-11-16"),
                      ("16 novembre 2026", "2026-11-16"), ("3 de abril de 2026", "2026-04-03"), ("16/11/2026", "2026-11-16"),
                      ("11/16/2026", "2026-11-16"), ("05/05/26", "2026-05-05")])
    func aDateThatCanBeReadOneWayIsRead(_ written: String, _ iso: String) throws {
        let date = try #require(DetailExtractor.dates(in: "Date: \(written)").first)
        #expect(date.iso == iso)
        #expect(date.text.lowercased() == written.lowercased())
    }

    /// 03/04/2026 is March 4 or April 3 depending on where it was written:
    /// kept as written, unresolved, never decided by this phone's region.
    @Test func aDateThatCouldBeEitherIsKeptAsWritten() throws {
        let date = try #require(DetailExtractor.dates(in: "03/04/2026").first)
        #expect(date.text == "03/04/2026" && date.isAmbiguous)
    }

    // MARK: - A receipt

    private var receipt: [CaptureLine] {
        [line("ACME MARKET", row: 0, height: 0.03),
         line("12 Rue de la Paix", row: 1),
         line("16/11/2026 14:32", row: 2),
         line("Bread", row: 4), line("3.20", row: 4, x: 0.7, width: 0.15),
         line("Milk", row: 5), line("1.10", row: 5, x: 0.7, width: 0.15),
         line("Subtotal", row: 7), line("4.30", row: 7, x: 0.7, width: 0.15),
         line("TVA 5,5%", row: 8), line("0.24", row: 8, x: 0.7, width: 0.15),
         line("TOTAL TTC", row: 9), line("4.54 €", row: 9, x: 0.7, width: 0.15, confidence: 0.98)]
    }

    @Test func aReceiptsMerchantDateTotalTaxAndCurrency() throws {
        let details = DetailExtractor.extract(.receipt, from: receipt)

        #expect(details[.merchant] == "ACME MARKET")
        #expect(try #require(details.values[.merchant]).needsReview, "a heading is a guess, so it is flagged")
        #expect(details[.date] == "16/11/2026")
        #expect(try #require(details.values[.date]).needsReview == false)
        #expect(details[.total] == "4.54 €", "the labelled total, never the subtotal")
        #expect(try #require(details.values[.total]).needsReview == false)
        #expect(details[.tax] == "0.24")
        #expect(details[.currency] == "€")
        #expect(details.lineItems.isEmpty, "a receipt has no line items field")
    }

    /// With no "total" anywhere, the largest amount is offered, and flagged.
    @Test func anUnlabelledTotalIsTheLargestAmountAndFlagged() throws {
        let details = DetailExtractor.extract(.receipt, from: [line("Corner Cafe", row: 0), line("Latte 4.50", row: 1),
                                                                line("12.80", row: 3)])
        #expect(details[.total] == "12.80")
        #expect(try #require(details.values[.total]).needsReview)
        #expect(details.values[.currency] == nil, "no currency written, none given")
    }

    @Test func aFieldThatIsNotThereIsLeftEmpty() {
        let details = DetailExtractor.extract(.receipt, from: [line("Thank you for visiting", row: 0)])
        #expect(details.values[.total] == nil && details.values[.date] == nil && details.values[.tax] == nil)
    }

    /// A low recognition confidence carries into the value.
    @Test func aBadlyReadLineIsFlagged() throws {
        let details = DetailExtractor.extract(.receipt, from: [line("TOTAL", row: 0), line("9.99", row: 0, x: 0.7, confidence: 0.4)])
        #expect(try #require(details.values[.total]).needsReview)
    }

    // MARK: - An invoice

    @Test func anInvoicesSupplierNumberDatesTotalAndLineItems() throws {
        let invoice = [line("Northwind Supplies", row: 0, height: 0.03), line("Invoice No. INV-2026-0042", row: 1),
                       line("Date: 2026-11-02", row: 2), line("Due date: 2026-12-02", row: 3),
                       line("Consulting hours", row: 5), line("1,200.00", row: 5, x: 0.7, width: 0.2),
                       line("Travel", row: 6), line("340.50", row: 6, x: 0.7, width: 0.2),
                       line("Subtotal", row: 8), line("1,540.50", row: 8, x: 0.7, width: 0.2),
                       line("VAT 20%", row: 9), line("308.10", row: 9, x: 0.7, width: 0.2),
                       line("Amount due", row: 10), line("1,848.60 EUR", row: 10, x: 0.7, width: 0.2)]

        let details = DetailExtractor.extract(.invoice, from: invoice)

        #expect(details[.supplier] == "Northwind Supplies")
        #expect(details[.invoiceNumber] == "INV-2026-0042")
        #expect(details[.date] == "2026-11-02")
        #expect(details[.dueDate] == "2026-12-02")
        #expect(details[.total] == "1,848.60 EUR")
        #expect(details[.currency] == "EUR")
        #expect(details[.tax] == "308.10")
        #expect(details.lineItems.map(\.description) == ["Consulting hours", "Travel"])
        #expect(details.lineItems.map(\.amount) == ["1,200.00", "340.50"])
    }

    @Test func frenchAndSpanishInvoiceLabels() {
        let french = DetailExtractor.extract(.invoice, from: [line("Facture n° F-2026-17", row: 0),
                                                               line("Date d'échéance : 15/12/2026", row: 1),
                                                               line("Net à payer 1 234,56 €", row: 2)])
        #expect(french[.invoiceNumber] == "F-2026-17")
        #expect(french[.dueDate] == "15/12/2026")
        #expect(french[.total] == "1 234,56 €")
        let spanish = DetailExtractor.extract(.invoice, from: [line("Factura nº A-881", row: 0),
                                                                line("Fecha de vencimiento: 3 de abril de 2026", row: 1),
                                                                line("Total a pagar 87,40 €", row: 2)])
        #expect(spanish[.invoiceNumber] == "A-881")
        #expect(spanish[.dueDate] == "3 de abril de 2026")
        #expect(spanish[.total] == "87,40 €")
    }

    // MARK: - A business card

    @Test func aBusinessCardsContactDetails() throws {
        let card = [line("Camille Dupont", row: 0, height: 0.03), line("Directrice commerciale", row: 1),
                    line("Atelier Lumière SARL", row: 2), line("+33 1 42 68 53 00", row: 4),
                    line("camille.dupont@atelier-lumiere.fr", row: 5), line("www.atelier-lumiere.fr", row: 6)]

        let details = DetailExtractor.extract(.businessCard, from: card)

        #expect(details[.name] == "Camille Dupont")
        #expect(try #require(details.values[.name]).needsReview, "a name is a heuristic, flagged")
        #expect(details[.company] == "Atelier Lumière SARL")
        #expect(details[.phone].filter(\.isNumber) == "33142685300")
        #expect(details[.email] == "camille.dupont@atelier-lumiere.fr")
        #expect(details[.website] == "www.atelier-lumiere.fr")
    }

    @Test func theKindIsGuessedFromWhatThePageSays() {
        #expect(DetailExtractor.guessKind([line("INVOICE", row: 0), line("Total 10.00", row: 1)]) == .invoice)
        #expect(DetailExtractor.guessKind([line("Jo Smith", row: 0), line("jo@example.com", row: 1)]) == .businessCard)
        #expect(DetailExtractor.guessKind(receipt) == .receipt)
    }

    // MARK: - Written out

    @Test func aVCardEscapesAndFoldsAsTheStandardSays() {
        var details = CapturedDetails(kind: .businessCard)
        details.values[.name] = DetailValue(text: "Zoë Ångström", confidence: 1)
        details.values[.company] = DetailValue(text: "Smith, Jones; Partners", confidence: 1)
        details.values[.address] = DetailValue(text: "Résidence Les Érables, 1 234 avenue de la République Française, 75011 Paris", confidence: 1)

        let card = DetailFormats.vCard(details)

        #expect(card.hasPrefix("BEGIN:VCARD\r\nVERSION:3.0\r\n"))
        #expect(card.hasSuffix("END:VCARD\r\n"))
        #expect(card.contains("N:Ångström;Zoë;;;\r\n"))
        #expect(card.contains("FN:Zoë Ångström\r\n"))
        #expect(card.contains("ORG:Smith\\, Jones\\; Partners\r\n"))
        // Folded lines are at most 75 octets and unfold back to the address, accents whole.
        let physical = card.components(separatedBy: "\r\n")
        #expect(physical.allSatisfy { $0.utf8.count <= 75 })
        let unfolded = card.replacingOccurrences(of: "\r\n ", with: "")
        #expect(unfolded.contains("ADR;TYPE=WORK:;;Résidence Les Érables\\, 1 234 avenue de la République Française\\, 75011 Paris;;;;"))
    }

    @Test func aCSVQuotesWhatNeedsQuotingAndListsLineItems() {
        var details = CapturedDetails(kind: .invoice)
        details.values[.supplier] = DetailValue(text: "Smith, Jones \"&\" Co", confidence: 1)
        details.values[.total] = DetailValue(text: "1 234,56 €", confidence: 1)
        details.lineItems = [LineItem(description: "Design, phase 1", amount: "1 000,00 €")]

        let csv = DetailFormats.csv(details, label: { $0.rawValue }, itemHeaders: ("Description", "Amount"))
        let lines = csv.components(separatedBy: "\r\n")

        #expect(lines[0] == "supplier,invoiceNumber,date,dueDate,total,tax,currency")
        #expect(lines[1] == "\"Smith, Jones \"\"&\"\" Co\",,,,1 234,56 €,,".replacingOccurrences(of: "1 234,56 €", with: "\"1 234,56 €\""))
        #expect(lines[3] == "Description,Amount")
        #expect(lines[4] == "\"Design, phase 1\",\"1 000,00 €\"")
    }
}

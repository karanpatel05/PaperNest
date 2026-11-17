import CoreGraphics
import Foundation

/// What a page is, for reading details off it.
public enum DetailKind: String, Codable, CaseIterable, Sendable {
    case receipt, businessCard, invoice

    /// The fields a page of this kind is read for, in the order they are shown.
    public var fields: [DetailField] {
        switch self {
        case .receipt: [.merchant, .date, .total, .tax, .currency]
        case .businessCard: [.name, .company, .phone, .email, .address, .website]
        case .invoice: [.supplier, .invoiceNumber, .date, .dueDate, .total, .tax, .currency]
        }
    }
}

public enum DetailField: String, Codable, CaseIterable, Sendable, CodingKeyRepresentable {
    case merchant, date, total, tax, currency
    case name, company, phone, email, address, website
    case supplier, invoiceNumber, dueDate
}

/// A value read off a page, as it was written there: an amount is kept as
/// read ("1 234,56 €"), never reformatted or converted, and a date that could
/// be read two ways is kept as written and flagged rather than given an order.
public struct DetailValue: Hashable, Codable, Sendable {
    public var text: String
    /// How far the reading can be trusted, from 0 to 1: the line's recognition
    /// confidence (1 for a PDF's own text) times how strong the rule that
    /// found it was. Edited by hand, it is 1.
    public var confidence: Double
    /// Where it was read, in the page's upright, uncropped source space.
    public var box: NormalizedRect?

    public init(text: String, confidence: Double, box: NormalizedRect? = nil) {
        self.text = text
        self.confidence = confidence
        self.box = box
    }

    /// Below this, the review asks for the value to be checked.
    public static let reviewThreshold = 0.6
    public var needsReview: Bool { confidence < Self.reviewThreshold }
}

/// One row of an invoice: what it is and what it costs, as read.
public struct LineItem: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var description: String
    public var amount: String

    public init(id: UUID = UUID(), description: String, amount: String) {
        self.id = id
        self.description = description
        self.amount = amount
    }
}

/// The details read off one page, for a person to review before saving.
/// A field that was not found is absent: nothing here is a guess dressed as
/// a reading.
public struct CapturedDetails: Hashable, Codable, Sendable {
    public var kind: DetailKind
    public var values: [DetailField: DetailValue]
    /// An invoice's rows. Always to be checked: they are read from layout.
    public var lineItems: [LineItem]

    public init(kind: DetailKind, values: [DetailField: DetailValue] = [:], lineItems: [LineItem] = []) {
        self.kind = kind
        self.values = values
        self.lineItems = lineItems
    }

    public subscript(field: DetailField) -> String {
        values[field]?.text ?? ""
    }
}

/// A line of a page's text and where it is: recognized (with Vision's
/// confidence) or the PDF's own (confidence 1).
public struct CaptureLine: Hashable, Sendable {
    public var text: String
    public var box: NormalizedRect
    public var confidence: Double

    public init(text: String, box: NormalizedRect, confidence: Double = 1) {
        self.text = text
        self.box = box
        self.confidence = confidence
    }
}

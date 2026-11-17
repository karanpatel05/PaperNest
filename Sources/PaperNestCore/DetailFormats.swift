import Foundation

/// Reviewed details written out for other apps: a business card as a vCard
/// someone can add to Contacts from the share sheet, a receipt or invoice as
/// CSV a spreadsheet opens.
public enum DetailFormats {
    // MARK: - vCard 3.0

    /// RFC 2426: CRLF line endings, `\`, `,`, `;` and line breaks escaped,
    /// and lines folded at 75 octets without splitting a character.
    public static func vCard(_ details: CapturedDetails) -> String {
        let name = details[.name].trimmingCharacters(in: .whitespaces)
        let parts = name.split(separator: " ").map(String.init)
        let family = parts.count > 1 ? parts.last! : name
        let given = parts.count > 1 ? parts.dropLast().joined(separator: " ") : ""
        var lines = ["BEGIN:VCARD", "VERSION:3.0",
                     "N:\(escape(family));\(escape(given));;;",
                     "FN:\(escape(name.isEmpty ? details[.company] : name))"]
        if !details[.company].isEmpty { lines.append("ORG:\(escape(details[.company]))") }
        if !details[.phone].isEmpty { lines.append("TEL;TYPE=WORK,VOICE:\(escape(details[.phone]))") }
        if !details[.email].isEmpty { lines.append("EMAIL;TYPE=INTERNET:\(escape(details[.email]))") }
        if !details[.address].isEmpty { lines.append("ADR;TYPE=WORK:;;\(escape(details[.address]));;;;") }
        if !details[.website].isEmpty { lines.append("URL:\(escape(details[.website]))") }
        lines.append("END:VCARD")
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Splits a line longer than 75 octets, each continuation starting with a space.
    static func fold(_ line: String) -> String {
        var result = "", current = 0
        for character in line {
            let size = String(character).utf8.count
            if current + size > 75 {
                result += "\r\n "
                current = 1
            }
            result.append(character)
            current += size
        }
        return result
    }

    // MARK: - CSV

    /// RFC 4180: a header of the kind's fields (named by `label`) and one row
    /// of their values; an invoice's line items follow under their own header.
    /// Values go out as read: an amount keeps its separators and currency.
    public static func csv(_ details: CapturedDetails, label: (DetailField) -> String,
                           itemHeaders: (description: String, amount: String)) -> String {
        let fields = details.kind.fields
        var rows = [fields.map(label), fields.map { details[$0] }]
        if !details.lineItems.isEmpty {
            rows.append([])
            rows.append([itemHeaders.description, itemHeaders.amount])
            rows += details.lineItems.map { [$0.description, $0.amount] }
        }
        return rows.map { $0.map(quote).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    static func quote(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

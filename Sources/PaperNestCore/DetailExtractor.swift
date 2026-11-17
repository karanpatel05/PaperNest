import CoreGraphics
import Foundation

/// Reads receipt, business-card and invoice details off a page's text, on
/// the device. Rules, not a model: every value says how strong the rule that
/// found it was, and nothing is filled in when no rule finds it.
///
/// Lines are first gathered into **rows**: a receipt's "TOTAL" and "42.18"
/// often come back from recognition as two lines side by side, and a label
/// is only any use next to its value.
public enum DetailExtractor {
    // MARK: - Rows

    /// Lines side by side on the page, read left to right.
    public struct Row: Hashable, Sendable {
        public var lines: [CaptureLine]
        public var text: String { lines.map(\.text).joined(separator: " ") }
        public var confidence: Double { lines.map(\.confidence).min() ?? 0 }
        public var box: NormalizedRect {
            lines.dropFirst().reduce(lines[0].box) { $0.union($1.box) }
        }
    }

    /// Lines whose boxes overlap vertically by at least half the shorter
    /// one's height are one row; rows run top to bottom.
    public static func rows(_ lines: [CaptureLine]) -> [Row] {
        let sorted = lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { ($0.box.y, $0.box.x) < ($1.box.y, $1.box.x) }
        var rows: [Row] = []
        for line in sorted {
            if let last = rows.indices.last {
                let row = rows[last].box
                let overlap = min(row.y + row.height, line.box.y + line.box.height) - max(row.y, line.box.y)
                if overlap >= 0.5 * min(row.height, line.box.height) {
                    rows[last].lines.append(line)
                    rows[last].lines.sort { $0.box.x < $1.box.x }
                    continue
                }
            }
            rows.append(Row(lines: [line]))
        }
        return rows
    }

    // MARK: - Money

    public struct Money: Hashable, Sendable {
        /// As read, currency and all.
        public var text: String
        /// The amount, from the digits as read: the decimal separator is the
        /// last "." or "," followed by exactly two digits.
        public var value: Decimal
        /// The symbol or code as written ("$", "€", "EUR"); never inferred.
        public var currency: String?
    }

    private static let currencyCodes = "USD|EUR|GBP|CAD|AUD|CHF|JPY|MXN|NZD|SEK|NOK|DKK"

    /// Amounts with two decimals, in any of the ways they are written:
    /// 42.18, 42,18 €, 1,234.56, 1.234,56, 1 234,56, EUR 42.18, 42.18 USD.
    /// A number followed by "%" is a rate, not an amount.
    public static func amounts(in text: String) -> [Money] {
        // Not inside a longer number or a date (16.11.2026 has no amount in it). A minus
        // (- or −) before the currency or the digits, or accounting parentheses, keep the sign.
        let pattern = #"(?<open>\()?(?<sign>[-\x{2212}])?(?<pre>[$€£¥]|\b(?:"# + currencyCodes + #")\b)?[ \x{00A0}]?(?<sign2>[-\x{2212}])?(?<!\d)(?<!\d[.,/\-])(?<num>\d{1,3}(?:[ \x{00A0}\x{202F}.,]\d{3})+[.,]\d{2}|\d+[.,]\d{2})(?![.,/\-]?\d)(?!\s?%)(?:[ \x{00A0}]?(?<post>[$€£¥]|\b(?:"# + currencyCodes + #")\b))?(?<close>\))?"#
        guard let regex = regex(pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            func group(_ name: String) -> String? {
                let range = match.range(withName: name)
                return range.location == NSNotFound ? nil : ns.substring(with: range)
            }
            guard let digits = group("num") else { return nil }
            let separator = digits[digits.index(digits.endIndex, offsetBy: -3)]
            let whole = digits.dropLast(3).filter(\.isNumber)
            let cents = digits.suffix(2)
            guard separator == "." || separator == ",",
                  let magnitude = Decimal(string: "\(whole).\(cents)", locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            // A refund, a credit note, a discount: the sign is part of what was read.
            let negative = group("sign") != nil || group("sign2") != nil || (group("open") != nil && group("close") != nil)
            var text = ns.substring(with: match.range).trimmingCharacters(in: .whitespaces)
            // A lone bracket belongs to the sentence around the amount, not to it.
            if group("open") != nil, group("close") == nil { text.removeFirst() }
            if group("close") != nil, group("open") == nil { text.removeLast() }
            return Money(text: text.trimmingCharacters(in: .whitespaces), value: negative ? -magnitude : magnitude,
                         currency: group("pre") ?? group("post"))
        }
    }

    // MARK: - Dates

    public struct ReadDate: Hashable, Sendable {
        /// As written on the page.
        public var text: String
        /// "yyyy-MM-dd" when the date can only be read one way.
        public var iso: String?
        public var isAmbiguous: Bool { iso == nil }
    }

    private static let months: [(String, Int)] = [
        ("january", 1), ("jan", 1), ("janvier", 1), ("janv", 1), ("enero", 1), ("ene", 1),
        ("february", 2), ("feb", 2), ("fevrier", 2), ("fevr", 2), ("fev", 2), ("febrero", 2),
        ("march", 3), ("mar", 3), ("mars", 3), ("marzo", 3),
        ("april", 4), ("apr", 4), ("avril", 4), ("avr", 4), ("abril", 4), ("abr", 4),
        ("may", 5), ("mai", 5), ("mayo", 5),
        ("june", 6), ("jun", 6), ("juin", 6), ("junio", 6),
        ("july", 7), ("jul", 7), ("juillet", 7), ("juil", 7), ("julio", 7),
        ("august", 8), ("aug", 8), ("aout", 8), ("agosto", 8), ("ago", 8),
        ("september", 9), ("sept", 9), ("sep", 9), ("septembre", 9), ("septiembre", 9),
        ("october", 10), ("oct", 10), ("octobre", 10), ("octubre", 10),
        ("november", 11), ("nov", 11), ("novembre", 11), ("noviembre", 11),
        ("december", 12), ("dec", 12), ("decembre", 12), ("diciembre", 12), ("dic", 12),
    ]

    /// Dates in reading order. Parsed by these patterns, never by the
    /// device's locale: a French receipt's 03/04/2026 read on a phone set to
    /// the US must not silently become March 4. When both numbers of a
    /// numeric date could be the month, it is kept as written, unresolved.
    public static func dates(in text: String) -> [ReadDate] {
        let folded = fold(text)
        let monthNames = months.map(\.0).sorted { $0.count > $1.count }.joined(separator: "|")
        let patterns: [(String, (NSTextCheckingResult, NSString) -> String?)] = [
            (#"\b(\d{4})-(\d{2})-(\d{2})\b"#, { m, s in iso(Int(s.substring(with: m.range(at: 1))), Int(s.substring(with: m.range(at: 2))), Int(s.substring(with: m.range(at: 3)))) }),
            (#"\b(\d{1,2})(?:er)?\s+(?:de\s+)?("# + monthNames + #")\.?\s+(?:de\s+)?(\d{4})\b"#, { m, s in iso(Int(s.substring(with: m.range(at: 3))), month(s.substring(with: m.range(at: 2))), Int(s.substring(with: m.range(at: 1)))) }),
            (#"\b("# + monthNames + #")\.?\s+(\d{1,2}),?\s+(\d{4})\b"#, { m, s in iso(Int(s.substring(with: m.range(at: 3))), month(s.substring(with: m.range(at: 1))), Int(s.substring(with: m.range(at: 2)))) }),
            (#"\b(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4}|\d{2})\b"#, { m, s in
                let a = Int(s.substring(with: m.range(at: 1))) ?? 0, b = Int(s.substring(with: m.range(at: 2))) ?? 0
                var y = Int(s.substring(with: m.range(at: 3))) ?? 0
                if y < 100 { y += 2000 }
                if a > 12 && b <= 12 { return iso(y, b, a) }      // day first
                if b > 12 && a <= 12 { return iso(y, a, b) }      // month first
                if a == b { return iso(y, a, b) }
                return nil                                        // could be either
            }),
        ]
        var found: [(location: Int, date: ReadDate)] = []
        var taken = IndexSet()
        let ns = folded as NSString, original = text as NSString
        for (pattern, resolve) in patterns {
            guard let regex = regex(pattern) else { continue }
            for match in regex.matches(in: folded, range: NSRange(location: 0, length: ns.length)) {
                let range = match.range
                guard !taken.intersects(integersIn: range.location..<(range.location + range.length)) else { continue }
                // A numeric date that matched no rule is still a date, unresolved.
                let resolved = resolve(match, ns)
                let isNumeric = pattern.hasPrefix(#"\b(\d{1,2})[/"#)
                guard resolved != nil || isNumeric else { continue }
                taken.insert(integersIn: range.location..<(range.location + range.length))
                // Folding kept every character in place unless the lengths differ.
                let written = original.length == ns.length ? original.substring(with: range) : ns.substring(with: range)
                found.append((range.location, ReadDate(text: written, iso: resolved)))
            }
        }
        return found.sorted { $0.location < $1.location }.map(\.date)
    }

    private static func month(_ name: String) -> Int? { months.first { $0.0 == name }?.1 }

    private static func iso(_ year: Int?, _ month: Int?, _ day: Int?) -> String? {
        guard let year, let month, let day, (1...12).contains(month), (1...31).contains(day), (1900...2200).contains(year) else { return nil }
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components), calendar.component(.day, from: date) == day else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    // MARK: - Words

    /// Case and accents removed, for matching labels.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
    }

    /// Whether `text` holds any of `phrases` as whole words: one pattern per
    /// list, compiled once.
    static func contains(_ text: String, any phrases: [String]) -> Bool {
        let pattern = #"(?<![\p{L}\p{N}])(?:"# + phrases.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
            + #")(?![\p{L}\p{N}])"#
        guard let regex = regex(pattern) else { return false }
        let folded = fold(text) as NSString
        return regex.firstMatch(in: folded as String, range: NSRange(location: 0, length: folded.length)) != nil
    }

    // MARK: - Compiled once

    /// Every pattern here is compiled the first time it is needed and kept:
    /// compiling them on every call made an 80-line invoice take over a
    /// second. `NSRegularExpression` is immutable and safe to share.
    private final class Compiled: @unchecked Sendable {
        private let lock = NSLock()
        private var patterns: [String: NSRegularExpression] = [:]

        func regex(_ pattern: String, _ options: NSRegularExpression.Options) -> NSRegularExpression? {
            let key = "\(options.rawValue)|\(pattern)"
            lock.lock(); defer { lock.unlock() }
            if let compiled = patterns[key] { return compiled }
            guard let compiled = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
            patterns[key] = compiled
            return compiled
        }
    }

    private static let compiled = Compiled()

    static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        compiled.regex(pattern, options)
    }

    /// Phone numbers, links and postal addresses; never dates.
    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType([.phoneNumber, .link, .address]).rawValue)

    static let strongTotal = ["grand total", "total ttc", "total a payer", "net a payer", "montant total", "amount due",
                              "balance due", "total due", "total a pagar", "importe total", "total amount"]
    static let total = strongTotal + ["total", "importe", "a payer", "montant"]
    static let notTotal = ["subtotal", "sub-total", "sub total", "sous-total", "sous total", "total ht", "total hors taxes",
                           "base imponible"]
    static let tax = ["tax", "taxes", "sales tax", "vat", "tva", "iva", "gst", "hst", "pst", "taxe", "impuesto", "impuestos"]
    static let invoiceWords = ["invoice", "facture", "factura"]
    static let dueWords = ["due date", "payment due", "due", "echeance", "date d'echeance", "date limite", "a payer avant",
                           "vencimiento", "fecha de vencimiento", "fecha limite"]
    static let companySuffixes = ["inc", "inc.", "llc", "ltd", "ltd.", "limited", "gmbh", "corp", "corp.", "corporation",
                                  "company", "co.", "sarl", "sas", "s.a.", "sa", "s.l.", "sl", "plc", "ag", "bv", "studio"]
    static let titleWords = ["manager", "director", "engineer", "designer", "president", "ceo", "cto", "cfo", "founder",
                             "consultant", "officer", "developer", "directeur", "directrice", "ingenieur", "gerant",
                             "responsable", "director general", "gerente", "ingeniero", "disenador", "fondateur", "fundador",
                             "sales", "marketing", "head of", "lead", "vp", "partner", "associate"]

    // MARK: - Which kind

    /// A first guess the review lets someone change: an invoice says so; a
    /// card has an email or a phone number and no amounts; anything else is
    /// a receipt.
    public static func guessKind(_ lines: [CaptureLine]) -> DetailKind {
        let text = lines.map(\.text).joined(separator: "\n")
        if contains(text, any: invoiceWords) { return .invoice }
        let detected = detected(in: text)
        if (detected.email != nil || detected.phone != nil) && amounts(in: text).isEmpty { return .businessCard }
        return .receipt
    }

    // MARK: - Reading

    public static func extract(_ kind: DetailKind, from lines: [CaptureLine]) -> CapturedDetails {
        let rows = rows(lines)
        var details = CapturedDetails(kind: kind)
        switch kind {
        case .receipt:
            details.values[.merchant] = heading(rows)
            details.values[.date] = firstDate(rows, avoiding: dueWords)
            readMoney(rows, into: &details)
        case .invoice:
            details.values[.supplier] = heading(rows)
            details.values[.invoiceNumber] = invoiceNumber(rows)
            details.values[.date] = firstDate(rows, avoiding: dueWords)
            details.values[.dueDate] = labelledDate(rows, labels: dueWords)
            readMoney(rows, into: &details)
            details.lineItems = lineItems(rows)
        case .businessCard:
            readCard(rows, into: &details)
        }
        return details
    }

    private static func value(_ text: String, _ row: Row, strength: Double) -> DetailValue {
        DetailValue(text: text, confidence: row.confidence * strength, box: row.box)
    }

    /// The total, the tax and the currency. A total comes from a row labelled
    /// as one (strong labels like "Total TTC" or "Amount due" first, the last
    /// such row otherwise); with no label, the largest amount, flagged.
    private static func readMoney(_ rows: [Row], into details: inout CapturedDetails) {
        func amountsOn(_ index: Int) -> [Money] {
            let here = amounts(in: rows[index].text)
            if !here.isEmpty || index + 1 >= rows.count { return here }
            return amounts(in: rows[index + 1].text)   // the label on one row, the amount under it
        }
        let labelled = rows.indices.filter { contains(rows[$0].text, any: total) && !contains(rows[$0].text, any: notTotal) }
        let strong = labelled.filter { contains(rows[$0].text, any: strongTotal) }
        var totalMoney: Money?
        if let index = (strong.last ?? labelled.last), let money = amountsOn(index).last {
            totalMoney = money
            details.values[.total] = value(money.text, rows[index], strength: strong.isEmpty ? 0.85 : 0.95)
        } else if let (index, money) = rows.indices.flatMap({ i in amounts(in: rows[i].text).map { (i, $0) } })
            .max(by: { $0.1.value < $1.1.value }) {
            totalMoney = money
            details.values[.total] = value(money.text, rows[index], strength: 0.4)
        }
        if let index = rows.indices.last(where: { contains(rows[$0].text, any: tax) && !contains(rows[$0].text, any: total) }),
           let money = amounts(in: rows[index].text).last {
            details.values[.tax] = value(money.text, rows[index], strength: 0.85)
        }
        if let currency = totalMoney?.currency, let total = details.values[.total] {
            details.values[.currency] = DetailValue(text: currency, confidence: total.confidence, box: total.box)
        } else {
            let written = rows.flatMap { row in amounts(in: row.text).compactMap { money in money.currency.map { ($0, row) } } }
            if let (currency, row) = written.first, Set(written.map(\.0)).count == 1 {
                details.values[.currency] = value(currency, row, strength: 0.7)
            }
        }
    }

    /// The name at the top: among the first rows, the tallest one with words
    /// and no amount, date or contact detail. A heuristic, so it is flagged.
    private static func heading(_ rows: [Row]) -> DetailValue? {
        let candidates = rows.prefix(max(3, rows.count / 3)).filter { row in
            let text = row.text
            return text.filter(\.isLetter).count >= 2 && amounts(in: text).isEmpty && dates(in: text).isEmpty
                && detected(in: text).isEmpty && !contains(text, any: invoiceWords + total + tax)
        }
        guard let best = candidates.max(by: { $0.box.height < $1.box.height }) else { return nil }
        return value(best.text.trimmingCharacters(in: .whitespaces), best, strength: 0.55)
    }

    private static func firstDate(_ rows: [Row], avoiding labels: [String]) -> DetailValue? {
        for row in rows where !contains(row.text, any: labels) {
            if let date = dates(in: row.text).first {
                return value(date.text, row, strength: date.isAmbiguous ? 0.5 : 0.85)
            }
        }
        return nil
    }

    private static func labelledDate(_ rows: [Row], labels: [String]) -> DetailValue? {
        for (index, row) in rows.enumerated() where contains(row.text, any: labels) {
            let date = dates(in: row.text).first ?? (index + 1 < rows.count ? dates(in: rows[index + 1].text).first : nil)
            if let date { return value(date.text, row, strength: date.isAmbiguous ? 0.5 : 0.9) }
        }
        return nil
    }

    private static func invoiceNumber(_ rows: [Row]) -> DetailValue? {
        let pattern = #"(?:invoice|facture|factura)\s*(?:no\.?|number|num(?:ero|\.)?|n[°º.]?|#)?\s*(?:de\s+facture\s*)?[:#]?\s*([A-Z0-9][A-Z0-9\-/]*\d[A-Z0-9\-/]*)"#
        guard let regex = regex(pattern, .caseInsensitive) else { return nil }
        for row in rows {
            let text = row.text, ns = text as NSString
            if let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                return value(ns.substring(with: match.range(at: 1)), row, strength: 0.9)
            }
        }
        return nil
    }

    /// Rows between the heading and the totals that end in an amount and say
    /// what it is for. Read from layout, so every one is to be checked.
    private static func lineItems(_ rows: [Row]) -> [LineItem] {
        let stop = rows.firstIndex { contains($0.text, any: total + notTotal + tax) } ?? rows.count
        return rows.prefix(stop).compactMap { row -> LineItem? in
            let text = row.text
            guard let money = amounts(in: text).last, !contains(text, any: invoiceWords + dueWords),
                  dates(in: text).isEmpty else { return nil }
            var description = text.replacingOccurrences(of: money.text, with: "")
            for other in amounts(in: description) { description = description.replacingOccurrences(of: other.text, with: "") }
            description = description.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard description.filter(\.isLetter).count >= 2 else { return nil }
            return LineItem(description: description, amount: money.text)
        }
    }

    // MARK: - Business cards

    struct Detected {
        var phone: String?
        var email: String?
        var website: String?
        var address: String?
        var isEmpty: Bool { phone == nil && email == nil && website == nil && address == nil }
    }

    /// Phone numbers, email and web addresses, and postal addresses, by the
    /// system's data detectors. Dates are deliberately not asked for: they
    /// would be read in the device's locale.
    static func detected(in text: String) -> Detected {
        var found = Detected()
        let ns = text as NSString
        if let email = regex(#"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#, .caseInsensitive)?
            .firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            found.email = ns.substring(with: email.range)
        }
        guard let detector = Self.detector else { return found }
        for match in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let written = ns.substring(with: match.range)
            switch match.resultType {
            case .phoneNumber where found.phone == nil: found.phone = match.phoneNumber ?? written
            case .link where match.url?.scheme?.hasPrefix("http") == true && found.website == nil && !written.contains("@"):
                found.website = written
            case .address where found.address == nil: found.address = written
            default: break
            }
        }
        return found
    }

    private static func readCard(_ rows: [Row], into details: inout CapturedDetails) {
        for row in rows {
            let found = detected(in: row.text)
            if details.values[.phone] == nil, let phone = found.phone { details.values[.phone] = value(phone, row, strength: 0.85) }
            if details.values[.email] == nil, let email = found.email { details.values[.email] = value(email, row, strength: 0.9) }
            if details.values[.website] == nil, let site = found.website { details.values[.website] = value(site, row, strength: 0.85) }
        }
        // An address can run over several rows: the detector reads the card's text whole.
        let whole = rows.map(\.text).joined(separator: "\n")
        if let address = detected(in: whole).address {
            let rowsInIt = rows.filter { address.contains($0.text) }
            let confidence = (rowsInIt.map(\.confidence).min() ?? rows.map(\.confidence).min() ?? 1) * 0.75
            let box = rowsInIt.first.map { first in rowsInIt.dropFirst().reduce(first.box) { $0.union($1.box) } }
            details.values[.address] = DetailValue(text: address.replacingOccurrences(of: "\n", with: ", "),
                                                   confidence: confidence, box: box)
        }
        func isPlainWords(_ text: String) -> Bool {
            text.filter(\.isNumber).isEmpty && !text.contains("@") && detected(in: text).isEmpty
        }
        if let company = rows.first(where: { isPlainWords($0.text) && contains($0.text, any: companySuffixes) }) {
            details.values[.company] = value(company.text, company, strength: 0.75)
        }
        // A name: two to four words, each capitalized, no company or job title word.
        let name = rows.filter { row in
            let words = row.text.split(separator: " ")
            return isPlainWords(row.text) && (2...4).contains(words.count)
                && words.allSatisfy { $0.first?.isUppercase == true }
                && !contains(row.text, any: companySuffixes + titleWords) && row.text != details.values[.company]?.text
        }.max { $0.box.height < $1.box.height }
        if let name { details.values[.name] = value(name.text, name, strength: 0.55) }
    }
}

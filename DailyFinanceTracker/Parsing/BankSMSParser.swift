import Foundation

/// The transaction details pulled out of a bank SMS.
struct ParsedSMS: Equatable {
    var amount: Double
    var kind: TransactionKind
    var merchant: String
    var category: SpendingCategory
    var bank: String?
    var accountLast4: String?
    var referenceNumber: String?
    /// When the transaction happened. Uses the date printed in the SMS when there is one,
    /// otherwise the moment the SMS was processed.
    var date: Date
}

/// Turns Indian bank / card / UPI alert SMS into structured transactions.
///
/// Bank SMS formats vary a lot, so this is a set of tolerant heuristics rather than
/// one strict grammar per bank. Anything that doesn't look like a completed debit or
/// credit (OTPs, offers, due reminders, failed payments) is rejected.
enum BankSMSParser {

    static func parse(_ raw: String, now: Date = .now, calendar: Calendar = .current) -> ParsedSMS? {
        let text = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.range(of: ignorePattern, options: .regularExpression) == nil else {
            return nil
        }
        guard let kind = detectKind(in: text), let amount = detectAmount(in: text), amount > 0 else {
            return nil
        }

        let isCashWithdrawal = kind == .debit
            && text.range(of: "(?i)\\b(atm|cash withdrawal|withdrawn)\\b", options: .regularExpression) != nil

        let merchant: String
        if isCashWithdrawal {
            merchant = "ATM Withdrawal"
        } else {
            merchant = detectMerchant(in: text, kind: kind) ?? (kind == .debit ? "Bank Debit" : "Bank Credit")
        }

        let category: SpendingCategory = isCashWithdrawal
            ? .cash
            : CategoryClassifier.classify(merchant: merchant, kind: kind)

        return ParsedSMS(
            amount: amount,
            kind: kind,
            merchant: merchant,
            category: category,
            bank: detectBank(in: text),
            accountLast4: detectAccount(in: text),
            referenceNumber: detectReference(in: text),
            date: resolveDate(detectDate(in: text, calendar: calendar), now: now, calendar: calendar)
        )
    }

    // MARK: - Rejection

    /// Messages that mention money but are not a completed transaction.
    private static let ignorePattern = "(?i)" + [
        "\\b(otp|one[- ]time password|verification code)\\b",
        "has requested|requested (money|rs|inr)|collect request",
        "will be (debited|deducted|charged)",
        "\\bis due\\b|\\bdue (on|date|by)\\b|(minimum|min|total) (amt|amount) due",
        "pre-?approved|loan offer|apply now|insta ?loan|eligible for",
        "\\b(declined|failed|unsuccessful)\\b",
        // Credit card bill payment acknowledgements; the bank-side debit SMS already records it.
        "\\bpayment (of [^.]{0,30})?(has been |is )?received\\b",
    ].joined(separator: "|")

    // MARK: - Debit / credit

    private static let debitPattern =
        "(?i)\\b(debited|spent|sent|paid|withdrawn|withdrawal|purchase|purchased|deducted|used|using|txn of|transaction of|transferred to)\\b"
    private static let creditPattern =
        "(?i)\\b(credited|received|deposited|refund|refunded|reversed|reversal)\\b"

    static func detectKind(in text: String) -> TransactionKind? {
        // "Credit card" / "credit limit" say nothing about the direction of money.
        let cleaned = text
            .replacingOccurrences(of: "(?i)\\b(credit|debit)\\s+card\\b", with: "card", options: .regularExpression)
            .replacingOccurrences(of: "(?i)\\b(avl\\.?|available)?\\s*(credit|cr\\.?)\\s*(limit|lmt)\\b", with: "limit", options: .regularExpression)

        let debit = cleaned.range(of: debitPattern, options: .regularExpression)
        let credit = cleaned.range(of: creditPattern, options: .regularExpression)
        switch (debit, credit) {
        case let (d?, c?):
            // e.g. "A/c debited for Rs 450; KSEB credited" -> the first verb describes our account.
            return d.lowerBound < c.lowerBound ? .debit : .credit
        case (_?, nil):
            return .debit
        case (nil, _?):
            return .credit
        default:
            return nil
        }
    }

    // MARK: - Amount

    private static let currencyAmountPattern = "(?i)(?:(?<![a-z])(?:rs|inr)\\.?|₹)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)"
    private static let verbAmountPattern =
        "(?i)\\b(?:debited|credited|spent|sent|paid|received)\\s+(?:by|for|with|of)?\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)"

    static func detectAmount(in text: String) -> Double? {
        let ns = text as NSString
        for match in regex(currencyAmountPattern).matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            // Skip "Avl Bal Rs 12,345" / "Avl Limit INR 1,20,000".
            let windowStart = max(0, match.range.location - 14)
            let before = ns.substring(with: NSRange(location: windowStart, length: match.range.location - windowStart)).lowercased()
            if ["bal", "limit", "lmt", "avl", "available", "outstanding"].contains(where: before.contains) {
                continue
            }
            if let value = number(from: ns.substring(with: match.range(at: 1))) {
                return value
            }
        }
        // SBI style: "A/C X1234 debited by 120.0 on date ..."
        if let match = firstCapture(verbAmountPattern, in: text) {
            return number(from: match)
        }
        return nil
    }

    private static func number(from string: String) -> Double? {
        Double(string.replacingOccurrences(of: ",", with: ""))
    }

    // MARK: - Merchant

    /// Characters a merchant name / VPA may contain. Deliberately excludes "/".
    /// May start with a digit for phone-number VPAs ("9876543210@ybl"); cleanMerchant drops pure numbers.
    private static let name = "([A-Za-z0-9][A-Za-z0-9&@._'\\- ]{0,60}?)"
    /// Where a merchant name ends.
    private static let end =
        "(?=\\s+(?i:on|ref|refno|upi|via|avl|bal|info|not|if|thru|using|from|by|at|dated|date|and|has|is|was|credited|debited|to|for|towards|in|with)\\b|\\s*[,;:(]|\\.(?=[A-Z\\s])|\\.$|\\s+-|\\s*\\*|$)"

    private static var debitMerchantPatterns: [String] {
        [
            "UPI/[A-Za-z0-9]+/\\d+/([^/]+?)(?=/|\\s+(?i:not|ref|avl)\\b|$)", // Axis: UPI/P2M/4275.../BigBasket
            "\\b(?i:at)\\s+" + name + end,                                    // card spends
            "\\b(?i:to)\\s+(?:(?i:vpa)\\s+)?" + name + end,                    // UPI / transfers
            "[;,.]\\s*" + name + "\\s+(?i:credited)\\b",                       // ICICI: "...; KSEB credited."
            "\\b(?i:on|for|towards)\\s+([A-Z][A-Z0-9&' .\\-]{2,40}?)" + end,  // ICICI card: "on APOLLO PHARMACY."
            "(?i:info)[:\\s]+(?:(?i:upi|pos|imps|neft|ach)[-/ ]?(?:\\d+[-/ ])?)?" + name + end,
        ]
    }

    private static var creditMerchantPatterns: [String] {
        [
            "\\b(?i:from|by)\\s+(?:(?i:vpa)\\s+)?" + name + end,
            "\\b(?i:vpa)\\s+" + name + end,
            "(?i:info)[:\\s]+(?:(?i:upi|imps|neft|ach)[-/ ]?(?:\\d+[-/ ])?)?" + name + end,
        ]
    }

    private static let notMerchants: Set<String> = [
        "your", "you", "a", "ac", "acct", "account", "bank", "upi", "neft", "imps", "rtgs", "card",
        "the", "block", "beneficiary", "vpa", "mobile", "net banking", "netbanking", "atm",
    ]

    static func detectMerchant(in text: String, kind: TransactionKind) -> String? {
        let patterns = kind == .debit ? debitMerchantPatterns : creditMerchantPatterns
        let ns = text as NSString
        for pattern in patterns {
            for match in regex(pattern).matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let range = match.range(at: 1)
                guard range.location != NSNotFound,
                      let cleaned = cleanMerchant(ns.substring(with: range)) else { continue }
                return cleaned
            }
        }
        return nil
    }

    static func cleanMerchant(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: CharacterSet(charactersIn: " .-,:*"))
        value = value.replacingOccurrences(
            of: "(?i)^(upi|neft|imps|rtgs|pos|vpa|ach|mmt|trf)[-/: ]+", with: "", options: .regularExpression)

        if let at = value.firstIndex(of: "@") {
            // A VPA such as "swiggy.instamart@icici" or "9876543210@ybl".
            let handle = String(value[..<at])
            if handle.allSatisfy(\.isNumber) {
                return handle.count >= 4 ? "UPI ••\(handle.suffix(4))" : nil
            }
            value = handle.replacingOccurrences(of: "[._\\-]+", with: " ", options: .regularExpression)
        }

        value = value.trimmingCharacters(in: .whitespaces)
        let lower = value.lowercased()
        guard value.count >= 2,
              !notMerchants.contains(lower),
              !lower.hasPrefix("your "),
              !lower.hasPrefix("a/c"),
              lower.range(of: "^(rs|inr)\\.?\\s*\\d", options: .regularExpression) == nil,
              value.contains(where: \.isLetter) else { return nil }

        return prettify(String(value.prefix(40)))
    }

    /// "AMAZON PAY INDIA" -> "Amazon Pay India", "netflix" -> "Netflix".
    /// Short all-caps names ("KSEB", "BSNL") and mixed case are left alone.
    private static func prettify(_ value: String) -> String {
        let letters = value.filter(\.isLetter)
        let hasLongWord = value.split(separator: " ").contains { $0.count >= 5 }
        if letters == letters.uppercased() && hasLongWord {
            return value.lowercased().capitalized
        }
        if letters == letters.lowercased() {
            return value.capitalized
        }
        return value
    }

    // MARK: - Account, bank, reference

    static func detectAccount(in text: String) -> String? {
        let pattern = "(?i)(?:a/c|acct|account|\\bac|card)(?:\\s*no\\.?)?(?:\\s*ending(?:\\s*with)?)?[\\s:]*[x*#.]*\\s*(\\d{3,6})\\b"
        return firstCapture(pattern, in: text).map { String($0.suffix(4)) }
    }

    static func detectReference(in text: String) -> String? {
        let pattern = "(?i)(?:ref(?:erence)?\\.?\\s*(?:no|num|number)?\\.?|rrn|utr|upi(?:\\s*ref)?(?:\\s*no)?)[\\s:.#-]*(\\d{6,})"
        if let ref = firstCapture(pattern, in: text) { return ref }
        return firstCapture("UPI/[A-Za-z0-9]+/(\\d{6,})/", in: text)
    }

    /// Ordered so that more specific names win ("South Indian Bank" before "Indian Bank").
    private static let banks: [(name: String, pattern: String)] = [
        ("HDFC Bank", "\\bhdfc"),
        ("SBI", "\\bsbi\\b|state bank"),
        ("ICICI Bank", "\\bicici"),
        ("Axis Bank", "\\baxis\\b"),
        ("Kotak", "\\bkotak"),
        ("Federal Bank", "federal\\s*bank|\\bfedbank"),
        ("South Indian Bank", "south indian bank|\\bsib\\b"),
        ("Canara Bank", "\\bcanara"),
        ("Union Bank", "union bank"),
        ("Bank of Baroda", "bank of baroda|\\bbob\\b"),
        ("Punjab National Bank", "punjab national|\\bpnb\\b"),
        ("IDFC First", "\\bidfc"),
        ("Yes Bank", "\\byes bank"),
        ("IndusInd", "\\bindusind"),
        ("CSB Bank", "\\bcsb\\b|catholic syrian"),
        ("Kerala Gramin Bank", "kerala gramin"),
        ("ESAF Bank", "\\besaf"),
        ("Dhanlaxmi Bank", "dhanlaxmi"),
        ("AU Bank", "\\bau small finance|\\bau bank"),
        ("Bank of India", "bank of india"),
        ("Indian Overseas Bank", "indian overseas|\\biob\\b"),
        ("Indian Bank", "indian bank"),
        ("Paytm", "\\bpaytm"),
    ]

    static func detectBank(in text: String) -> String? {
        banks.first { text.range(of: "(?i)" + $0.pattern, options: .regularExpression) != nil }?.name
    }

    // MARK: - Date

    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    static func detectDate(in text: String, calendar: Calendar) -> DateComponents? {
        // 2026-10-01
        if let m = captures("(?<!\\d)(\\d{4})-(\\d{1,2})-(\\d{1,2})(?!\\d)", in: text),
           let y = Int(m[0]), let mo = Int(m[1]), let d = Int(m[2]) {
            return validDate(year: y, month: mo, day: d, calendar: calendar)
        }
        // 01-Oct-26, 01Oct26, 1 Oct 2026
        if let m = captures("(?i)(?<!\\d)(\\d{1,2})[- ]?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[-, ]*(\\d{2,4})(?!\\d)", in: text),
           let d = Int(m[0]), let mo = months.firstIndex(of: m[1].lowercased()), let y = Int(m[2]) {
            return validDate(year: y, month: mo + 1, day: d, calendar: calendar)
        }
        // 01/10/26, 01-10-2026 (Indian day-first order)
        if let m = captures("(?<!\\d)(\\d{1,2})[/-](\\d{1,2})[/-](\\d{2}|\\d{4})(?!\\d)", in: text),
           let d = Int(m[0]), let mo = Int(m[1]), let y = Int(m[2]) {
            return validDate(year: y, month: mo, day: d, calendar: calendar)
        }
        return nil
    }

    private static func validDate(year: Int, month: Int, day: Int, calendar: Calendar) -> DateComponents? {
        let fullYear = year < 100 ? 2000 + year : year
        guard (1...12).contains(month), (1...31).contains(day), (2000...2100).contains(fullYear) else { return nil }
        let components = DateComponents(year: fullYear, month: month, day: day)
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day else { return nil } // rejects 31 Feb etc.
        return components
    }

    /// The SMS normally arrives seconds after the payment, so "now" is the most accurate time.
    /// Only fall back to the printed date when it is clearly an older message being pasted in.
    static func resolveDate(_ components: DateComponents?, now: Date, calendar: Calendar) -> Date {
        guard let components,
              let day = calendar.date(from: components),
              !calendar.isDate(day, inSameDayAs: now),
              day < now else { return now }
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    // MARK: - Regex helpers

    private static var cache: [String: NSRegularExpression] = [:]
    private static let cacheLock = NSLock()

    private static func regex(_ pattern: String) -> NSRegularExpression {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cache[pattern] { return cached }
        // Patterns are compile-time constants; a failure here is a programming error.
        let compiled = try! NSRegularExpression(pattern: pattern)
        cache[pattern] = compiled
        return compiled
    }

    private static func captures(_ pattern: String, in text: String) -> [String]? {
        let ns = text as NSString
        guard let match = regex(pattern).firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return (1..<match.numberOfRanges).map {
            let range = match.range(at: $0)
            return range.location == NSNotFound ? "" : ns.substring(with: range)
        }
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        captures(pattern, in: text)?.first
    }
}

import Foundation
import SwiftData

enum AppModelContainer {
    /// One container shared by the app UI and the App Intents (which run in the same process),
    /// so a transaction logged from Shortcuts shows up immediately on screen.
    static let shared: ModelContainer = {
        do {
            return try ModelContainer(for: Schema([BankTransaction.self, MerchantRule.self]))
        } catch {
            fatalError("Could not open the transactions database: \(error)")
        }
    }()
}

struct TransactionStore {
    let context: ModelContext

    enum IngestResult {
        case saved(BankTransaction)
        case duplicate
        case notATransaction
    }

    /// Parses a bank SMS and saves it, skipping messages that were already logged.
    @discardableResult
    func ingest(sms: String, now: Date = .now) throws -> IngestResult {
        let trimmed = sms.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parsed = BankSMSParser.parse(trimmed, now: now) else { return .notATransaction }
        if try isDuplicate(parsed, sms: trimmed) { return .duplicate }

        if let rule = try rule(for: parsed.merchant) {
            parsed.category = rule.category
        }

        let transaction = BankTransaction(
            amount: parsed.amount,
            kind: parsed.kind,
            merchant: parsed.merchant,
            category: parsed.category,
            date: parsed.date,
            bank: parsed.bank,
            accountLast4: parsed.accountLast4,
            referenceNumber: parsed.referenceNumber,
            rawSMS: trimmed,
            source: .sms
        )
        context.insert(transaction)
        try context.save()
        return .saved(transaction)
    }

    func isDuplicate(_ parsed: ParsedSMS, sms: String) throws -> Bool {
        if let reference = parsed.referenceNumber {
            let ref: String? = reference
            let amount = parsed.amount
            var byReference = FetchDescriptor<BankTransaction>(
                predicate: #Predicate { $0.referenceNumber == ref && $0.amount == amount })
            byReference.fetchLimit = 1
            if try !context.fetch(byReference).isEmpty { return true }
        }
        let raw: String? = sms
        var byText = FetchDescriptor<BankTransaction>(predicate: #Predicate { $0.rawSMS == raw })
        byText.fetchLimit = 1
        return try !context.fetch(byText).isEmpty
    }

    // MARK: - Merchant rules

    func rule(for merchant: String) throws -> MerchantRule? {
        let key = MerchantRule.key(for: merchant)
        var descriptor = FetchDescriptor<MerchantRule>(predicate: #Predicate { $0.merchantKey == key })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Called when the user changes a transaction's category, so the next SMS from that merchant is categorised the same way.
    func remember(_ category: SpendingCategory, for merchant: String) {
        let key = MerchantRule.key(for: merchant)
        guard !key.isEmpty else { return }
        if let existing = try? rule(for: merchant) {
            existing.categoryRaw = category.rawValue
        } else {
            context.insert(MerchantRule(merchantKey: key, category: category))
        }
        try? context.save()
    }

    // MARK: - Totals

    func totalSpent(on day: Date, calendar: Calendar = .current) throws -> Double {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? day
        let debit = TransactionKind.debit.rawValue
        let descriptor = FetchDescriptor<BankTransaction>(
            predicate: #Predicate { $0.kindRaw == debit && $0.date >= start && $0.date < end })
        return try context.fetch(descriptor).reduce(0) { $0 + $1.amount }
    }
}

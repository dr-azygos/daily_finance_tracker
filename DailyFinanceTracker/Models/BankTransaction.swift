import Foundation
import SwiftData

enum TransactionSource: String, Codable {
    case sms
    case manual
}

@Model
final class BankTransaction {
    var amount: Double
    var kindRaw: String
    var merchant: String
    var categoryRaw: String
    var date: Date
    var bank: String?
    var accountLast4: String?
    var referenceNumber: String?
    var rawSMS: String?
    var note: String
    var sourceRaw: String
    var createdAt: Date

    init(
        amount: Double,
        kind: TransactionKind,
        merchant: String,
        category: SpendingCategory,
        date: Date = .now,
        bank: String? = nil,
        accountLast4: String? = nil,
        referenceNumber: String? = nil,
        rawSMS: String? = nil,
        note: String = "",
        source: TransactionSource = .manual
    ) {
        self.amount = amount
        self.kindRaw = kind.rawValue
        self.merchant = merchant
        self.categoryRaw = category.rawValue
        self.date = date
        self.bank = bank
        self.accountLast4 = accountLast4
        self.referenceNumber = referenceNumber
        self.rawSMS = rawSMS
        self.note = note
        self.sourceRaw = source.rawValue
        self.createdAt = .now
    }

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .debit }
        set { kindRaw = newValue.rawValue }
    }

    var category: SpendingCategory {
        get { SpendingCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var source: TransactionSource {
        get { TransactionSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    /// Positive for income, negative for spending.
    var signedAmount: Double { kind == .credit ? amount : -amount }
}

/// Remembers the category the user picked for a merchant so future SMS from that merchant get it automatically.
@Model
final class MerchantRule {
    @Attribute(.unique) var merchantKey: String
    var categoryRaw: String

    init(merchantKey: String, category: SpendingCategory) {
        self.merchantKey = merchantKey
        self.categoryRaw = category.rawValue
    }

    var category: SpendingCategory { SpendingCategory(rawValue: categoryRaw) ?? .other }

    static func key(for merchant: String) -> String {
        merchant.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

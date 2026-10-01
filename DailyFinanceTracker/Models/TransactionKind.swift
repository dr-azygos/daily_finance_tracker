import Foundation

enum TransactionKind: String, Codable, CaseIterable, Identifiable {
    case debit
    case credit

    var id: String { rawValue }
    var displayName: String { self == .debit ? "Expense" : "Income" }
}

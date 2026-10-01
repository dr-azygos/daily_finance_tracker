import Foundation

/// Spending categories. Kept free of UI imports so the parser can be unit tested on its own.
enum SpendingCategory: String, CaseIterable, Codable, Identifiable {
    case food
    case groceries
    case transport
    case fuel
    case shopping
    case bills
    case health
    case entertainment
    case travel
    case education
    case transfer
    case cash
    case income
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .food: "Food & Dining"
        case .groceries: "Groceries"
        case .transport: "Transport"
        case .fuel: "Fuel"
        case .shopping: "Shopping"
        case .bills: "Bills & Recharge"
        case .health: "Health"
        case .entertainment: "Entertainment"
        case .travel: "Travel"
        case .education: "Education"
        case .transfer: "Transfers"
        case .cash: "Cash Withdrawal"
        case .income: "Income"
        case .other: "Other"
        }
    }
}

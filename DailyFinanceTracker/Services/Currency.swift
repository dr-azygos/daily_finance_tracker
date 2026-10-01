import Foundation

enum Currency {
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_IN") // ₹1,20,000 grouping
        formatter.currencyCode = "INR"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static func format(_ value: Double) -> String {
        formatter.string(from: NSNumber(value: value)) ?? "₹\(value)"
    }
}

enum AppSettings {
    static let dailyBudgetKey = "dailyBudget"
    static let defaultDailyBudget = 1000.0

    static var dailyBudget: Double {
        UserDefaults.standard.object(forKey: dailyBudgetKey) as? Double ?? defaultDailyBudget
    }
}

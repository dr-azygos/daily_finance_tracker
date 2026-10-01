import Foundation
import UserNotifications

enum NotificationService {
    static let enabledKey = "notifyOnLog"

    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Shows "₹250 at Swiggy · ₹1,240 spent today" after a transaction is logged from an SMS.
    static func notifyLogged(_ transaction: BankTransaction, spentToday: Double, dailyBudget: Double) {
        let enabled = UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
        guard enabled else { return }

        let content = UNMutableNotificationContent()
        let amount = Currency.format(transaction.amount)
        if transaction.kind == .debit {
            content.title = "\(amount) at \(transaction.merchant)"
            var body = "\(Currency.format(spentToday)) spent today"
            if dailyBudget > 0 {
                let left = dailyBudget - spentToday
                body += left >= 0
                    ? " · \(Currency.format(left)) left of your daily budget"
                    : " · \(Currency.format(-left)) over your daily budget"
            }
            content.body = body
        } else {
            content.title = "\(amount) received"
            content.body = "From \(transaction.merchant)"
        }
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

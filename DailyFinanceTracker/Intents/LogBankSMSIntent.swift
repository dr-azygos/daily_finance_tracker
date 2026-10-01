import AppIntents
import Foundation

/// The bridge from Messages to the app. iOS doesn't let apps read SMS, so a Shortcuts
/// automation ("When I get a message containing 'debited'") passes the message text here.
struct LogBankSMSIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Bank SMS"
    static let description = IntentDescription(
        "Reads a bank, card or UPI transaction SMS and records the expense or income in Daily Finance.")
    static let openAppWhenRun = false

    @Parameter(
        title: "Message",
        description: "The full text of the bank SMS.",
        inputOptions: String.IntentInputOptions(multiline: true))
    var message: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log bank SMS \(\.$message)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let store = TransactionStore(context: AppModelContainer.shared.mainContext)

        switch try store.ingest(sms: message) {
        case .saved(let transaction):
            let spentToday = try store.totalSpent(on: .now)
            NotificationService.notifyLogged(transaction, spentToday: spentToday, dailyBudget: AppSettings.dailyBudget)
            let verb = transaction.kind == .debit ? "Spent" : "Received"
            let summary = "\(verb) \(Currency.format(transaction.amount)) · \(transaction.merchant)"
            return .result(value: summary, dialog: "\(summary)")
        case .duplicate:
            return .result(value: "Already logged", dialog: "This transaction was already logged.")
        case .notATransaction:
            return .result(value: "Not a transaction", dialog: "That message doesn't look like a bank transaction, so nothing was logged.")
        }
    }
}

struct TodaySpendingIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's Spending"
    static let description = IntentDescription("Tells you how much you have spent today.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let spent = try TransactionStore(context: AppModelContainer.shared.mainContext).totalSpent(on: .now)
        let budget = AppSettings.dailyBudget
        var sentence = "You've spent \(Currency.format(spent)) today."
        if budget > 0 {
            sentence += spent <= budget
                ? " \(Currency.format(budget - spent)) left in your daily budget."
                : " That's \(Currency.format(spent - budget)) over your daily budget."
        }
        return .result(value: spent, dialog: "\(sentence)")
    }
}

struct DailyFinanceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TodaySpendingIntent(),
            phrases: [
                "How much did I spend today in \(.applicationName)",
                "Today's spending in \(.applicationName)",
            ],
            shortTitle: "Today's Spending",
            systemImageName: "indianrupeesign.circle")
        AppShortcut(
            intent: LogBankSMSIntent(),
            phrases: ["Log bank SMS in \(.applicationName)"],
            shortTitle: "Log Bank SMS",
            systemImageName: "message.badge")
    }
}

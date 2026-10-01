import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BankTransaction.date, order: .reverse) private var transactions: [BankTransaction]
    @AppStorage(AppSettings.dailyBudgetKey) private var dailyBudget = AppSettings.defaultDailyBudget
    @AppStorage(NotificationService.enabledKey) private var notifyOnLog = true
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Daily budget") {
                        TextField("Amount", value: $dailyBudget, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Set to 0 to turn off budget tracking.")
                }

                Section("Automatic logging") {
                    NavigationLink("Set up SMS logging") { SetupGuideView() }
                    Toggle("Notify when an SMS is logged", isOn: $notifyOnLog)
                }

                Section("Data") {
                    ShareLink(item: CSVExport(transactions: transactions), preview: SharePreview("Transactions.csv")) {
                        Label("Export as CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(transactions.isEmpty)
                    Button("Delete all transactions", role: .destructive) { confirmingDelete = true }
                        .disabled(transactions.isEmpty)
                }

                Section {
                    Text("Everything stays on this iPhone. The app has no account, no server and no internet access — it only sees the SMS text that your Shortcuts automation passes to it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Privacy")
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete all \(transactions.count) transactions?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) {
                    try? context.delete(model: BankTransaction.self)
                    try? context.save()
                }
            } message: {
                Text("This can't be undone.")
            }
        }
    }
}

/// Exported as a .csv file that opens in Numbers, Excel or Google Sheets.
struct CSVExport: Transferable {
    let csv: String

    init(transactions: [BankTransaction]) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let header = "Date,Type,Amount,Merchant,Category,Bank,Account,Reference,Note"
        let rows = transactions.map { t in
            [
                formatter.string(from: t.date),
                t.kind.displayName,
                String(format: "%.2f", t.amount),
                t.merchant,
                t.category.displayName,
                t.bank ?? "",
                t.accountLast4 ?? "",
                t.referenceNumber ?? "",
                t.note,
            ]
            .map(Self.escape)
            .joined(separator: ",")
        }
        csv = ([header] + rows).joined(separator: "\n")
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { export in
            Data(export.csv.utf8)
        }
        .suggestedFileName("Transactions.csv")
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

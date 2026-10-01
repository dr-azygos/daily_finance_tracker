import SwiftData
import SwiftUI

struct TransactionDetailView: View {
    @Bindable var transaction: BankTransaction
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false

    private var categoryBinding: Binding<SpendingCategory> {
        Binding(
            get: { transaction.category },
            set: { newValue in
                transaction.category = newValue
                // Learn from the correction so future SMS from this merchant get the same category.
                TransactionStore(context: context).remember(newValue, for: transaction.merchant)
            })
    }

    private var kindBinding: Binding<TransactionKind> {
        Binding(get: { transaction.kind }, set: { transaction.kind = $0 })
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    CategoryIcon(category: transaction.category, size: 48)
                    VStack(alignment: .leading) {
                        Text(transaction.merchant).font(.headline)
                        Text(transaction.date.formatted(date: .complete, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    AmountText(transaction: transaction)
                }
            }

            Section("Details") {
                TextField("Merchant", text: $transaction.merchant)
                LabeledContent("Amount (₹)") {
                    TextField("Amount", value: $transaction.amount, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                Picker("Type", selection: kindBinding) {
                    ForEach(TransactionKind.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Category", selection: categoryBinding) {
                    ForEach(SpendingCategory.allCases) { item in
                        Label(item.displayName, systemImage: item.symbol).tag(item)
                    }
                }
                DatePicker("Date", selection: $transaction.date)
                TextField("Note", text: $transaction.note, axis: .vertical)
            }

            if transaction.source == .sms {
                Section("From SMS") {
                    if let bank = transaction.bank { LabeledContent("Bank", value: bank) }
                    if let account = transaction.accountLast4 { LabeledContent("Account", value: "••\(account)") }
                    if let reference = transaction.referenceNumber { LabeledContent("Reference", value: reference) }
                    if let raw = transaction.rawSMS {
                        Text(raw)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Section {
                Button("Delete Transaction", role: .destructive) { confirmingDelete = true }
            }
        }
        .navigationTitle(transaction.kind == .debit ? "Expense" : "Income")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { if !transaction.isDeleted { try? context.save() } }
        .confirmationDialog("Delete this transaction?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                // Leave the screen first so it never renders a deleted model.
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    context.delete(transaction)
                    try? context.save()
                }
            }
        }
    }
}

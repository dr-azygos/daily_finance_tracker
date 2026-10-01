import SwiftData
import SwiftUI

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    enum Mode: String, CaseIterable, Identifiable {
        case sms = "Paste SMS", manual = "Manual"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .sms
    @State private var smsText = ""
    @State private var alertMessage: String?

    @State private var amount: Double?
    @State private var kind: TransactionKind = .debit
    @State private var merchant = ""
    @State private var category: SpendingCategory = .food
    @State private var date = Date.now
    @State private var note = ""

    private var parsed: ParsedSMS? { BankSMSParser.parse(smsText) }

    private var canSave: Bool {
        switch mode {
        case .sms: parsed != nil
        case .manual: (amount ?? 0) > 0
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                switch mode {
                case .sms: smsForm
                case .manual: manualForm
                }
            }
            .navigationTitle("Add Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .alert(alertMessage ?? "", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private var smsForm: some View {
        Section {
            TextEditor(text: $smsText)
                .frame(minHeight: 140)
                .font(.callout)
            PasteButton(payloadType: String.self) { strings in
                smsText = strings.first ?? ""
            }
        } header: {
            Text("Bank SMS")
        } footer: {
            Text("In Messages, long-press the bank SMS → Copy, then paste it here.")
        }

        if !smsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Section("Detected") {
                if let parsed {
                    ParsedPreview(parsed: parsed)
                } else {
                    Label("This doesn't look like a completed bank transaction. Try Manual instead.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private var manualForm: some View {
        Section {
            Picker("Type", selection: $kind) {
                ForEach(TransactionKind.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            LabeledContent("Amount (₹)") {
                TextField("0", value: $amount, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            TextField(kind == .debit ? "Paid to" : "Received from", text: $merchant)
            Picker("Category", selection: $category) {
                ForEach(SpendingCategory.allCases) { item in
                    Label(item.displayName, systemImage: item.symbol).tag(item)
                }
            }
            DatePicker("Date", selection: $date)
            TextField("Note", text: $note, axis: .vertical)
        }
        .onChange(of: kind) { _, newKind in
            if newKind == .credit { category = .income }
            else if category == .income { category = .food }
        }
    }

    private func save() {
        let store = TransactionStore(context: context)
        switch mode {
        case .sms:
            do {
                switch try store.ingest(sms: smsText) {
                case .saved: dismiss()
                case .duplicate: alertMessage = "This transaction is already in your history."
                case .notATransaction: alertMessage = "Couldn't find a transaction in this message."
                }
            } catch {
                alertMessage = "Couldn't save: \(error.localizedDescription)"
            }
        case .manual:
            guard let amount, amount > 0 else { return }
            let name = merchant.trimmingCharacters(in: .whitespaces)
            context.insert(BankTransaction(
                amount: amount,
                kind: kind,
                merchant: name.isEmpty ? category.displayName : name,
                category: category,
                date: date,
                note: note,
                source: .manual
            ))
            if !name.isEmpty { store.remember(category, for: name) }
            try? context.save()
            dismiss()
        }
    }
}

import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BankTransaction.date, order: .reverse) private var transactions: [BankTransaction]
    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var showingAdd = false

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", expenses = "Expenses", income = "Income"
        var id: String { rawValue }
    }

    private var filtered: [BankTransaction] {
        transactions.filter { transaction in
            switch filter {
            case .all: break
            case .expenses: if transaction.kind != .debit { return false }
            case .income: if transaction.kind != .credit { return false }
            }
            guard !search.isEmpty else { return true }
            return transaction.merchant.localizedCaseInsensitiveContains(search)
                || transaction.category.displayName.localizedCaseInsensitiveContains(search)
                || transaction.note.localizedCaseInsensitiveContains(search)
        }
    }

    private var days: [(day: Date, items: [BankTransaction])] {
        Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.date) }
            .map { (day: $0.key, items: $0.value) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                ForEach(days, id: \.day) { group in
                    Section {
                        ForEach(group.items) { transaction in
                            NavigationLink {
                                TransactionDetailView(transaction: transaction)
                            } label: {
                                TransactionRow(transaction: transaction)
                            }
                        }
                        .onDelete { offsets in
                            offsets.map { group.items[$0] }.forEach { context.delete($0) }
                            try? context.save()
                        }
                    } header: {
                        HStack {
                            Text(group.day.formatted(.dateTime.weekday(.wide).day().month()))
                            Spacer()
                            let spent = group.items.totalSpent
                            if spent > 0 { Text("−\(Currency.format(spent))").monospacedDigit() }
                        }
                    }
                }
            }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        search.isEmpty ? "Nothing here yet" : "No matches",
                        systemImage: search.isEmpty ? "tray" : "magnifyingglass")
                }
            }
            .searchable(text: $search, prompt: "Merchant, category or note")
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add transaction")
                }
            }
            .sheet(isPresented: $showingAdd) { AddTransactionView() }
        }
    }
}

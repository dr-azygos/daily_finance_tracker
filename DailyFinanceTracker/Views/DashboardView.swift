import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Query(sort: \BankTransaction.date, order: .reverse) private var transactions: [BankTransaction]
    @AppStorage(AppSettings.dailyBudgetKey) private var dailyBudget = AppSettings.defaultDailyBudget
    @State private var showingAdd = false
    @State private var showingSetup = false

    private var today: [BankTransaction] {
        transactions.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var thisMonth: [BankTransaction] {
        transactions.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    todayCard
                    monthCards
                    if today.contains(where: { $0.kind == .debit }) {
                        todayBreakdown
                    }
                    recent
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus.circle.fill") }
                        .accessibilityLabel("Add transaction")
                }
            }
            .sheet(isPresented: $showingAdd) { AddTransactionView() }
            .sheet(isPresented: $showingSetup) {
                NavigationStack { SetupGuideView() }
            }
        }
    }

    private var todayCard: some View {
        let spent = today.totalSpent
        let progress = dailyBudget > 0 ? min(spent / dailyBudget, 1) : 0
        let over = dailyBudget > 0 && spent > dailyBudget

        return VStack(alignment: .leading, spacing: 12) {
            Text("Spent today").font(.subheadline).foregroundStyle(.secondary)
            Text(Currency.format(spent))
                .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
            if dailyBudget > 0 {
                ProgressView(value: progress)
                    .tint(over ? Color.red : progress > 0.8 ? Color.orange : Color.accentColor)
                Text(over
                     ? "\(Currency.format(spent - dailyBudget)) over your \(Currency.format(dailyBudget)) daily budget"
                     : "\(Currency.format(dailyBudget - spent)) left of \(Currency.format(dailyBudget))")
                    .font(.footnote)
                    .foregroundStyle(over ? Color.red : Color.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var monthCards: some View {
        HStack(spacing: 12) {
            statCard(title: "Spent this month", value: thisMonth.totalSpent, color: .primary)
            statCard(title: "Received this month", value: thisMonth.totalReceived, color: .green)
        }
    }

    private func statCard(title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Currency.format(value))
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var todayBreakdown: some View {
        let totals = Dictionary(grouping: today.filter { $0.kind == .debit }, by: \.category)
            .map { (category: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.amount > $1.amount }

        return VStack(alignment: .leading, spacing: 12) {
            Text("Where it went today").font(.headline)
            HStack(spacing: 16) {
                Chart(totals, id: \.category) { item in
                    SectorMark(angle: .value("Amount", item.amount), innerRadius: .ratio(0.6), angularInset: 1.5)
                        .foregroundStyle(item.category.color)
                }
                .frame(width: 110, height: 110)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(totals.prefix(5), id: \.category) { item in
                        HStack {
                            Circle().fill(item.category.color).frame(width: 8, height: 8)
                            Text(item.category.displayName).font(.caption)
                            Spacer()
                            Text(Currency.format(item.amount)).font(.caption.monospacedDigit())
                        }
                    }
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var recent: some View {
        if transactions.isEmpty {
            ContentUnavailableView {
                Label("No transactions yet", systemImage: "message.badge")
            } description: {
                Text("Set up the Shortcuts automation once, and every bank SMS you receive will be logged here automatically.")
            } actions: {
                Button("Set up SMS logging") { showingSetup = true }
                    .buttonStyle(.borderedProminent)
                Button("Paste an SMS") { showingAdd = true }
            }
            .padding(.top, 24)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent").font(.headline)
                VStack(spacing: 0) {
                    ForEach(transactions.prefix(8)) { transaction in
                        NavigationLink {
                            TransactionDetailView(transaction: transaction)
                        } label: {
                            TransactionRow(transaction: transaction)
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        if transaction.id != transactions.prefix(8).last?.id {
                            Divider().padding(.leading, 64)
                        }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

import Charts
import SwiftData
import SwiftUI

struct InsightsView: View {
    @Query(sort: \BankTransaction.date, order: .reverse) private var transactions: [BankTransaction]
    @AppStorage(AppSettings.dailyBudgetKey) private var dailyBudget = AppSettings.defaultDailyBudget
    @State private var period: Period = .week

    enum Period: String, CaseIterable, Identifiable {
        case week = "7 days", month = "30 days", thisMonth = "This month"
        var id: String { rawValue }

        var startDate: Date {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            switch self {
            case .week: return calendar.date(byAdding: .day, value: -6, to: today)!
            case .month: return calendar.date(byAdding: .day, value: -29, to: today)!
            case .thisMonth: return calendar.dateInterval(of: .month, for: .now)!.start
            }
        }
    }

    private var expenses: [BankTransaction] {
        let start = period.startDate
        return transactions.filter { $0.kind == .debit && $0.date >= start }
    }

    private var daily: [(day: Date, amount: Double)] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: expenses) { calendar.startOfDay(for: $0.date) }
        var result: [(Date, Double)] = []
        var day = period.startDate
        let today = calendar.startOfDay(for: .now)
        while day <= today {
            result.append((day, grouped[day]?.reduce(0) { $0 + $1.amount } ?? 0))
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return result.map { (day: $0.0, amount: $0.1) }
    }

    private var byCategory: [(category: SpendingCategory, amount: Double)] {
        Dictionary(grouping: expenses, by: \.category)
            .map { (category: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.amount > $1.amount }
    }

    private var topMerchants: [(merchant: String, amount: Double, count: Int)] {
        Dictionary(grouping: expenses, by: \.merchant)
            .map { (merchant: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }, count: $0.value.count) }
            .sorted { $0.amount > $1.amount }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Period", selection: $period) {
                    ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if expenses.isEmpty {
                    ContentUnavailableView("No spending in this period", systemImage: "chart.bar")
                } else {
                    summarySection
                    dailySection
                    categorySection
                    merchantSection
                }
            }
            .navigationTitle("Insights")
        }
    }

    private var summarySection: some View {
        let total = expenses.totalSpent
        let average = total / Double(max(daily.count, 1))
        return Section {
            LabeledContent("Total spent", value: Currency.format(total))
            LabeledContent("Daily average", value: Currency.format(average))
            if dailyBudget > 0 {
                let overDays = daily.filter { $0.amount > dailyBudget }.count
                LabeledContent("Days over budget", value: "\(overDays) of \(daily.count)")
            }
        }
    }

    private var dailySection: some View {
        Section("Daily spending") {
            Chart {
                ForEach(daily, id: \.day) { item in
                    BarMark(x: .value("Day", item.day, unit: .day), y: .value("Spent", item.amount))
                        .foregroundStyle(dailyBudget > 0 && item.amount > dailyBudget ? Color.red : Color.accentColor)
                }
                if dailyBudget > 0 {
                    RuleMark(y: .value("Budget", dailyBudget))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(.secondary)
                        .annotation(position: .top, alignment: .leading) {
                            Text("Budget").font(.caption2).foregroundStyle(.secondary)
                        }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) { Text(Currency.format(amount)) }
                    }
                }
            }
            .frame(height: 200)
            .padding(.vertical, 8)
        }
    }

    private var categorySection: some View {
        let total = max(expenses.totalSpent, 1)
        return Section("By category") {
            ForEach(byCategory, id: \.category) { item in
                HStack(spacing: 12) {
                    CategoryIcon(category: item.category, size: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.category.displayName)
                            Spacer()
                            Text(Currency.format(item.amount)).monospacedDigit()
                        }
                        .font(.subheadline)
                        ProgressView(value: item.amount / total).tint(item.category.color)
                    }
                }
            }
        }
    }

    private var merchantSection: some View {
        Section("Top merchants") {
            ForEach(topMerchants, id: \.merchant) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.merchant)
                        Text("\(item.count) transaction\(item.count == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Currency.format(item.amount)).monospacedDigit()
                }
            }
        }
    }
}

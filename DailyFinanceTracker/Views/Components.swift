import SwiftUI

struct CategoryIcon: View {
    let category: SpendingCategory
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(category.color)
            .frame(width: size, height: size)
            .background(category.color.opacity(0.15), in: Circle())
    }
}

struct TransactionRow: View {
    let transaction: BankTransaction

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: transaction.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.merchant)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(transaction.category.displayName)
                    Text("·")
                    Text(transaction.date, format: .dateTime.hour().minute())
                    if transaction.source == .sms {
                        Image(systemName: "message.fill")
                            .accessibilityLabel("From SMS")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            AmountText(transaction: transaction)
        }
        .padding(.vertical, 2)
    }
}

struct AmountText: View {
    let transaction: BankTransaction

    var body: some View {
        Text((transaction.kind == .credit ? "+" : "−") + Currency.format(transaction.amount))
            .font(.body.monospacedDigit().weight(.semibold))
            .foregroundStyle(transaction.kind == .credit ? Color.green : Color.primary)
    }
}

/// Shows what the parser understood from an SMS before it is saved.
struct ParsedPreview: View {
    let parsed: ParsedSMS

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                CategoryIcon(category: parsed.category, size: 44)
                VStack(alignment: .leading) {
                    Text(parsed.merchant).font(.headline)
                    Text(parsed.category.displayName).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text((parsed.kind == .credit ? "+" : "−") + Currency.format(parsed.amount))
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(parsed.kind == .credit ? Color.green : Color.primary)
            }
            Divider()
            detail("Type", parsed.kind.displayName)
            detail("Date", parsed.date.formatted(date: .abbreviated, time: .shortened))
            if let bank = parsed.bank { detail("Bank", bank) }
            if let account = parsed.accountLast4 { detail("Account", "••\(account)") }
            if let reference = parsed.referenceNumber { detail("Reference", reference) }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.subheadline)
    }
}

extension Array where Element == BankTransaction {
    var totalSpent: Double { filter { $0.kind == .debit }.reduce(0) { $0 + $1.amount } }
    var totalReceived: Double { filter { $0.kind == .credit }.reduce(0) { $0 + $1.amount } }
}

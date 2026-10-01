import SwiftUI

extension SpendingCategory {
    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .groceries: "cart"
        case .transport: "car"
        case .fuel: "fuelpump"
        case .shopping: "bag"
        case .bills: "bolt"
        case .health: "cross.case"
        case .entertainment: "film"
        case .travel: "airplane"
        case .education: "book"
        case .transfer: "arrow.left.arrow.right"
        case .cash: "banknote"
        case .income: "arrow.down.circle"
        case .other: "square.grid.2x2"
        }
    }

    var color: Color {
        switch self {
        case .food: .orange
        case .groceries: .green
        case .transport: .blue
        case .fuel: .brown
        case .shopping: .pink
        case .bills: .yellow
        case .health: .red
        case .entertainment: .purple
        case .travel: .cyan
        case .education: .indigo
        case .transfer: .gray
        case .cash: .mint
        case .income: .teal
        case .other: .secondary
        }
    }
}

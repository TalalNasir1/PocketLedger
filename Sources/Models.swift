import Foundation

enum BillingCycle: String, Codable, CaseIterable, Identifiable {
    case weekly = "Weekly"
    case monthly = "Monthly"
    case yearly = "Yearly"
    case custom = "Custom days"

    var id: String { rawValue }
}

enum AssetKind: String, Codable, CaseIterable, Identifiable {
    case cash = "Cash"
    case bank = "Bank account"
    case savings = "Savings"
    case investment = "Investment"
    case property = "Property"
    case other = "Other"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .cash: return "banknote.fill"
        case .bank: return "building.columns.fill"
        case .savings: return "dollarsign.circle.fill"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .property: return "house.fill"
        case .other: return "shippingbox.fill"
        }
    }
}

struct AssetAccount: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var kind: AssetKind
    var balance: Double
    var notes: String = ""
    var includeInTotal: Bool = true
    var updatedAt = Date()
}

struct ExpenseEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var amount: Double
    var date: Date
    var category: String
    var paymentMethod: String = ""
    var assetID: UUID?
    var notes: String = ""
    var subscriptionID: UUID?
}

struct IncomeEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var source: String
    var amount: Double
    var date: Date
    var category: String
    var assetID: UUID?
    var notes: String = ""
}

struct SubscriptionEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var amount: Double
    var cycle: BillingCycle
    var customDays: Int = 30
    var nextDueDate: Date
    var reminderDays: Int = 3
    var assetID: UUID?
    var isActive: Bool = true
    var notes: String = ""

    func monthlyEquivalent() -> Double {
        switch cycle {
        case .weekly: return amount * 52.0 / 12.0
        case .monthly: return amount
        case .yearly: return amount / 12.0
        case .custom: return amount * 30.4375 / Double(max(customDays, 1))
        }
    }

    func dateAfter(_ date: Date, calendar: Calendar = .current) -> Date {
        switch cycle {
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date) ?? date
        case .custom:
            return calendar.date(byAdding: .day, value: max(customDays, 1), to: date) ?? date
        }
    }
}

struct LedgerSettings: Codable, Hashable {
    var currencyCode: String = Locale.current.currency?.identifier ?? "USD"
    var reminderHour: Int = 9
}

struct LedgerData: Codable {
    var assets: [AssetAccount] = []
    var expenses: [ExpenseEntry] = []
    var income: [IncomeEntry] = []
    var subscriptions: [SubscriptionEntry] = []
    var settings = LedgerSettings()
    var lastBackupDate: Date?
}

extension Date {
    var startOfMonth: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self)) ?? self
    }

    var endOfMonth: Date {
        let start = startOfMonth
        return Calendar.current.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? self
    }
}

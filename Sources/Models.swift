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
    case phone = "Phone"
    case laptop = "Laptop"
    case other = "Other"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .cash: return "banknote.fill"
        case .bank: return "building.columns.fill"
        case .savings: return "dollarsign.circle.fill"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .property: return "house.fill"
        case .phone: return "iphone"
        case .laptop: return "laptopcomputer"
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

struct AssetTransfer: Identifiable, Codable, Hashable {
    var id = UUID()
    var amount: Double
    var date: Date
    var fromAssetID: UUID
    var toAssetID: UUID
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
    var trialEndDate: Date?
    var trialReminderDays: Int?

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
    var transfers: [AssetTransfer] = []
    var subscriptions: [SubscriptionEntry] = []
    var settings = LedgerSettings()
    var lastBackupDate: Date?

    private enum CodingKeys: String, CodingKey {
        case assets, expenses, income, transfers, subscriptions, settings, lastBackupDate
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assets = try container.decodeIfPresent([AssetAccount].self, forKey: .assets) ?? []
        expenses = try container.decodeIfPresent([ExpenseEntry].self, forKey: .expenses) ?? []
        income = try container.decodeIfPresent([IncomeEntry].self, forKey: .income) ?? []
        transfers = try container.decodeIfPresent([AssetTransfer].self, forKey: .transfers) ?? []
        subscriptions = try container.decodeIfPresent([SubscriptionEntry].self, forKey: .subscriptions) ?? []
        settings = try container.decodeIfPresent(LedgerSettings.self, forKey: .settings) ?? LedgerSettings()
        lastBackupDate = try container.decodeIfPresent(Date.self, forKey: .lastBackupDate)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(assets, forKey: .assets)
        try container.encode(expenses, forKey: .expenses)
        try container.encode(income, forKey: .income)
        try container.encode(transfers, forKey: .transfers)
        try container.encode(subscriptions, forKey: .subscriptions)
        try container.encode(settings, forKey: .settings)
        try container.encodeIfPresent(lastBackupDate, forKey: .lastBackupDate)
    }
}

extension Date {
    var startOfMonth: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self)) ?? self
    }

    var endOfMonth: Date {
        let start = startOfMonth
        return Calendar.current.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? self
    }

    var startOfYear: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year], from: self)) ?? self
    }

    var endOfYear: Date {
        Calendar.current.date(byAdding: DateComponents(year: 1, second: -1), to: startOfYear) ?? self
    }
}

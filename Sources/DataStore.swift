import AppKit
import Foundation

@MainActor
final class LedgerStore: ObservableObject {
    @Published private(set) var data = LedgerData()
    @Published var lastError: String?

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let customStorageRoot: URL?
    private let schedulesNotifications: Bool

    private var supportFolder: URL {
        if let customStorageRoot { return customStorageRoot }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("Pocket Ledger", isDirectory: true)
    }

    private var dataFile: URL { supportFolder.appendingPathComponent("ledger-data.json") }
    var backupFolder: URL { supportFolder.appendingPathComponent("Backups", isDirectory: true) }

    init(storageRoot: URL? = nil, schedulesNotifications: Bool = true) {
        self.customStorageRoot = storageRoot
        self.schedulesNotifications = schedulesNotifications
        load()
        createDailyBackupIfNeeded()
    }

    func assetName(for id: UUID?) -> String {
        guard let id else { return "Not linked" }
        return data.assets.first(where: { $0.id == id })?.name ?? "Deleted account"
    }

    func currency(_ amount: Double) -> String {
        amount.formatted(.currency(code: data.settings.currencyCode))
    }

    var totalAssets: Double {
        data.assets.filter(\.includeInTotal).reduce(0) { $0 + $1.balance }
    }

    var monthlySubscriptionCost: Double {
        data.subscriptions.filter(\.isActive).reduce(0) { $0 + $1.monthlyEquivalent() }
    }

    var thisMonthExpenses: Double {
        data.expenses.filter { $0.date >= Date().startOfMonth && $0.date <= Date().endOfMonth }
            .reduce(0) { $0 + $1.amount }
    }

    var thisMonthIncome: Double {
        data.income.filter { $0.date >= Date().startOfMonth && $0.date <= Date().endOfMonth }
            .reduce(0) { $0 + $1.amount }
    }

    func totalSpent(on subscription: SubscriptionEntry) -> Double {
        data.expenses.filter { $0.subscriptionID == subscription.id }.reduce(0) { $0 + $1.amount }
    }

    func addAsset(_ asset: AssetAccount) {
        data.assets.append(asset)
        persist()
    }

    func updateAsset(_ asset: AssetAccount) {
        guard let index = data.assets.firstIndex(where: { $0.id == asset.id }) else { return }
        var updated = asset
        updated.updatedAt = Date()
        data.assets[index] = updated
        persist()
    }

    func deleteAsset(_ asset: AssetAccount) {
        data.assets.removeAll { $0.id == asset.id }
        for index in data.expenses.indices where data.expenses[index].assetID == asset.id { data.expenses[index].assetID = nil }
        for index in data.income.indices where data.income[index].assetID == asset.id { data.income[index].assetID = nil }
        for index in data.subscriptions.indices where data.subscriptions[index].assetID == asset.id { data.subscriptions[index].assetID = nil }
        persist()
    }

    func addExpense(_ expense: ExpenseEntry) {
        data.expenses.append(expense)
        changeAsset(expense.assetID, by: -expense.amount)
        persist()
    }

    func updateExpense(_ expense: ExpenseEntry) {
        guard let index = data.expenses.firstIndex(where: { $0.id == expense.id }) else { return }
        let old = data.expenses[index]
        changeAsset(old.assetID, by: old.amount)
        data.expenses[index] = expense
        changeAsset(expense.assetID, by: -expense.amount)
        persist()
    }

    func deleteExpense(_ expense: ExpenseEntry) {
        changeAsset(expense.assetID, by: expense.amount)
        data.expenses.removeAll { $0.id == expense.id }
        persist()
    }

    func addIncome(_ entry: IncomeEntry) {
        data.income.append(entry)
        changeAsset(entry.assetID, by: entry.amount)
        persist()
    }

    func updateIncome(_ entry: IncomeEntry) {
        guard let index = data.income.firstIndex(where: { $0.id == entry.id }) else { return }
        let old = data.income[index]
        changeAsset(old.assetID, by: -old.amount)
        data.income[index] = entry
        changeAsset(entry.assetID, by: entry.amount)
        persist()
    }

    func deleteIncome(_ entry: IncomeEntry) {
        changeAsset(entry.assetID, by: -entry.amount)
        data.income.removeAll { $0.id == entry.id }
        persist()
    }

    func addSubscription(_ subscription: SubscriptionEntry) {
        data.subscriptions.append(subscription)
        persist()
        refreshNotifications()
    }

    func updateSubscription(_ subscription: SubscriptionEntry) {
        guard let index = data.subscriptions.firstIndex(where: { $0.id == subscription.id }) else { return }
        data.subscriptions[index] = subscription
        persist()
        refreshNotifications()
    }

    func deleteSubscription(_ subscription: SubscriptionEntry) {
        data.subscriptions.removeAll { $0.id == subscription.id }
        persist()
        refreshNotifications()
    }

    func recordSubscriptionPayment(_ subscription: SubscriptionEntry) {
        let expense = ExpenseEntry(
            title: subscription.name,
            amount: subscription.amount,
            date: Date(),
            category: "Subscriptions",
            paymentMethod: "Recurring payment",
            assetID: subscription.assetID,
            notes: subscription.notes,
            subscriptionID: subscription.id
        )
        addExpense(expense)
        guard let index = data.subscriptions.firstIndex(where: { $0.id == subscription.id }) else { return }
        var next = data.subscriptions[index].nextDueDate
        repeat { next = subscription.dateAfter(next) } while next <= Date()
        data.subscriptions[index].nextDueDate = next
        persist()
        refreshNotifications()
    }

    func updateSettings(_ settings: LedgerSettings) {
        data.settings = settings
        persist()
        refreshNotifications()
    }

    private func changeAsset(_ id: UUID?, by amount: Double) {
        guard let id, let index = data.assets.firstIndex(where: { $0.id == id }) else { return }
        data.assets[index].balance += amount
        data.assets[index].updatedAt = Date()
    }

    private func prepareFolders() throws {
        try FileManager.default.createDirectory(at: supportFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backupFolder, withIntermediateDirectories: true)
    }

    private func load() {
        do {
            try prepareFolders()
            guard FileManager.default.fileExists(atPath: dataFile.path) else { return }
            data = try decoder.decode(LedgerData.self, from: Data(contentsOf: dataFile))
        } catch {
            lastError = "Your saved data could not be opened: \(error.localizedDescription)"
        }
    }

    private func persist() {
        do {
            try prepareFolders()
            let encoded = try encoder.encode(data)
            try encoded.write(to: dataFile, options: .atomic)
            createDailyBackupIfNeeded()
        } catch {
            lastError = "Changes could not be saved: \(error.localizedDescription)"
        }
    }

    func createBackup() -> URL? {
        do {
            try prepareFolders()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let url = backupFolder.appendingPathComponent("Pocket-Ledger-\(formatter.string(from: Date())).json")
            try encoder.encode(data).write(to: url, options: .atomic)
            return url
        } catch {
            lastError = "Backup could not be created: \(error.localizedDescription)"
            return nil
        }
    }

    private func createDailyBackupIfNeeded() {
        if let last = data.lastBackupDate, Calendar.current.isDateInToday(last) { return }
        guard dataFile.path != "" else { return }
        do {
            try prepareFolders()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let url = backupFolder.appendingPathComponent("Pocket-Ledger-Auto-\(formatter.string(from: Date())).json")
            data.lastBackupDate = Date()
            try encoder.encode(data).write(to: url, options: .atomic)
            try encoder.encode(data).write(to: dataFile, options: .atomic)
            trimOldBackups()
        } catch {
            lastError = "Automatic backup could not be created: \(error.localizedDescription)"
        }
    }

    private func trimOldBackups() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: backupFolder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ), files.count > 30 else { return }
        let sorted = files.sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }
        for url in sorted.dropFirst(30) { try? FileManager.default.removeItem(at: url) }
    }

    func importBackup(from url: URL) {
        do {
            let imported = try decoder.decode(LedgerData.self, from: Data(contentsOf: url))
            _ = createBackup()
            data = imported
            persist()
            refreshNotifications()
        } catch {
            lastError = "That backup could not be restored: \(error.localizedDescription)"
        }
    }

    func exportCSV(to folder: URL) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let expenseHeader = "Date,Description,Category,Amount,Account,Payment Method,Notes\n"
            let expenseRows = data.expenses.sorted { $0.date < $1.date }.map {
                [dateString($0.date), $0.title, $0.category, String($0.amount), assetName(for: $0.assetID), $0.paymentMethod, $0.notes]
                    .map(csvEscape).joined(separator: ",")
            }.joined(separator: "\n")
            try (expenseHeader + expenseRows).write(to: folder.appendingPathComponent("expenses.csv"), atomically: true, encoding: .utf8)

            let incomeHeader = "Date,Source,Category,Amount,Account,Notes\n"
            let incomeRows = data.income.sorted { $0.date < $1.date }.map {
                [dateString($0.date), $0.source, $0.category, String($0.amount), assetName(for: $0.assetID), $0.notes]
                    .map(csvEscape).joined(separator: ",")
            }.joined(separator: "\n")
            try (incomeHeader + incomeRows).write(to: folder.appendingPathComponent("income.csv"), atomically: true, encoding: .utf8)
        } catch {
            lastError = "CSV files could not be exported: \(error.localizedDescription)"
        }
    }

    private func dateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }

    private func csvEscape(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func refreshNotifications() {
        guard schedulesNotifications else { return }
        NotificationManager.shared.reschedule(from: data)
    }
}

import AppKit
import Charts
import SwiftUI
import UserNotifications

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "Home"
    case subscriptions = "Subscriptions"
    case expenses = "Expenses"
    case income = "Income"
    case assets = "Assets & balances"
    case settings = "Settings & backup"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .dashboard: return "house.fill"
        case .subscriptions: return "calendar.badge.clock"
        case .expenses: return "arrow.up.right.circle.fill"
        case .income: return "arrow.down.left.circle.fill"
        case .assets: return "wallet.bifold.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct ContentView: View {
    @State private var selection: AppSection? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
                    .padding(.vertical, 5)
            }
            .navigationTitle("Pocket Ledger")
            .navigationSplitViewColumnWidth(min: 210, ideal: 235)
        } detail: {
            Group {
                switch selection ?? .dashboard {
                case .dashboard: DashboardView()
                case .subscriptions: SubscriptionsView()
                case .expenses: ExpensesView()
                case .income: IncomeView()
                case .assets: AssetsView()
                case .settings: SettingsView()
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.largeTitle.bold())
                Text(subtitle).foregroundStyle(.secondary)
            }
            Spacer()
            if let actionTitle, let action {
                Button(action: action) { Label(actionTitle, systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title2.bold()).lineLimit(1).minimumScaleFactor(0.7)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.separator.opacity(0.35)))
    }
}

struct SpendingPoint: Identifiable {
    let id = UUID()
    let month: Date
    let amount: Double
}

struct CategoryPoint: Identifiable {
    let category: String
    let amount: Double
    var id: String { category }
}

struct DashboardView: View {
    @EnvironmentObject var store: LedgerStore

    private var sixMonthSpending: [SpendingPoint] {
        let calendar = Calendar.current
        return (0..<6).reversed().compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: -offset, to: Date()) else { return nil }
            let total = store.data.expenses.filter {
                calendar.isDate($0.date, equalTo: month, toGranularity: .month)
            }.reduce(0) { $0 + $1.amount }
            return SpendingPoint(month: month, amount: total)
        }
    }

    private var categorySpending: [CategoryPoint] {
        let grouped = Dictionary(grouping: store.data.expenses.filter {
            $0.date >= Date().startOfMonth && $0.date <= Date().endOfMonth
        }, by: \.category)
        return grouped.map { CategoryPoint(category: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.amount > $1.amount }
    }

    private var upcoming: [SubscriptionEntry] {
        store.data.subscriptions.filter(\.isActive).sorted { $0.nextDueDate < $1.nextDueDate }.prefix(5).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "Your money", subtitle: "A private overview stored only on this Mac")

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    StatCard(title: "Current assets", value: store.currency(store.totalAssets), subtitle: "Across included balances", icon: "wallet.bifold.fill", color: .blue)
                    StatCard(title: "Spent this month", value: store.currency(store.thisMonthExpenses), subtitle: "All recorded expenses", icon: "arrow.up.right", color: .orange)
                    StatCard(title: "Income this month", value: store.currency(store.thisMonthIncome), subtitle: "Salary, pocket money & more", icon: "arrow.down.left", color: .green)
                    StatCard(title: "Monthly subscriptions", value: store.currency(store.monthlySubscriptionCost), subtitle: "Estimated recurring cost", icon: "repeat", color: .purple)
                    StatCard(title: "Net cash flow", value: store.currency(store.thisMonthIncome - store.thisMonthExpenses), subtitle: "Income minus expenses", icon: "equal.circle.fill", color: store.thisMonthIncome >= store.thisMonthExpenses ? .green : .red)
                    StatCard(title: "Active subscriptions", value: "\(store.data.subscriptions.filter(\.isActive).count)", subtitle: "Payments being tracked", icon: "calendar.badge.clock", color: .indigo)
                }

                HStack(alignment: .top, spacing: 16) {
                    GroupBox("Spending over six months") {
                        if store.data.expenses.isEmpty {
                            EmptyChart(message: "Your spending chart will appear here")
                        } else {
                            Chart(sixMonthSpending) { point in
                                BarMark(x: .value("Month", point.month, unit: .month), y: .value("Spent", point.amount))
                                    .foregroundStyle(.blue.gradient)
                                    .cornerRadius(5)
                            }
                            .chartYAxis { AxisMarks(position: .leading) }
                            .frame(height: 220)
                            .padding(.top, 8)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    GroupBox("This month by category") {
                        if categorySpending.isEmpty {
                            EmptyChart(message: "Add an expense to see categories")
                        } else {
                            Chart(categorySpending) { point in
                                SectorMark(angle: .value("Amount", point.amount), innerRadius: .ratio(0.58), angularInset: 2)
                                    .foregroundStyle(by: .value("Category", point.category))
                            }
                            .chartLegend(position: .bottom, spacing: 8)
                            .frame(height: 220)
                            .padding(.top, 8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                GroupBox("Upcoming subscription payments") {
                    if upcoming.isEmpty {
                        Text("No active subscriptions yet.").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 65)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(upcoming) { subscription in
                                HStack {
                                    Image(systemName: "play.rectangle.fill").foregroundStyle(.purple).frame(width: 28)
                                    VStack(alignment: .leading) {
                                        Text(subscription.name).fontWeight(.semibold)
                                        Text(subscription.nextDueDate, format: .dateTime.day().month().year()).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(store.currency(subscription.amount)).fontWeight(.semibold)
                                }
                                .padding(.vertical, 9)
                                if subscription.id != upcoming.last?.id { Divider() }
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
    }
}

struct EmptyChart: View {
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis").font(.largeTitle).foregroundStyle(.tertiary)
            Text(message).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

struct SubscriptionsView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var presented: SubscriptionEntry?
    @State private var isNew = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Subscriptions", subtitle: "Track recurring payments and upcoming due dates", actionTitle: "Add subscription") {
                isNew = true
                presented = SubscriptionEntry(name: "", amount: 0, cycle: .monthly, nextDueDate: Date())
            }
            .padding(28)

            if store.data.subscriptions.isEmpty {
                EmptyState(icon: "calendar.badge.plus", title: "No subscriptions yet", message: "Add Netflix, HBO, Snapchat, Spotify, or any recurring payment.")
            } else {
                List {
                    ForEach(store.data.subscriptions.sorted { $0.nextDueDate < $1.nextDueDate }) { subscription in
                        HStack(spacing: 14) {
                            Image(systemName: subscription.isActive ? "repeat.circle.fill" : "pause.circle.fill")
                                .font(.title2).foregroundStyle(subscription.isActive ? .purple : .secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(subscription.name).font(.headline)
                                    if !subscription.isActive { Text("Paused").font(.caption).padding(.horizontal, 7).padding(.vertical, 2).background(.secondary.opacity(0.15), in: Capsule()) }
                                }
                                Text("Due \(subscription.nextDueDate.formatted(date: .abbreviated, time: .omitted)) • \(subscription.cycle.rawValue) • \(store.assetName(for: subscription.assetID))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(store.currency(subscription.amount)).font(.headline)
                                Text("\(subscription.reminderDays) day reminder").font(.caption).foregroundStyle(.secondary)
                            }
                            Button("Record paid") { store.recordSubscriptionPayment(subscription) }
                                .disabled(!subscription.isActive)
                            Menu {
                                Button("Edit") { isNew = false; presented = subscription }
                                Button(subscription.isActive ? "Pause" : "Activate") {
                                    var changed = subscription
                                    changed.isActive.toggle()
                                    store.updateSubscription(changed)
                                }
                                Divider()
                                Button("Delete", role: .destructive) { store.deleteSubscription(subscription) }
                            } label: { Image(systemName: "ellipsis.circle") }
                            .menuStyle(.borderlessButton).frame(width: 28)
                        }
                        .padding(.vertical, 7)
                    }
                }
            }
        }
        .sheet(item: $presented) { item in
            SubscriptionEditor(item: item, isNew: isNew) { value in
                if isNew { store.addSubscription(value) } else { store.updateSubscription(value) }
                presented = nil
            }
        }
    }
}

struct ExpensesView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var presented: ExpenseEntry?
    @State private var isNew = false
    @State private var search = ""

    private var filtered: [ExpenseEntry] {
        store.data.expenses.filter {
            search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.category.localizedCaseInsensitiveContains(search)
        }.sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Expenses", subtitle: "Everyday spending automatically reduces the selected balance", actionTitle: "Add expense") {
                isNew = true
                presented = ExpenseEntry(title: "", amount: 0, date: Date(), category: "Food")
            }
            .padding(28)
            if store.data.expenses.isEmpty {
                EmptyState(icon: "cart.badge.plus", title: "No expenses recorded", message: "Add food, shopping, transport, bills, or any other spending.")
            } else {
                List {
                    ForEach(filtered) { expense in
                        TransactionRow(icon: "arrow.up.right", color: .orange, title: expense.title, subtitle: "\(expense.category) • \(expense.date.formatted(date: .abbreviated, time: .omitted)) • \(store.assetName(for: expense.assetID))", amount: "−\(store.currency(expense.amount))") {
                            isNew = false; presented = expense
                        } delete: { store.deleteExpense(expense) }
                    }
                }
                .searchable(text: $search, prompt: "Search expenses")
            }
        }
        .sheet(item: $presented) { item in
            ExpenseEditor(item: item, isNew: isNew) { value in
                if isNew { store.addExpense(value) } else { store.updateExpense(value) }
                presented = nil
            }
        }
    }
}

struct IncomeView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var presented: IncomeEntry?
    @State private var isNew = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Income", subtitle: "Salary, pocket money, gifts, and other money received", actionTitle: "Add income") {
                isNew = true
                presented = IncomeEntry(source: "", amount: 0, date: Date(), category: "Salary")
            }
            .padding(28)
            if store.data.income.isEmpty {
                EmptyState(icon: "banknote.fill", title: "No income recorded", message: "Add salary or pocket money and choose which balance receives it.")
            } else {
                List {
                    ForEach(store.data.income.sorted { $0.date > $1.date }) { income in
                        TransactionRow(icon: "arrow.down.left", color: .green, title: income.source, subtitle: "\(income.category) • \(income.date.formatted(date: .abbreviated, time: .omitted)) • \(store.assetName(for: income.assetID))", amount: "+\(store.currency(income.amount))") {
                            isNew = false; presented = income
                        } delete: { store.deleteIncome(income) }
                    }
                }
            }
        }
        .sheet(item: $presented) { item in
            IncomeEditor(item: item, isNew: isNew) { value in
                if isNew { store.addIncome(value) } else { store.updateIncome(value) }
                presented = nil
            }
        }
    }
}

struct TransactionRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let amount: String
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 34, height: 34).background(color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(amount).font(.headline).foregroundStyle(color)
            Menu {
                Button("Edit", action: edit)
                Divider()
                Button("Delete", role: .destructive, action: delete)
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).frame(width: 28)
        }
        .padding(.vertical, 7)
    }
}

struct AssetsView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var presented: AssetAccount?
    @State private var isNew = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "Assets & balances", subtitle: "Cash, bank accounts, savings, investments, and property", actionTitle: "Add asset") {
                    isNew = true
                    presented = AssetAccount(name: "", kind: .cash, balance: 0)
                }
                StatCard(title: "Total current assets", value: store.currency(store.totalAssets), subtitle: "Only balances marked ‘Include in total’", icon: "wallet.bifold.fill", color: .blue)
                    .frame(maxWidth: 420)

                if store.data.assets.isEmpty {
                    EmptyState(icon: "wallet.bifold", title: "Add your first balance", message: "Start with Cash, Wallet, or a bank account. Income and expenses can update it automatically.")
                        .frame(minHeight: 300)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                        ForEach(store.data.assets) { asset in
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Image(systemName: asset.kind.symbol).font(.title2).foregroundStyle(.blue)
                                    VStack(alignment: .leading) {
                                        Text(asset.name).font(.headline)
                                        Text(asset.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Menu {
                                        Button("Edit or adjust balance") { isNew = false; presented = asset }
                                        Divider()
                                        Button("Delete", role: .destructive) { store.deleteAsset(asset) }
                                    } label: { Image(systemName: "ellipsis.circle") }
                                    .menuStyle(.borderlessButton).frame(width: 28)
                                }
                                Text(store.currency(asset.balance)).font(.title.bold())
                                HStack {
                                    Text(asset.includeInTotal ? "Included in total" : "Not included in total")
                                    Spacer()
                                    Text("Updated \(asset.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(18)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.separator.opacity(0.35)))
                        }
                    }
                }
            }
            .padding(28)
        }
        .sheet(item: $presented) { item in
            AssetEditor(item: item, isNew: isNew) { value in
                if isNew { store.addAsset(value) } else { store.updateAsset(value) }
                presented = nil
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var settings = LedgerSettings()
    @State private var notificationText = "Checking…"
    @State private var confirmation = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "Settings & backup", subtitle: "Everything remains private and local to this Mac")
                GroupBox("Display") {
                    Form {
                        TextField("Currency code", text: $settings.currencyCode)
                            .onSubmit { saveSettings() }
                        Picker("Reminder time", selection: $settings.reminderHour) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(hour.formatted(.number.precision(.integerLength(2))) + ":00").tag(hour)
                            }
                        }
                        Button("Save settings", action: saveSettings)
                    }
                    .padding(8)
                }

                GroupBox("Payment reminders") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Mac notifications").font(.headline)
                            Text(notificationText).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Enable notifications") {
                            Task {
                                let granted = await NotificationManager.shared.requestPermission()
                                notificationText = granted ? "Enabled. Upcoming reminders are scheduled locally." : "Not enabled. You can allow notifications in System Settings."
                                if granted { NotificationManager.shared.reschedule(from: store.data) }
                            }
                        }
                    }
                    .padding(8)
                }

                GroupBox("Local data and backups") {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Changes are saved immediately. Pocket Ledger also keeps up to 30 dated backups on this Mac.")
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Create backup now") {
                                if store.createBackup() != nil { confirmation = "Backup created." }
                            }
                            Button("Open backup folder") { NSWorkspace.shared.open(store.backupFolder) }
                            Button("Restore a backup…", action: restoreBackup)
                            Button("Export CSV files…", action: exportCSV)
                        }
                        if !confirmation.isEmpty { Text(confirmation).font(.caption).foregroundStyle(.green) }
                        Text(store.backupFolder.path).font(.caption).foregroundStyle(.tertiary).textSelection(.enabled)
                    }
                    .padding(8)
                }

                GroupBox("Privacy") {
                    Label("No account, advertisements, analytics, cloud storage, or internet connection is used.", systemImage: "lock.shield.fill")
                        .padding(8)
                }
            }
            .padding(28)
        }
        .onAppear {
            settings = store.data.settings
            Task {
                let status = await NotificationManager.shared.status()
                switch status {
                case .authorized, .provisional, .ephemeral: notificationText = "Enabled. Upcoming reminders are scheduled locally."
                case .denied: notificationText = "Disabled in System Settings."
                case .notDetermined: notificationText = "Not enabled yet."
                @unknown default: notificationText = "Notification status is unavailable."
                }
            }
        }
    }

    private func saveSettings() {
        settings.currencyCode = settings.currencyCode.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if settings.currencyCode.count != 3 { settings.currencyCode = "USD" }
        store.updateSettings(settings)
        confirmation = "Settings saved."
    }

    private func restoreBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            store.importBackup(from: url)
            settings = store.data.settings
            confirmation = "Backup restored."
        }
    }

    private func exportCSV() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        if panel.runModal() == .OK, let url = panel.url {
            store.exportCSV(to: url)
            confirmation = "CSV files exported."
        }
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 45)).foregroundStyle(.tertiary)
            Text(title).font(.title2.bold())
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 430)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

private let expenseCategories = ["Food", "Groceries", "Online Shopping", "Transport", "Entertainment", "Bills", "Healthcare", "Education", "Subscriptions", "Other"]
private let incomeCategories = ["Salary", "Pocket Money", "Freelance", "Gift", "Investment Return", "Refund", "Other"]

struct ExpenseEditor: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) var dismiss
    @State var item: ExpenseEntry
    let isNew: Bool
    let onSave: (ExpenseEntry) -> Void

    var body: some View {
        EditorContainer(title: isNew ? "Add expense" : "Edit expense", canSave: !item.title.trimmingCharacters(in: .whitespaces).isEmpty && item.amount > 0, onCancel: { dismiss() }, onSave: { onSave(item) }) {
            Form {
                TextField("Description", text: $item.title)
                TextField("Amount", value: $item.amount, format: .number.precision(.fractionLength(0...2)))
                DatePicker("Date", selection: $item.date, displayedComponents: .date)
                Picker("Category", selection: $item.category) {
                    ForEach(expenseCategories, id: \.self) { Text($0).tag($0) }
                }
                Picker("Paid from", selection: $item.assetID) {
                    Text("Do not update a balance").tag(UUID?.none)
                    ForEach(store.data.assets) { Text($0.name).tag(Optional($0.id)) }
                }
                TextField("Payment method (optional)", text: $item.paymentMethod)
                TextField("Notes (optional)", text: $item.notes, axis: .vertical)
            }
        }
    }
}

struct IncomeEditor: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) var dismiss
    @State var item: IncomeEntry
    let isNew: Bool
    let onSave: (IncomeEntry) -> Void

    var body: some View {
        EditorContainer(title: isNew ? "Add income" : "Edit income", canSave: !item.source.trimmingCharacters(in: .whitespaces).isEmpty && item.amount > 0, onCancel: { dismiss() }, onSave: { onSave(item) }) {
            Form {
                TextField("Source", text: $item.source)
                TextField("Amount", value: $item.amount, format: .number.precision(.fractionLength(0...2)))
                DatePicker("Date", selection: $item.date, displayedComponents: .date)
                Picker("Category", selection: $item.category) {
                    ForEach(incomeCategories, id: \.self) { Text($0).tag($0) }
                }
                Picker("Add money to", selection: $item.assetID) {
                    Text("Do not update a balance").tag(UUID?.none)
                    ForEach(store.data.assets) { Text($0.name).tag(Optional($0.id)) }
                }
                TextField("Notes (optional)", text: $item.notes, axis: .vertical)
            }
        }
    }
}

struct AssetEditor: View {
    @Environment(\.dismiss) var dismiss
    @State var item: AssetAccount
    let isNew: Bool
    let onSave: (AssetAccount) -> Void

    var body: some View {
        EditorContainer(title: isNew ? "Add asset or balance" : "Edit asset or balance", canSave: !item.name.trimmingCharacters(in: .whitespaces).isEmpty, onCancel: { dismiss() }, onSave: { onSave(item) }) {
            Form {
                TextField("Name", text: $item.name)
                Picker("Type", selection: $item.kind) {
                    ForEach(AssetKind.allCases) { Text($0.rawValue).tag($0) }
                }
                TextField("Current value", value: $item.balance, format: .number.precision(.fractionLength(0...2)))
                Toggle("Include in total assets", isOn: $item.includeInTotal)
                TextField("Notes (optional)", text: $item.notes, axis: .vertical)
                if !isNew {
                    Text("Editing the current value is a manual balance adjustment. Income and expenses linked to this account update it automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct SubscriptionEditor: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) var dismiss
    @State var item: SubscriptionEntry
    let isNew: Bool
    let onSave: (SubscriptionEntry) -> Void

    var body: some View {
        EditorContainer(title: isNew ? "Add subscription" : "Edit subscription", canSave: !item.name.trimmingCharacters(in: .whitespaces).isEmpty && item.amount > 0, onCancel: { dismiss() }, onSave: { onSave(item) }) {
            Form {
                TextField("Service name", text: $item.name)
                TextField("Payment amount", value: $item.amount, format: .number.precision(.fractionLength(0...2)))
                Picker("Billing cycle", selection: $item.cycle) {
                    ForEach(BillingCycle.allCases) { Text($0.rawValue).tag($0) }
                }
                if item.cycle == .custom {
                    Stepper("Every \(item.customDays) days", value: $item.customDays, in: 1...730)
                }
                DatePicker("Next due date", selection: $item.nextDueDate, displayedComponents: .date)
                Stepper("Remind \(item.reminderDays) day\(item.reminderDays == 1 ? "" : "s") before", value: $item.reminderDays, in: 0...30)
                Picker("Pay from", selection: $item.assetID) {
                    Text("Do not update a balance").tag(UUID?.none)
                    ForEach(store.data.assets) { Text($0.name).tag(Optional($0.id)) }
                }
                Toggle("Active subscription", isOn: $item.isActive)
                TextField("Notes (optional)", text: $item.notes, axis: .vertical)
            }
        }
    }
}

struct EditorContainer<Content: View>: View {
    let title: String
    let canSave: Bool
    let onCancel: () -> Void
    let onSave: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.title2.bold())
                Spacer()
            }
            .padding(22)
            Divider()
            content.padding(22)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save", action: onSave).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!canSave)
            }
            .padding(18)
        }
        .frame(width: 540)
    }
}

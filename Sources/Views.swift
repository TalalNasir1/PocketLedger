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
    var secondaryActionTitle: String?
    var secondaryActionIcon = "arrow.left.arrow.right"
    var secondaryAction: (() -> Void)?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.largeTitle.bold())
                Text(subtitle).foregroundStyle(.secondary)
            }
            Spacer()
            if let secondaryActionTitle, let secondaryAction {
                Button(action: secondaryAction) {
                    Label(secondaryActionTitle, systemImage: secondaryActionIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
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
    var privacyHidden = false
    var privacyAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 7) {
                    Text(privacyHidden ? "••••••" : value)
                        .font(.title2.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityLabel(privacyHidden ? "Amount hidden" : value)
                    if let privacyAction {
                        Button(action: privacyAction) {
                            Image(systemName: privacyHidden ? "eye" : "eye.slash")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help(privacyHidden ? "Show total assets" : "Hide total assets")
                        .accessibilityLabel(privacyHidden ? "Show total assets" : "Hide total assets")
                    }
                }
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
    let date: Date
    let amount: Double
}

struct CategoryPoint: Identifiable {
    let category: String
    let amount: Double
    var id: String { category }
}

enum DashboardPeriod: String, CaseIterable, Identifiable {
    case month = "Monthly"
    case year = "Yearly"
    var id: String { rawValue }
}

enum TransactionPeriod: String, CaseIterable, Identifiable {
    case month = "Month"
    case year = "Year"
    case all = "All"
    var id: String { rawValue }
}

struct DashboardView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var hideTotalAssets = true
    @State private var trendPeriod: DashboardPeriod = .month
    @State private var categoryPeriod: DashboardPeriod = .month
    @State private var hoveredCategory: CategoryPoint?

    private var trendSpending: [SpendingPoint] {
        let calendar = Calendar.current
        let component: Calendar.Component = trendPeriod == .month ? .month : .year
        let count = trendPeriod == .month ? 6 : 5
        return (0..<count).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: component, value: -offset, to: Date()) else { return nil }
            let total = store.data.expenses.filter {
                calendar.isDate($0.date, equalTo: date, toGranularity: component)
            }.reduce(0) { $0 + $1.amount }
            return SpendingPoint(date: date, amount: total)
        }
    }

    private var categorySpending: [CategoryPoint] {
        let grouped = Dictionary(grouping: store.data.expenses.filter {
            categoryPeriod == .month
                ? ($0.date >= Date().startOfMonth && $0.date <= Date().endOfMonth)
                : ($0.date >= Date().startOfYear && $0.date <= Date().endOfYear)
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
                    StatCard(
                        title: "Current assets",
                        value: store.currency(store.totalAssets),
                        subtitle: "Across included balances",
                        icon: "wallet.bifold.fill",
                        color: .blue,
                        privacyHidden: hideTotalAssets,
                        privacyAction: { hideTotalAssets.toggle() }
                    )
                    StatCard(title: "Spent this month", value: store.currency(store.thisMonthExpenses), subtitle: "All recorded expenses", icon: "arrow.up.right", color: .orange)
                    StatCard(title: "Income this month", value: store.currency(store.thisMonthIncome), subtitle: "Salary, pocket money & more", icon: "arrow.down.left", color: .green)
                    StatCard(title: "Monthly subscriptions", value: store.currency(store.monthlySubscriptionCost), subtitle: "Estimated recurring cost", icon: "repeat", color: .purple)
                    StatCard(title: "Net cash flow", value: store.currency(store.thisMonthIncome - store.thisMonthExpenses), subtitle: "Income minus expenses", icon: "equal.circle.fill", color: store.thisMonthIncome >= store.thisMonthExpenses ? .green : .red)
                    StatCard(title: "Active subscriptions", value: "\(store.data.subscriptions.filter(\.isActive).count)", subtitle: "Payments being tracked", icon: "calendar.badge.clock", color: .indigo)
                }

                HStack(alignment: .top, spacing: 16) {
                    GroupBox {
                        VStack(spacing: 8) {
                            Picker("Chart period", selection: $trendPeriod) {
                                ForEach(DashboardPeriod.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(maxWidth: 220)
                            if store.data.expenses.isEmpty {
                                EmptyChart(message: "Your spending chart will appear here")
                            } else {
                                Chart(trendSpending) { point in
                                    BarMark(
                                        x: .value(trendPeriod == .month ? "Month" : "Year", point.date, unit: trendPeriod == .month ? .month : .year),
                                        y: .value("Spent", point.amount)
                                    )
                                    .foregroundStyle(.blue.gradient)
                                    .cornerRadius(5)
                                }
                                .chartYAxis { AxisMarks(position: .leading) }
                                .frame(height: 220)
                                .padding(.top, 4)
                            }
                        }
                    } label: {
                        Text(trendPeriod == .month ? "Spending over six months" : "Spending over five years")
                    }
                    .frame(maxWidth: .infinity)

                    GroupBox {
                        VStack(spacing: 8) {
                            Picker("Category period", selection: $categoryPeriod) {
                                ForEach(DashboardPeriod.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(maxWidth: 220)
                            .onChange(of: categoryPeriod) { _, _ in hoveredCategory = nil }
                            if categorySpending.isEmpty {
                                EmptyChart(message: "Add an expense to see categories")
                            } else {
                                ZStack {
                                    Chart(categorySpending) { point in
                                        SectorMark(
                                            angle: .value("Amount", point.amount),
                                            innerRadius: .ratio(0.58),
                                            angularInset: 2
                                        )
                                        .foregroundStyle(by: .value("Category", point.category))
                                        .opacity(hoveredCategory == nil || hoveredCategory?.id == point.id ? 1 : 0.42)
                                    }
                                    .chartLegend(position: .bottom, spacing: 8)
                                    .chartOverlay { proxy in
                                        GeometryReader { geometry in
                                            Rectangle()
                                                .fill(.clear)
                                                .contentShape(Rectangle())
                                                .onContinuousHover { phase in
                                                    switch phase {
                                                    case .active(let location):
                                                        hoveredCategory = category(at: location, proxy: proxy, geometry: geometry)
                                                    case .ended:
                                                        hoveredCategory = nil
                                                    }
                                                }
                                        }
                                    }
                                    .frame(height: 220)

                                    VStack(spacing: 2) {
                                        Text(hoveredCategory?.category ?? "Total")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(store.currency(hoveredCategory?.amount ?? categorySpending.reduce(0) { $0 + $1.amount }))
                                            .font(.headline)
                                    }
                                    .allowsHitTesting(false)
                                }
                                Text("Hover over a slice to see its category total.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } label: {
                        Text(categoryPeriod == .month ? "This month by category" : "This year by category")
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

    private func category(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> CategoryPoint? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let frame = geometry[plotFrame]
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = hypot(dx, dy)
        let outerRadius = min(frame.width, frame.height) / 2
        guard distance <= outerRadius, distance >= outerRadius * 0.45 else { return nil }

        var angle = atan2(dx, -dy)
        if angle < 0 { angle += 2 * .pi }
        let total = categorySpending.reduce(0) { $0 + $1.amount }
        guard total > 0 else { return nil }
        let target = angle / (2 * .pi) * total
        var running = 0.0
        for point in categorySpending {
            running += point.amount
            if target <= running { return point }
        }
        return categorySpending.last
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
    @State private var paymentSubscription: SubscriptionEntry?
    @State private var isNew = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Subscriptions", subtitle: "Track recurring payments and upcoming due dates", actionTitle: "Add subscription") {
                isNew = true
                presented = SubscriptionEntry(name: "", amount: 0, cycle: .monthly, nextDueDate: Date(), assetID: store.data.assets.first?.id)
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
                                if let trialEnd = subscription.trialEndDate {
                                    Label(
                                        "Free trial ends \(trialEnd.formatted(date: .abbreviated, time: .omitted))",
                                        systemImage: "hourglass"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(store.currency(subscription.amount)).font(.headline)
                                Text("\(subscription.reminderDays) day reminder • \(store.currency(store.totalSpent(on: subscription))) spent")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Button("Record paid") { paymentSubscription = subscription }
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
        .sheet(item: $paymentSubscription) { subscription in
            SubscriptionPaymentSheet(subscription: subscription) { amount in
                store.recordSubscriptionPayment(subscription, amount: amount)
                paymentSubscription = nil
            }
        }
    }
}

struct ExpensesView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var presented: ExpenseEntry?
    @State private var isNew = false
    @State private var search = ""
    @State private var period: TransactionPeriod = .month
    @State private var referenceDate = Date()
    @State private var showingTransfer = false

    private var filtered: [ExpenseEntry] {
        store.data.expenses.filter {
            matches($0.date) &&
            (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.category.localizedCaseInsensitiveContains(search))
        }.sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "Expenses",
                subtitle: "Everyday spending automatically reduces the selected balance",
                secondaryActionTitle: "Transfer money",
                secondaryAction: { showingTransfer = true },
                actionTitle: "Add expense"
            ) {
                isNew = true
                presented = ExpenseEntry(title: "", amount: 0, date: Date(), category: "Food", assetID: store.data.assets.first?.id)
            }
            .padding(28)
            PeriodFilterBar(
                period: $period,
                referenceDate: $referenceDate,
                totalLabel: "Expenses",
                total: store.currency(filtered.reduce(0) { $0 + $1.amount })
            )
            .padding(.horizontal, 28)
            .padding(.bottom, 14)
            if store.data.expenses.isEmpty {
                EmptyState(icon: "cart.badge.plus", title: "No expenses recorded", message: "Add food, shopping, transport, bills, or any other spending.")
            } else if filtered.isEmpty {
                EmptyState(icon: "calendar", title: "No expenses in this period", message: "Choose another month or year, or add a new expense.")
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
        .sheet(isPresented: $showingTransfer) {
            TransferEditor { transfer in
                _ = store.addTransfer(transfer)
                showingTransfer = false
            }
        }
    }

    private func matches(_ date: Date) -> Bool {
        switch period {
        case .month: return Calendar.current.isDate(date, equalTo: referenceDate, toGranularity: .month)
        case .year: return Calendar.current.isDate(date, equalTo: referenceDate, toGranularity: .year)
        case .all: return true
        }
    }
}

struct IncomeView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var presented: IncomeEntry?
    @State private var isNew = false
    @State private var period: TransactionPeriod = .month
    @State private var referenceDate = Date()

    private var filtered: [IncomeEntry] {
        store.data.income.filter { matches($0.date) }.sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Income", subtitle: "Salary, pocket money, gifts, and other money received", actionTitle: "Add income") {
                isNew = true
                presented = IncomeEntry(source: "", amount: 0, date: Date(), category: "Salary", assetID: store.data.assets.first?.id)
            }
            .padding(28)
            PeriodFilterBar(
                period: $period,
                referenceDate: $referenceDate,
                totalLabel: "Income",
                total: store.currency(filtered.reduce(0) { $0 + $1.amount })
            )
            .padding(.horizontal, 28)
            .padding(.bottom, 14)
            if store.data.income.isEmpty {
                EmptyState(icon: "banknote.fill", title: "No income recorded", message: "Add salary or pocket money and choose which balance receives it.")
            } else if filtered.isEmpty {
                EmptyState(icon: "calendar", title: "No income in this period", message: "Choose another month or year, or add new income.")
            } else {
                List {
                    ForEach(filtered) { income in
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

    private func matches(_ date: Date) -> Bool {
        switch period {
        case .month: return Calendar.current.isDate(date, equalTo: referenceDate, toGranularity: .month)
        case .year: return Calendar.current.isDate(date, equalTo: referenceDate, toGranularity: .year)
        case .all: return true
        }
    }
}

struct PeriodFilterBar: View {
    @Binding var period: TransactionPeriod
    @Binding var referenceDate: Date
    let totalLabel: String
    let total: String

    private var periodTitle: String {
        switch period {
        case .month: return referenceDate.formatted(.dateTime.month(.wide).year())
        case .year: return referenceDate.formatted(.dateTime.year())
        case .all: return "All time"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Picker("Period", selection: $period) {
                ForEach(TransactionPeriod.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 230)

            if period != .all {
                HStack(spacing: 6) {
                    Button { move(-1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.borderless)
                        .help("Previous \(period.rawValue.lowercased())")
                    Text(periodTitle).fontWeight(.semibold).frame(minWidth: 125)
                    Button { move(1) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.borderless)
                        .help("Next \(period.rawValue.lowercased())")
                }
            } else {
                Text(periodTitle).fontWeight(.semibold).frame(minWidth: 125)
            }
            Spacer()
            Text("\(totalLabel):").foregroundStyle(.secondary)
            Text(total).font(.headline)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: period) { _, _ in referenceDate = Date() }
    }

    private func move(_ value: Int) {
        let component: Calendar.Component = period == .year ? .year : .month
        referenceDate = Calendar.current.date(byAdding: component, value: value, to: referenceDate) ?? referenceDate
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
    @State private var showingTransfer = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    title: "Assets & balances",
                    subtitle: "Cash, accounts, investments, property, phones, and laptops",
                    secondaryActionTitle: "Transfer money",
                    secondaryAction: { showingTransfer = true },
                    actionTitle: "Add asset"
                ) {
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

                if !store.data.transfers.isEmpty {
                    GroupBox("Recent transfers") {
                        VStack(spacing: 0) {
                            ForEach(store.data.transfers.sorted { $0.date > $1.date }.prefix(8)) { transfer in
                                HStack(spacing: 12) {
                                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.blue)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(store.assetName(for: transfer.fromAssetID)) → \(store.assetName(for: transfer.toAssetID))")
                                            .fontWeight(.semibold)
                                        Text(transfer.date.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(store.currency(transfer.amount)).fontWeight(.semibold)
                                    Button(role: .destructive) {
                                        store.deleteTransfer(transfer)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Delete and reverse this transfer")
                                }
                                .padding(.vertical, 9)
                                if transfer.id != store.data.transfers.sorted(by: { $0.date > $1.date }).prefix(8).last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding(.horizontal, 8)
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
        .sheet(isPresented: $showingTransfer) {
            TransferEditor { transfer in
                _ = store.addTransfer(transfer)
                showingTransfer = false
            }
        }
    }
}

struct AppUnlockView: View {
    @EnvironmentObject var appLock: AppLockManager
    @State private var pin = ""
    @State private var message = ""
    @State private var attemptedBiometrics = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.blue.opacity(0.18), Color.purple.opacity(0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 92, height: 92)
                    .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))

                VStack(spacing: 7) {
                    Text("Pocket Ledger is locked").font(.largeTitle.bold())
                    Text("Enter your four-digit passcode or use \(appLock.biometryName).")
                        .foregroundStyle(.secondary)
                }

                SecureField("4-digit passcode", text: $pin)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3.monospacedDigit())
                    .frame(width: 240)
                    .onSubmit(unlock)
                    .onChange(of: pin) { _, newValue in
                        pin = String(newValue.filter(\.isNumber).prefix(4))
                        message = ""
                    }

                if !message.isEmpty {
                    Text(message).font(.callout).foregroundStyle(.red)
                }

                HStack(spacing: 12) {
                    Button("Unlock", action: unlock)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!AppLockManager.isValidPIN(pin))

                    if appLock.biometricsEnabled && appLock.canUseBiometrics {
                        Button {
                            Task { _ = await appLock.authenticateWithBiometrics() }
                        } label: {
                            Label("Use \(appLock.biometryName)", systemImage: "touchid")
                        }
                        .controlSize(.large)
                    }
                }

                Text("Your financial records remain stored locally on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(44)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.35)))
            .shadow(color: .black.opacity(0.12), radius: 24, y: 12)
        }
        .task {
            guard !attemptedBiometrics, appLock.biometricsEnabled, appLock.canUseBiometrics else { return }
            attemptedBiometrics = true
            _ = await appLock.authenticateWithBiometrics()
        }
    }

    private func unlock() {
        if appLock.unlock(with: pin) {
            pin = ""
        } else {
            message = "Incorrect passcode. Please try again."
            pin = ""
        }
    }
}

enum PasscodeAction: String, Identifiable {
    case setup
    case change
    case remove
    var id: String { rawValue }
}

struct PasscodeEditorSheet: View {
    @EnvironmentObject var appLock: AppLockManager
    @Environment(\.dismiss) var dismiss
    let action: PasscodeAction
    @State private var currentPIN = ""
    @State private var newPIN = ""
    @State private var confirmation = ""
    @State private var errorMessage = ""

    private var title: String {
        switch action {
        case .setup: return "Set app passcode"
        case .change: return "Change app passcode"
        case .remove: return "Remove app passcode"
        }
    }

    private var canContinue: Bool {
        switch action {
        case .setup:
            return AppLockManager.isValidPIN(newPIN) && AppLockManager.isValidPIN(confirmation)
        case .change:
            return AppLockManager.isValidPIN(currentPIN) && AppLockManager.isValidPIN(newPIN) && AppLockManager.isValidPIN(confirmation)
        case .remove:
            return AppLockManager.isValidPIN(currentPIN)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title2.bold())
                    Text(action == .remove ? "This will stop Pocket Ledger from asking for a passcode." : "Use exactly four digits that you can remember.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(22)
            Divider()

            Form {
                if action == .change || action == .remove {
                    SecureField("Current passcode", text: $currentPIN)
                        .onChange(of: currentPIN) { _, value in currentPIN = sanitized(value) }
                }
                if action == .setup || action == .change {
                    SecureField("New four-digit passcode", text: $newPIN)
                        .onChange(of: newPIN) { _, value in newPIN = sanitized(value) }
                    SecureField("Confirm new passcode", text: $confirmation)
                        .onChange(of: confirmation) { _, value in confirmation = sanitized(value) }
                }
                if !errorMessage.isEmpty {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .padding(22)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(action == .remove ? "Remove passcode" : "Save passcode", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(action == .remove ? .red : .accentColor)
                    .disabled(!canContinue)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(18)
        }
        .frame(width: 520)
    }

    private func sanitized(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(4))
    }

    private func save() {
        do {
            switch action {
            case .setup:
                try appLock.setPasscode(newPIN, confirmation: confirmation)
            case .change:
                try appLock.changePasscode(current: currentPIN, new: newPIN, confirmation: confirmation)
            case .remove:
                try appLock.removePasscode(current: currentPIN)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: LedgerStore
    @EnvironmentObject var appLock: AppLockManager
    @State private var settings = LedgerSettings()
    @State private var notificationText = "Checking…"
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var confirmation = ""
    @State private var passcodeAction: PasscodeAction?

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
                        Circle()
                            .fill(notificationIndicatorColor)
                            .frame(width: 11, height: 11)
                            .accessibilityLabel(notificationIndicatorLabel)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 7) {
                                Text("Mac notifications").font(.headline)
                                Text(notificationIndicatorLabel)
                                    .font(.caption.bold())
                                    .foregroundStyle(notificationIndicatorColor)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(notificationIndicatorColor.opacity(0.12), in: Capsule())
                            }
                            Text(notificationText).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Enable notifications") {
                            Task {
                                let granted = await NotificationManager.shared.requestPermission()
                                if granted { NotificationManager.shared.reschedule(from: store.data) }
                                await refreshNotificationStatus()
                            }
                        }
                    }
                    .padding(8)
                }

                GroupBox("App lock") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: appLock.hasPasscode ? "lock.shield.fill" : "lock.open.fill")
                                .font(.title2)
                                .foregroundStyle(appLock.hasPasscode ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(appLock.hasPasscode ? "Four-digit passcode is enabled" : "App lock is not enabled")
                                    .font(.headline)
                                Text(appLock.hasPasscode ? "Pocket Ledger locks on launch and when you switch away." : "Add a passcode to prevent casual access to your records.")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        if appLock.hasPasscode {
                            Toggle("Unlock with \(appLock.biometryName)", isOn: $appLock.biometricsEnabled)
                                .disabled(!appLock.canUseBiometrics)
                            if !appLock.canUseBiometrics {
                                Text("Touch ID is not available or has not been configured in macOS System Settings.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            HStack {
                                Button("Change passcode") { passcodeAction = .change }
                                Button("Lock now") { appLock.lock() }
                                Button("Remove passcode", role: .destructive) { passcodeAction = .remove }
                            }
                        } else {
                            Button("Set four-digit passcode") { passcodeAction = .setup }
                                .buttonStyle(.borderedProminent)
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
            Task { await refreshNotificationStatus() }
        }
        .sheet(item: $passcodeAction) { action in
            PasscodeEditorSheet(action: action)
                .environmentObject(appLock)
        }
    }

    private var notificationIndicatorColor: Color {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return .green
        case .denied: return .red
        case .notDetermined: return .orange
        @unknown default: return .gray
        }
    }

    private var notificationIndicatorLabel: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return "On"
        case .denied: return "Off"
        case .notDetermined: return "Not set"
        @unknown default: return "Unknown"
        }
    }

    private func refreshNotificationStatus() async {
        let status = await NotificationManager.shared.status()
        notificationStatus = status
        switch status {
        case .authorized, .provisional, .ephemeral:
            notificationText = "Enabled. Payment and free-trial reminders are scheduled locally."
        case .denied:
            notificationText = "Disabled in System Settings."
        case .notDetermined:
            notificationText = "Not enabled yet."
        @unknown default:
            notificationText = "Notification status is unavailable."
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
                Toggle("This subscription has a free trial", isOn: trialEnabled)
                if item.trialEndDate != nil {
                    DatePicker("Free trial ends", selection: trialEndDate, displayedComponents: .date)
                    Stepper(
                        "Remind to cancel \(trialReminderDays.wrappedValue) day\(trialReminderDays.wrappedValue == 1 ? "" : "s") before",
                        value: trialReminderDays,
                        in: 0...30
                    )
                    Text("Pocket Ledger will send a separate cancellation reminder before the trial converts to a paid subscription.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("Pay from", selection: $item.assetID) {
                    Text("Do not update a balance").tag(UUID?.none)
                    ForEach(store.data.assets) { Text($0.name).tag(Optional($0.id)) }
                }
                Toggle("Active subscription", isOn: $item.isActive)
                TextField("Notes (optional)", text: $item.notes, axis: .vertical)
            }
        }
    }

    private var trialEnabled: Binding<Bool> {
        Binding(
            get: { item.trialEndDate != nil },
            set: { enabled in
                if enabled {
                    item.trialEndDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
                    item.trialReminderDays = 2
                } else {
                    item.trialEndDate = nil
                    item.trialReminderDays = nil
                }
            }
        )
    }

    private var trialEndDate: Binding<Date> {
        Binding(
            get: { item.trialEndDate ?? Date() },
            set: { item.trialEndDate = $0 }
        )
    }

    private var trialReminderDays: Binding<Int> {
        Binding(
            get: { item.trialReminderDays ?? 2 },
            set: { item.trialReminderDays = $0 }
        )
    }
}

private enum SubscriptionPaymentChoice: String, CaseIterable, Identifiable {
    case scheduled = "Scheduled amount"
    case different = "Different amount"
    var id: String { rawValue }
}

struct SubscriptionPaymentSheet: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) var dismiss
    let subscription: SubscriptionEntry
    let onSave: (Double) -> Void
    @State private var choice: SubscriptionPaymentChoice = .scheduled
    @State private var customAmount: Double = 0

    private var paymentAmount: Double {
        choice == .scheduled ? subscription.amount : customAmount
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Record subscription payment").font(.title2.bold())
                Text("Confirm the amount charged for \(subscription.name). The scheduled amount is \(store.currency(subscription.amount)).")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            Divider()

            VStack(alignment: .leading, spacing: 18) {
                Picker("Amount paid", selection: $choice) {
                    ForEach(SubscriptionPaymentChoice.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.radioGroup)

                if choice == .different {
                    TextField(
                        "Actual amount paid",
                        value: $customAmount,
                        format: .number.precision(.fractionLength(0...2))
                    )
                    Text("Use the final amount charged by your bank—for example, when currency conversion changes the price.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Label(
                    "This will add a subscription expense, update the linked asset balance, and move the next due date forward.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(22)
            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Record payment") {
                    onSave(paymentAmount)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(paymentAmount <= 0)
            }
            .padding(18)
        }
        .frame(width: 540)
        .onAppear { customAmount = subscription.amount }
    }
}

struct TransferEditor: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) var dismiss
    let onSave: (AssetTransfer) -> Void
    @State private var amount: Double = 0
    @State private var date = Date()
    @State private var fromAssetID: UUID?
    @State private var toAssetID: UUID?
    @State private var notes = ""

    private var canSave: Bool {
        amount > 0 && fromAssetID != nil && toAssetID != nil && fromAssetID != toAssetID
    }

    var body: some View {
        EditorContainer(
            title: "Transfer between assets",
            canSave: canSave,
            onCancel: { dismiss() },
            onSave: {
                guard let fromAssetID, let toAssetID else { return }
                onSave(AssetTransfer(
                    amount: amount,
                    date: date,
                    fromAssetID: fromAssetID,
                    toAssetID: toAssetID,
                    notes: notes
                ))
                dismiss()
            }
        ) {
            Form {
                if store.data.assets.count < 2 {
                    Label("Add at least two assets before recording a transfer.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                TextField("Amount", value: $amount, format: .number.precision(.fractionLength(0...2)))
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Picker("Move money from", selection: $fromAssetID) {
                    Text("Choose an asset").tag(UUID?.none)
                    ForEach(store.data.assets) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("Move money to", selection: $toAssetID) {
                    Text("Choose an asset").tag(UUID?.none)
                    ForEach(store.data.assets) { Text($0.name).tag(Optional($0.id)) }
                }
                if fromAssetID != nil && fromAssetID == toAssetID {
                    Text("Choose two different assets.").font(.caption).foregroundStyle(.red)
                }
                TextField("Notes (optional)", text: $notes, axis: .vertical)
                Text("Transfers change both balances but are not counted as income or expenses.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            fromAssetID = store.data.assets.first?.id
            toAssetID = store.data.assets.dropFirst().first?.id
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

import AppKit
import SwiftUI

@main
struct RenderPreview {
    @MainActor
    static func main() throws {
        let application = NSApplication.shared
        application.appearance = NSAppearance(named: .aqua)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PocketLedgerPreview-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LedgerStore(storageRoot: folder, schedulesNotifications: false)
        let bank = AssetAccount(name: "Main Bank", kind: .bank, balance: 124_500)
        let cash = AssetAccount(name: "Wallet", kind: .cash, balance: 8_200)
        store.addAsset(bank)
        store.addAsset(cash)
        store.addIncome(IncomeEntry(source: "Salary", amount: 85_000, date: Date(), category: "Salary", assetID: bank.id))
        store.addExpense(ExpenseEntry(title: "Groceries", amount: 6_400, date: Date(), category: "Groceries", assetID: bank.id))
        store.addExpense(ExpenseEntry(title: "Dinner", amount: 2_500, date: Date(), category: "Food", assetID: cash.id))
        store.addExpense(ExpenseEntry(title: "Headphones", amount: 9_000, date: Date(), category: "Online Shopping", assetID: bank.id))
        store.addSubscription(SubscriptionEntry(name: "Netflix", amount: 1_100, cycle: .monthly, nextDueDate: Calendar.current.date(byAdding: .day, value: 4, to: Date())!, assetID: bank.id))
        store.addSubscription(SubscriptionEntry(name: "HBO Max", amount: 900, cycle: .monthly, nextDueDate: Calendar.current.date(byAdding: .day, value: 9, to: Date())!, assetID: bank.id))

        let view = DashboardView()
            .environmentObject(store)
            .frame(width: 1180, height: 820)
            .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 1180, height: 820)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.appearance = NSAppearance(named: .aqua)
        window.display()
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw PreviewError.renderFailed }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw PreviewError.renderFailed }
        let output = CommandLine.arguments.dropFirst().first ?? "PocketLedger-preview.png"
        try png.write(to: URL(fileURLWithPath: output))
    }
}

enum PreviewError: Error {
    case renderFailed
}

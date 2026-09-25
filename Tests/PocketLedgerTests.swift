import XCTest
@testable import PocketLedger

final class PocketLedgerTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    @MainActor
    private func makeStore() -> LedgerStore {
        LedgerStore(storageRoot: folder, schedulesNotifications: false)
    }

    @MainActor
    func testIncomeAndExpenseUpdateBalance() {
        let store = makeStore()
        let cash = AssetAccount(name: "Wallet", kind: .cash, balance: 100)
        store.addAsset(cash)

        store.addIncome(IncomeEntry(source: "Salary", amount: 500, date: Date(), category: "Salary", assetID: cash.id))
        XCTAssertEqual(store.data.assets.first?.balance, 600)

        store.addExpense(ExpenseEntry(title: "Food", amount: 75, date: Date(), category: "Food", assetID: cash.id))
        XCTAssertEqual(store.data.assets.first?.balance, 525)
        XCTAssertEqual(store.thisMonthIncome, 500)
        XCTAssertEqual(store.thisMonthExpenses, 75)
    }

    @MainActor
    func testEditingAndDeletingTransactionsReversesOldAmounts() {
        let store = makeStore()
        let bank = AssetAccount(name: "Bank", kind: .bank, balance: 1_000)
        store.addAsset(bank)
        var expense = ExpenseEntry(title: "Shopping", amount: 100, date: Date(), category: "Online Shopping", assetID: bank.id)
        store.addExpense(expense)
        XCTAssertEqual(store.data.assets.first?.balance, 900)

        expense.amount = 40
        store.updateExpense(expense)
        XCTAssertEqual(store.data.assets.first?.balance, 960)

        store.deleteExpense(expense)
        XCTAssertEqual(store.data.assets.first?.balance, 1_000)
    }

    @MainActor
    func testSubscriptionPaymentCreatesExpenseAndMovesDueDate() {
        let store = makeStore()
        let bank = AssetAccount(name: "Bank", kind: .bank, balance: 1_000)
        store.addAsset(bank)
        let pastDue = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        let subscription = SubscriptionEntry(name: "Netflix", amount: 50, cycle: .monthly, nextDueDate: pastDue, assetID: bank.id)
        store.addSubscription(subscription)

        store.recordSubscriptionPayment(subscription)

        XCTAssertEqual(store.data.expenses.count, 1)
        XCTAssertEqual(store.data.expenses.first?.subscriptionID, subscription.id)
        XCTAssertEqual(store.totalSpent(on: subscription), 50)
        XCTAssertEqual(store.data.assets.first?.balance, 950)
        XCTAssertGreaterThan(store.data.subscriptions.first!.nextDueDate, Date())
    }

    @MainActor
    func testSubscriptionPaymentAcceptsDifferentChargedAmount() {
        let store = makeStore()
        let bank = AssetAccount(name: "Bank", kind: .bank, balance: 1_000)
        store.addAsset(bank)
        let subscription = SubscriptionEntry(
            name: "Streaming",
            amount: 10,
            cycle: .monthly,
            nextDueDate: Date(),
            assetID: bank.id
        )
        store.addSubscription(subscription)

        store.recordSubscriptionPayment(subscription, amount: 12.75)

        XCTAssertEqual(store.data.expenses.first?.amount, 12.75)
        XCTAssertEqual(store.totalSpent(on: subscription), 12.75)
        XCTAssertEqual(store.data.assets.first?.balance, 987.25)
    }

    @MainActor
    func testTransferMovesBalanceWithoutCreatingIncomeOrExpense() {
        let store = makeStore()
        let wallet = AssetAccount(name: "Wallet", kind: .cash, balance: 300)
        let bank = AssetAccount(name: "Bank", kind: .bank, balance: 500)
        store.addAsset(wallet)
        store.addAsset(bank)

        let transfer = AssetTransfer(
            amount: 125,
            date: Date(),
            fromAssetID: wallet.id,
            toAssetID: bank.id,
            notes: "Deposit"
        )
        XCTAssertTrue(store.addTransfer(transfer))
        XCTAssertEqual(store.data.assets.first(where: { $0.id == wallet.id })?.balance, 175)
        XCTAssertEqual(store.data.assets.first(where: { $0.id == bank.id })?.balance, 625)
        XCTAssertTrue(store.data.expenses.isEmpty)
        XCTAssertTrue(store.data.income.isEmpty)
        XCTAssertEqual(store.totalAssets, 800)

        store.deleteTransfer(transfer)
        XCTAssertEqual(store.data.assets.first(where: { $0.id == wallet.id })?.balance, 300)
        XCTAssertEqual(store.data.assets.first(where: { $0.id == bank.id })?.balance, 500)
    }

    func testOlderLedgerDataLoadsWithoutTransferField() throws {
        let json = """
        {
          "assets": [],
          "expenses": [],
          "income": [],
          "subscriptions": [],
          "settings": {"currencyCode": "USD", "reminderHour": 9}
        }
        """
        let decoded = try JSONDecoder().decode(LedgerData.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.transfers.isEmpty)
    }

    @MainActor
    func testDataPersistsAcrossRelaunch() {
        var store = makeStore()
        store.addAsset(AssetAccount(name: "Savings", kind: .savings, balance: 2_500))
        store = LedgerStore(storageRoot: folder, schedulesNotifications: false)
        XCTAssertEqual(store.data.assets.count, 1)
        XCTAssertEqual(store.data.assets.first?.name, "Savings")
        XCTAssertEqual(store.totalAssets, 2_500)
    }

    @MainActor
    func testSubscriptionMonthlyEquivalents() {
        let date = Date()
        XCTAssertEqual(SubscriptionEntry(name: "M", amount: 100, cycle: .monthly, nextDueDate: date).monthlyEquivalent(), 100)
        XCTAssertEqual(SubscriptionEntry(name: "Y", amount: 1_200, cycle: .yearly, nextDueDate: date).monthlyEquivalent(), 100)
        XCTAssertEqual(SubscriptionEntry(name: "W", amount: 12, cycle: .weekly, nextDueDate: date).monthlyEquivalent(), 52, accuracy: 0.001)
    }

    @MainActor
    func testBackupIsCreated() {
        let store = makeStore()
        store.addAsset(AssetAccount(name: "Cash", kind: .cash, balance: 10))
        let backup = store.createBackup()
        XCTAssertNotNil(backup)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup!.path))
    }

    func testPINValidationAndHashing() throws {
        XCTAssertTrue(AppLockManager.isValidPIN("0427"))
        XCTAssertFalse(AppLockManager.isValidPIN("427"))
        XCTAssertFalse(AppLockManager.isValidPIN("12a4"))
        XCTAssertFalse(AppLockManager.isValidPIN("12345"))

        let credential = try PINCredential.create(for: "0427")
        XCTAssertTrue(credential.matches("0427"))
        XCTAssertFalse(credential.matches("0428"))
        XCTAssertNotEqual(credential.digest, Data("0427".utf8))
    }
}

import SwiftUI

@main
struct PocketLedgerApp: App {
    @StateObject private var store = LedgerStore()

    var body: some Scene {
        WindowGroup("Pocket Ledger") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear {
                    NotificationManager.shared.reschedule(from: store.data)
                }
                .alert("Pocket Ledger", isPresented: Binding(
                    get: { store.lastError != nil },
                    set: { if !$0 { store.lastError = nil } }
                )) {
                    Button("OK") { store.lastError = nil }
                } message: {
                    Text(store.lastError ?? "")
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

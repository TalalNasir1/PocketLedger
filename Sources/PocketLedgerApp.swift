import AppKit
import SwiftUI

@main
struct PocketLedgerApp: App {
    @StateObject private var store = LedgerStore()
    @StateObject private var appLock = AppLockManager()

    var body: some Scene {
        WindowGroup("Pocket Ledger") {
            Group {
                if appLock.isLocked {
                    AppUnlockView()
                } else {
                    ContentView()
                }
            }
                .environmentObject(store)
                .environmentObject(appLock)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear {
                    NotificationManager.shared.reschedule(from: store.data)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    appLock.lock()
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
            CommandMenu("Security") {
                Button("Lock Pocket Ledger") { appLock.lock() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                    .disabled(!appLock.hasPasscode || appLock.isLocked)
            }
        }
    }
}

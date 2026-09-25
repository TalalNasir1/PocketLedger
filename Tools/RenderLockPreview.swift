import AppKit
import SwiftUI

@main
struct RenderLockPreview {
    @MainActor
    static func main() throws {
        let application = NSApplication.shared
        application.appearance = NSAppearance(named: .aqua)
        let lock = AppLockManager()
        let view = AppUnlockView()
            .environmentObject(lock)
            .frame(width: 980, height: 640)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 980, height: 640)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.appearance = NSAppearance(named: .aqua)
        window.display()
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw LockPreviewError.renderFailed }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw LockPreviewError.renderFailed }
        let output = CommandLine.arguments.dropFirst().first ?? "PocketLedger-lock-preview.png"
        try png.write(to: URL(fileURLWithPath: output))
    }
}

enum LockPreviewError: Error {
    case renderFailed
}

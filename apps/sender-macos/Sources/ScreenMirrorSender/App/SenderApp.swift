import AppKit
import SwiftUI

@MainActor
struct SenderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            SenderView()
        } label: {
            Image(systemName: "airplayvideo")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // App de barra de menús: sin icono en el Dock (AGENTS.md §6).
        NSApp.setActivationPolicy(.accessory)
    }
}

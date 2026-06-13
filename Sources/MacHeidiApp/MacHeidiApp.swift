import SwiftUI
import AppKit
import MacHeidiCore
import MacHeidiMySQL

@main
struct MacHeidiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var env = AppEnvironment.make()

    var body: some Scene {
        WindowGroup("MacHeidi") {
            RootView()
                .environment(env)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Query Tab") {
                    env.openNewQueryTab()
                }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(env.activeSession == nil)
            }
        }
    }
}

/// 当 App 以"裸 swift package executable"形式跑时（即 `swift run` 或我们脚本里
/// `open MacHeidi.app`），macOS 不会自动把它当成 regular foreground app。
/// 这里强制 regular policy 并 activate，保证窗口出现在最前。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}


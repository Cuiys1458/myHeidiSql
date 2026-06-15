import SwiftUI
import AppKit
import MacHeidiCore
import MacHeidiMySQL

@main
struct MacHeidiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var env = AppEnvironment.make()

    /// 语言偏好（响应式）：
    /// - "" → 跟随系统
    /// - "zh-Hans" → 中文
    /// - "en" → 英文
    /// 改 key 后整个 WindowGroup 自动 rebuild，UI 立即切换不用重启。
    @AppStorage("MacHeidiLanguage") private var preferredLanguage: String = ""

    private var preferredLocale: Locale? {
        guard !preferredLanguage.isEmpty else { return nil }
        return Locale(identifier: preferredLanguage)
    }

    var body: some Scene {
        WindowGroup("MacHeidi") {
            Group {
                if let locale = preferredLocale {
                    RootView().environment(\.locale, locale)
                } else {
                    RootView()
                }
            }
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
            // 主菜单：View → Language
            CommandMenu("Language") {
                Button {
                    preferredLanguage = ""
                } label: {
                    if preferredLanguage.isEmpty {
                        Label("System Default", systemImage: "checkmark")
                    } else {
                        Text("System Default")
                    }
                }
                Divider()
                Button {
                    preferredLanguage = "en"
                } label: {
                    if preferredLanguage == "en" {
                        Label("English", systemImage: "checkmark")
                    } else {
                        Text("English")
                    }
                }
                Button {
                    preferredLanguage = "zh-Hans"
                } label: {
                    if preferredLanguage == "zh-Hans" {
                        Label("简体中文", systemImage: "checkmark")
                    } else {
                        Text("简体中文")
                    }
                }
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


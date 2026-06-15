import SwiftUI

// MARK: - Module-bound localization shorthands
//
// SPM 的 SwiftUI Text("key") 默认从 Bundle.main 查表，但 MacHeidi 的 strings 在
// Bundle.module（SPM resource bundle）里，所以默认查不到。这里提供两个写法：
//
//   Text(loc: "data.commit")         // 显式 bundle: .module
//   Text(L("data.commit"))           // 同上，更短
//   Button(L("common.cancel")) { ... }
//
// 已有的 `Text("foo")` 字面量会继续显示 "foo"（不影响行为，逐步迁移）。
//
// 改完 UI 后要切换显示语言：
//   - SwiftUI 默认跟随系统语言
//   - 强制中文：在 RootView 加 .environment(\.locale, .init(identifier: "zh-Hans"))

// 让 Text(L("...")) 直接拿 bundle: .module
extension Text {
    /// 主要 i18n 入口：Text(L("key"))
    init(_ key: ModuleLocalizedKey) {
        self.init(key.value, bundle: .module)
    }
}

extension Button where Label == Text {
    /// Button(L("key")) { ... }
    init(_ key: ModuleLocalizedKey, action: @escaping () -> Void) {
        self.init(action: action) {
            Text(key.value, bundle: .module)
        }
    }

    /// Button(L("key"), role: .destructive) { ... }
    init(_ key: ModuleLocalizedKey,
         role: ButtonRole?,
         action: @escaping () -> Void) {
        self.init(role: role, action: action) {
            Text(key.value, bundle: .module)
        }
    }
}

extension Label where Title == Text, Icon == Image {
    /// Label(L("key"), systemImage: "...")
    init(_ key: ModuleLocalizedKey, systemImage name: String) {
        self.init(title: { Text(key.value, bundle: .module) },
                  icon: { Image(systemName: name) })
    }
}

/// 通过 strong typing 区分 module-bound key 和普通 LocalizedStringKey，
/// 避免重载冲突。
public struct ModuleLocalizedKey {
    public let value: LocalizedStringKey
    public init(_ key: String) { self.value = LocalizedStringKey(key) }
}

// MARK: - Public API

/// SwiftUI 用：Text(L("key")) / Button(L("key")) / Label(L("key"), systemImage: ...)
@inline(__always)
public func L(_ key: String) -> ModuleLocalizedKey {
    ModuleLocalizedKey(key)
}

/// String 用（NSMenuItem / NSAlert / pasteboard / NSWindow.title 等）。
@inline(__always)
public func LS(_ key: String, fallback: String? = nil) -> String {
    NSLocalizedString(key, bundle: .module, value: fallback ?? key, comment: "")
}

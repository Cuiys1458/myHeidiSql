import Foundation
import SwiftUI

/// SwiftUI / AppKit 文本国际化 helper。
///
/// 问题背景：SwiftUI 的 `Text("key")` 默认从 `Bundle.main` 查 Localizable.strings，
/// 但 SPM 把 Resources 打到 `Bundle.module`（每模块独立），所以每次都要写
/// `Text("key", bundle: .module)` 才能取到。这个 helper 把 bundle 显式传好。
///
/// 用法：
///   Text(L("data.commit"))
///   Button(L("common.cancel")) { ... }
///
/// 漏的 key 会落到 ENG 默认值 = key 本身（fallback 行为）。
@inline(__always)
public func L(_ key: String) -> LocalizedStringKey {
    LocalizedStringKey(key)
}

/// String 形式（用于 NSMenuItem / NSAlert / pasteboard 等 AppKit 接口）。
@inline(__always)
public func LS(_ key: String, fallback: String? = nil) -> String {
    let s = NSLocalizedString(key, bundle: .module, value: fallback ?? key, comment: "")
    return s
}

/// 给 SwiftUI Text/Button 用的 explicit bundle helper（当默认 Bundle.main lookup 失败时）。
extension Text {
    init(loc key: String) {
        self.init(LocalizedStringKey(key), bundle: .module)
    }
}

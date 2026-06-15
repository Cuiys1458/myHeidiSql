import SwiftUI
import MacHeidiCore

/// 会话颜色标签（防误连生产）：把 `SessionColorTag` 映射成 SwiftUI Color。
/// 同时给 SessionManager 提供本地化标签名。
enum SessionColorPalette {

    /// `SwiftUI.Color`，nil = 不画标签（none）
    static func swiftColor(for tag: SessionColorTag) -> Color? {
        switch tag {
        case .none:   return nil
        case .blue:   return .blue
        case .green:  return .green
        case .orange: return .orange
        case .red:    return .red
        case .purple: return .purple
        case .gray:   return .gray
        }
    }

    /// 本地化的标签名（"无 / 蓝 / 绿 / ..."）
    static func label(for tag: SessionColorTag) -> String {
        switch tag {
        case .none:   return LS("color.none", fallback: "None")
        case .blue:   return LS("color.blue", fallback: "Blue")
        case .green:  return LS("color.green", fallback: "Green")
        case .orange: return LS("color.orange", fallback: "Orange")
        case .red:    return LS("color.red", fallback: "Red")
        case .purple: return LS("color.purple", fallback: "Purple")
        case .gray:   return LS("color.gray", fallback: "Gray")
        }
    }
}

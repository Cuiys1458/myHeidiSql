import Foundation

/// 自动补全弹窗的"是否触发"状态机（纯函数，便于 TDD）。
///
/// 输入：当前文本 + 光标位置 + 上一次 trigger 时的快照。
/// 输出：动作（show/hide/keep）+ 应该传给 CompletionEngine 的 prefix。
public enum CompletionTrigger {

    public enum Action: Equatable, Sendable {
        case show(prefix: String)
        case hide
        case keep   // 没有变化，不动
    }

    /// 当前光标位置算"identifier-like" → 当前 token 由字母/数字/下划线/点组成。
    public static func evaluate(text: String, cursor: Int) -> Action {
        // 取光标处当前 token
        let tok = CompletionEngine.currentToken(text: text, cursor: cursor)
        // 空白处或只输入了非 identifier 字符 → hide
        if tok.token.isEmpty {
            return .hide
        }
        // 当前 token 末尾必须是 identifier 字符（避免在 ", " "(" 等之后乱弹）
        let chars = Array(text)
        let safe = max(0, min(cursor, chars.count))
        guard safe > 0 else { return .hide }
        let last = chars[safe - 1]
        if !(last.isLetter || last.isNumber || last == "_" || last == ".") {
            return .hide
        }
        return .show(prefix: tok.token)
    }

    /// 应用补全：在 token 范围替换为选中文本。
    /// 返回 (newText, newCursor)。
    public static func applyCompletion(
        text: String, cursor: Int, suggestion: String
    ) -> (text: String, cursor: Int) {
        let tok = CompletionEngine.currentToken(text: text, cursor: cursor)
        // 处理 db.table 这种带点的 prefix：只替换最后一段
        let prefix = tok.token
        let lastDotInPrefix = prefix.range(of: ".", options: .backwards)
        let replaceFrom: Int
        if let dot = lastDotInPrefix {
            // 例 "users." → 从 dot 之后开始替换；"users.na" → 从 "na" 开始
            let dotOffsetInPrefix = prefix.distance(from: prefix.startIndex, to: dot.upperBound)
            replaceFrom = tok.range.lowerBound + dotOffsetInPrefix
        } else {
            replaceFrom = tok.range.lowerBound
        }
        let chars = Array(text)
        let prefixPart = String(chars[..<replaceFrom])
        let suffixPart = String(chars[tok.range.upperBound...])
        let newText = prefixPart + suggestion + suffixPart
        let newCursor = replaceFrom + suggestion.count
        return (newText, newCursor)
    }
}

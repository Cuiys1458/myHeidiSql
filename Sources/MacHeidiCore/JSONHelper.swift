import Foundation

/// JSON 处理辅助工具 —— UI 无关的纯函数。
///
/// 用于：
/// - 判断 BLOB 列内容是否其实是 JSON 字符串（启发式识别）
/// - 编辑器里实时校验 + 错误定位
/// - Format / Minify / Pretty-print
///
/// 与 `JSONSerialization` 的差别：
/// 1. `isJSON` 只接受顶层 object/array（拒绝裸 number、bool、null —— 这些 MySQL JSON 列允许，但
///    用作"BLOB-as-JSON 启发式"时太宽容会误判）。
/// 2. `validate` 返回字符级 offset，方便编辑器红色波浪线定位。
/// 3. `prettyPrint` 用 `.sortedKeys` 让 diff 稳定。
public enum JSONHelper {

    // MARK: - 判定

    /// 字符串能否解析为合法 JSON，且**顶层是 object 或 array**。
    public static func isJSON(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "{" || first == "[" else { return false }
        guard let data = trimmed.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [])) != nil
    }

    /// 同上，输入是 Data。
    public static func isJSON(_ d: Data) -> Bool {
        guard let s = String(data: d, encoding: .utf8) else { return false }
        return isJSON(s)
    }

    /// 启发式：BLOB 数据看起来是 JSON 吗？
    ///
    /// 三重判定：
    /// 1. 整段 Data 必须能 UTF-8 解码
    /// 2. trim 后第一个字符是 `{` 或 `[`
    /// 3. `JSONSerialization` 能完整解析
    ///
    /// - Returns: 解码后的 JSON 字符串；非 JSON / 二进制 BLOB 返回 nil。
    public static func looksLikeJSONBLOB(_ d: Data) -> String? {
        guard !d.isEmpty,
              let s = String(data: d, encoding: .utf8) else { return nil }
        guard isJSON(s) else { return nil }
        return s
    }

    // MARK: - Pretty-print / Minify

    /// 美化：2 空格缩进，键按字典序排（diff 稳定）。失败返回 nil。
    public static func prettyPrint(_ s: String) -> String? {
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(
                  with: data, options: [.fragmentsAllowed]
              ),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: obj,
                  options: [.prettyPrinted, .sortedKeys]
              ),
              let result = String(data: pretty, encoding: .utf8) else { return nil }
        return result
    }

    /// 压缩：去除所有空白字符。失败返回 nil。
    public static func minify(_ s: String) -> String? {
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(
                  with: data, options: [.fragmentsAllowed]
              ),
              let mini = try? JSONSerialization.data(
                  withJSONObject: obj, options: [.sortedKeys]
              ),
              let result = String(data: mini, encoding: .utf8) else { return nil }
        return result
    }

    // MARK: - 校验

    public enum ValidateResult: Equatable {
        case valid
        case invalid(message: String, byteOffset: Int?)
    }

    /// 校验 + 提取错误位置（如果 NSError 里有 `NSJSONSerializationErrorIndex`）。
    public static func validate(_ s: String) -> ValidateResult {
        guard let data = s.data(using: .utf8) else {
            return .invalid(message: "Input is not valid UTF-8", byteOffset: nil)
        }
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            return .valid
        } catch let err as NSError {
            // Foundation 的 JSONSerialization 在 macOS 14+ 会在 userInfo 里提供
            // NSDebugDescription 含 "around character N" 形式。提取出 N 作为 byte offset。
            let msg = err.localizedDescription
            let offset = extractCharIndex(from: err.userInfo) ?? extractCharIndex(fromMessage: msg)
            return .invalid(message: msg, byteOffset: offset)
        }
    }

    private static func extractCharIndex(from userInfo: [String: Any]) -> Int? {
        // 系统 SDK 里这个 key 在不同版本下名字不一样，多探一下
        for key in ["NSJSONSerializationErrorIndex", "ErrorIndex"] {
            if let n = userInfo[key] as? Int { return n }
            if let n = userInfo[key] as? NSNumber { return n.intValue }
        }
        return nil
    }

    private static func extractCharIndex(fromMessage msg: String) -> Int? {
        // 兜底：从错误描述字符串里抠 "around character N"
        let pattern = #"around (?:character|line)\s+(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(
                  in: msg, options: [],
                  range: NSRange(msg.startIndex..., in: msg)
              ),
              match.numberOfRanges >= 2,
              let r = Range(match.range(at: 1), in: msg) else { return nil }
        return Int(msg[r])
    }

    // MARK: - 统计（编辑器底部状态栏用）

    public struct Stats: Equatable {
        public let topLevelKeys: Int      // -1 表示顶层不是 object
        public let topLevelItems: Int     // -1 表示顶层不是 array
        public let byteCount: Int

        public init(topLevelKeys: Int, topLevelItems: Int, byteCount: Int) {
            self.topLevelKeys = topLevelKeys
            self.topLevelItems = topLevelItems
            self.byteCount = byteCount
        }
    }

    public static func stats(_ s: String) -> Stats {
        let bytes = s.utf8.count
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(
                  with: data, options: [.fragmentsAllowed]
              ) else {
            return Stats(topLevelKeys: -1, topLevelItems: -1, byteCount: bytes)
        }
        if let dict = obj as? [String: Any] {
            return Stats(topLevelKeys: dict.count, topLevelItems: -1, byteCount: bytes)
        }
        if let arr = obj as? [Any] {
            return Stats(topLevelKeys: -1, topLevelItems: arr.count, byteCount: bytes)
        }
        return Stats(topLevelKeys: -1, topLevelItems: -1, byteCount: bytes)
    }
}

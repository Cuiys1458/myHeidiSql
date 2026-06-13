import Foundation

/// 把 `SHOW DATABASES` 返回的完整库名列表按 ``SessionConfig/defaultDatabases``
/// 规则过滤。规则对齐 HeidiSQL：
///
/// - `defaultDatabases` 为空 → 返回所有非系统库（剔除 information_schema 等）
/// - `defaultDatabases` 非空 → 按逗号分割成白名单，**只**返回白名单里的库
///   （白名单允许包含系统库，由用户自己决定）
///
/// 比较大小写不敏感（MySQL 库名在多数平台不区分大小写）。
public enum DatabaseFilter {

    public static func apply(
        _ all: [String],
        defaultDatabases setting: String
    ) -> [String] {
        let trimmed = setting.trimmingCharacters(in: .whitespacesAndNewlines)

        // 空 → 剔除系统库
        if trimmed.isEmpty {
            return all.filter { !SystemSchemas.names.contains($0.lowercased()) }
        }

        // 非空 → 白名单
        let whiteList = trimmed.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // 只有分隔符没有名字 → 等同空
        guard !whiteList.isEmpty else {
            return all.filter { !SystemSchemas.names.contains($0.lowercased()) }
        }

        let wlSet = Set(whiteList.map { $0.lowercased() })
        return all.filter { wlSet.contains($0.lowercased()) }
    }
}

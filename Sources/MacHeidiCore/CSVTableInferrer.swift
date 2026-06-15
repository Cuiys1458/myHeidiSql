import Foundation

/// 从 CSV 内容推导 CREATE TABLE 语句。
///
/// 规则（保守为准，宁可宽不要窄）：
/// - 全空 → VARCHAR(255)
/// - 全为整型 → BIGINT（不区分 int / smallint，让用户后续 ALTER）
/// - 含小数点的全数字 → DECIMAL(20,6)
/// - 全为 ISO 日期 (yyyy-mm-dd) → DATE
/// - 全为 ISO 日期时间 (yyyy-mm-dd hh:mm:ss) → DATETIME
/// - 含逗号 / 引号 / 换行 / 平均长度 > 200 → TEXT
/// - 其他 → VARCHAR(N)，N = max(255, 最长样本 × 1.5 向上取整)
/// - 任一行该列为空 → 该列 NULLABLE
///
/// 列名清洗：去除前后空白；非法字符（空格、横杠等）替换为下划线；
/// 与 MySQL 关键字冲突时反引号兜底（由 SQLIdentifier.quote 处理）。
///
/// 主键策略：
/// - CSV 已含 `id` 列（不区分大小写）→ 把它设为 PRIMARY KEY（NOT NULL；
///   值看着是整型 → BIGINT；否则按推导出的类型）；不再注入隐式 id 列
/// - CSV 不含 id → 注入 `id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY`
public enum CSVTableInferrer {

    public struct Spec: Equatable {
        public let columns: [ColumnSpec]
        public let createSQL: String
        /// CSV 自己提供 id 列 → 该列名（清洗后）；否则 nil 表示注入了隐式 id。
        public let primaryKeyColumn: String?
        /// PRIMARY KEY 是不是 AUTO_INCREMENT BIGINT（注入 id 时为 true）
        public let pkIsAutoIncrement: Bool
    }

    public struct ColumnSpec: Equatable {
        public let originalName: String   // CSV 里的原始列名
        public let cleanName: String      // 清洗后用作 SQL 列名
        public let mysqlType: String      // BIGINT / DECIMAL(20,6) / VARCHAR(255) / TEXT...
        public let nullable: Bool
    }

    /// `headers` 是首行列名（如果 CSV 没有 header，传 ["Column 1", "Column 2", ...]）。
    /// `rows` 应该是采样后的若干行（推荐 100-500 行；越多越准但越慢）。
    public static func infer(
        database: String, table: String,
        headers: [String], rows: [[String]]
    ) throws -> Spec {
        let cols: [ColumnSpec] = headers.enumerated().map { idx, header in
            let samples = rows.compactMap { idx < $0.count ? $0[idx] : nil }
            let nullable = samples.contains(where: { $0.isEmpty })
            let nonEmpty = samples.filter { !$0.isEmpty }
            let mysqlType = inferType(samples: nonEmpty)
            let clean = cleanColumnName(header, fallbackIndex: idx)
            return ColumnSpec(
                originalName: header,
                cleanName: clean,
                mysqlType: mysqlType,
                nullable: nullable
            )
        }

        // 探测：CSV 是不是已经带了 id 列？大小写不敏感
        let existingIdIndex = cols.firstIndex { $0.cleanName.lowercased() == "id" }

        let qualified = try SQLIdentifier.qualified(database: database, table: table)
        var lines: [String] = []
        let pkColumn: String?
        let pkAuto: Bool

        if let idx = existingIdIndex {
            // 已有 id：把它作为 PRIMARY KEY，强制 NOT NULL（PK 必须非空）
            let idCol = cols[idx]
            let qc = try SQLIdentifier.quote(idCol.cleanName)
            lines.append("\(qc) \(idCol.mysqlType) NOT NULL PRIMARY KEY")
            for (i, c) in cols.enumerated() where i != idx {
                let qc = try SQLIdentifier.quote(c.cleanName)
                let nullClause = c.nullable ? "NULL" : "NOT NULL"
                lines.append("\(qc) \(c.mysqlType) \(nullClause)")
            }
            pkColumn = idCol.cleanName
            pkAuto = false
        } else {
            // 没有 id：注入隐式 BIGINT AUTO_INCREMENT 作为 PRIMARY KEY
            lines.append("`id` BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY")
            for c in cols {
                let qc = try SQLIdentifier.quote(c.cleanName)
                let nullClause = c.nullable ? "NULL" : "NOT NULL"
                lines.append("\(qc) \(c.mysqlType) \(nullClause)")
            }
            pkColumn = nil
            pkAuto = true
        }

        let body = lines.joined(separator: ",\n  ")
        let sql = """
        CREATE TABLE \(qualified) (
          \(body)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
        return Spec(columns: cols, createSQL: sql,
                    primaryKeyColumn: pkColumn, pkIsAutoIncrement: pkAuto)
    }

    // MARK: 类型推断

    private static func inferType(samples: [String]) -> String {
        guard !samples.isEmpty else { return "VARCHAR(255)" }

        // 长字段直接 TEXT
        let avgLen = samples.reduce(0) { $0 + $1.count } / samples.count
        let maxLen = samples.map(\.count).max() ?? 0
        if avgLen > 200 || maxLen > 1000 {
            return "TEXT"
        }

        // 整型
        if samples.allSatisfy({ Int64($0) != nil }) {
            return "BIGINT"
        }

        // 浮点 / DECIMAL
        if samples.allSatisfy({ Double($0) != nil && $0.contains(".") }) {
            return "DECIMAL(20,6)"
        }

        // 日期
        if samples.allSatisfy({ matchesISODate($0) }) {
            return "DATE"
        }

        // 日期时间
        if samples.allSatisfy({ matchesISODateTime($0) }) {
            return "DATETIME"
        }

        // 含中文 / 长字段 → TEXT
        if samples.contains(where: { $0.contains("\n") }) {
            return "TEXT"
        }

        // 其他 VARCHAR
        let n = max(64, min(2048, Int(Double(maxLen) * 1.5).round8()))
        return "VARCHAR(\(n))"
    }

    private static func matchesISODate(_ s: String) -> Bool {
        // yyyy-mm-dd
        guard s.count == 10 else { return false }
        let parts = s.split(separator: "-")
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ Int($0) != nil }) else { return false }
        return true
    }

    private static func matchesISODateTime(_ s: String) -> Bool {
        // yyyy-mm-dd hh:mm:ss / yyyy-mm-ddThh:mm:ss / 含毫秒
        let normalized = s.replacingOccurrences(of: "T", with: " ")
        let comps = normalized.split(separator: " ", maxSplits: 1)
        guard comps.count == 2,
              matchesISODate(String(comps[0])) else { return false }
        let timePart = String(comps[1]).split(separator: ".").first ?? ""
        let timeComps = timePart.split(separator: ":")
        return timeComps.count == 3 && timeComps.allSatisfy { Int($0) != nil }
    }

    private static func cleanColumnName(_ raw: String, fallbackIndex: Int) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "col_\(fallbackIndex + 1)" }
        // 保留中文 / 字母 / 数字 / 下划线，其他替换 _
        let chars = trimmed.map { c -> Character in
            if c.isLetter || c.isNumber || c == "_" { return c }
            return "_"
        }
        // 不能以数字开头
        var result = String(chars)
        if let first = result.first, first.isNumber {
            result = "col_" + result
        }
        return result
    }
}

private extension Int {
    /// 向上对齐到 8 的倍数（让 VARCHAR(N) 看起来更顺眼，比如 250 → 256）。
    func round8() -> Int {
        return ((self + 7) / 8) * 8
    }
}

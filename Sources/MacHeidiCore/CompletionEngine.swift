import Foundation

/// SQL 自动补全引擎（纯函数）。
///
/// 输入：当前 SQL 全文 + 光标偏移 + 可用的 schema 元信息。
/// 输出：候选列表（按相关性排序）。
///
/// 策略简单：根据光标前最近一个非引号 / 非注释的"关键字上下文"分类决定建议什么。
/// 不做完整 SQL 解析（成本高且 SQL 方言差异大）；够日常用即可。
public enum CompletionEngine {

    public struct Suggestion: Equatable, Hashable, Sendable {
        public let text: String
        public let kind: Kind
        public let detail: String?
        public init(text: String, kind: Kind, detail: String? = nil) {
            self.text = text; self.kind = kind; self.detail = detail
        }

        public enum Kind: String, Sendable {
            case keyword, table, column, database, function
        }
    }

    public struct SchemaSnapshot: Sendable {
        /// 当前默认数据库的列名集合（含限定 db.table 来源）
        public let columnsByTable: [String: [String]]   // tableName → columns
        /// 当前 session 的 db 列表
        public let databases: [String]
        /// 当前激活 db 的表名 / 视图名
        public let tables: [String]

        public init(databases: [String], tables: [String],
                    columnsByTable: [String: [String]]) {
            self.databases = databases
            self.tables = tables
            self.columnsByTable = columnsByTable
        }
    }

    public enum Context: Equatable, Sendable {
        case afterFrom        // 期望表
        case afterDot(String) // 期望 <prefix>. 后的列
        case afterSelect      // 期望列 + 函数 + *
        case afterWhere       // 期望列
        case afterUpdate      // 期望表
        case afterInto        // 期望表
        case afterSet         // 期望列
        case afterJoin        // 期望表
        case afterOrderBy     // 期望列
        case afterGroupBy     // 期望列
        case generic          // 关键字 + 表 + 列
    }

    public static let keywords: [String] = [
        "SELECT","FROM","WHERE","AND","OR","NOT","IN","IS","NULL","LIKE","BETWEEN",
        "GROUP","BY","ORDER","HAVING","LIMIT","OFFSET","JOIN","LEFT","RIGHT","INNER",
        "OUTER","ON","AS","DISTINCT","UNION","ALL","CASE","WHEN","THEN","ELSE","END",
        "INSERT","INTO","VALUES","UPDATE","SET","DELETE","CREATE","TABLE","DROP",
        "ALTER","ADD","COLUMN","INDEX","KEY","PRIMARY","FOREIGN","REFERENCES",
        "DESCRIBE","DESC","ASC","EXPLAIN","SHOW","DATABASES","TABLES","TRUNCATE",
        "WITH","BEGIN","COMMIT","ROLLBACK","TRANSACTION","CALL","IF","EXISTS","USE",
        "GRANT","REVOKE","CONSTRAINT","DEFAULT","UNIQUE","CHECK"
    ]

    public static let functions: [String] = [
        // 聚合
        "COUNT","SUM","AVG","MIN","MAX","GROUP_CONCAT",
        // 时间
        "NOW","CURDATE","CURTIME","CURRENT_DATE","CURRENT_TIME","CURRENT_TIMESTAMP",
        "DATE","TIME","TIMESTAMP","UNIX_TIMESTAMP","FROM_UNIXTIME",
        "DATE_ADD","DATE_SUB","DATEDIFF","DATE_FORMAT","STR_TO_DATE",
        "YEAR","MONTH","DAY","HOUR","MINUTE","SECOND","WEEK","WEEKDAY","DAYOFWEEK",
        // 字符串
        "CONCAT","CONCAT_WS","SUBSTRING","SUBSTR","LEFT","RIGHT","LENGTH","CHAR_LENGTH",
        "TRIM","LTRIM","RTRIM","LOWER","UPPER","LCASE","UCASE",
        "REPLACE","REVERSE","REPEAT","LPAD","RPAD","INSTR","LOCATE","FIND_IN_SET",
        "FORMAT","HEX","UNHEX","MD5","SHA1","SHA2","UUID",
        // 数值
        "ROUND","FLOOR","CEIL","CEILING","ABS","MOD","POW","POWER","SQRT","RAND","SIGN",
        "GREATEST","LEAST",
        // 条件 / 系统
        "COALESCE","IFNULL","NULLIF","IF","CASE","CAST","CONVERT",
        "VERSION","DATABASE","SCHEMA","USER","CURRENT_USER","CONNECTION_ID",
        "LAST_INSERT_ID","ROW_COUNT","FOUND_ROWS",
        // JSON
        "JSON_OBJECT","JSON_ARRAY","JSON_EXTRACT","JSON_UNQUOTE","JSON_VALID",
        "JSON_LENGTH","JSON_KEYS","JSON_CONTAINS",
    ]

    /// 主入口。
    public static func suggest(
        text: String, cursor: Int, schema: SchemaSnapshot
    ) -> [Suggestion] {
        let prefix = currentToken(text: text, cursor: cursor)
        let ctx = detectContext(text: text, cursor: cursor)
        let candidates = candidatesFor(context: ctx, schema: schema, prefix: prefix.token)
        return rank(candidates, prefix: prefix.token)
    }

    // MARK: - tokenizer (rough)

    /// 当前光标处的 token：从光标往前找连续的字母数字下划线 / 反引号。
    public static func currentToken(text: String, cursor: Int) -> (token: String, range: Range<Int>) {
        let chars = Array(text)
        let safe = max(0, min(cursor, chars.count))
        var start = safe
        while start > 0 {
            let c = chars[start - 1]
            if c.isLetter || c.isNumber || c == "_" || c == "." { start -= 1 }
            else { break }
        }
        let token = String(chars[start..<safe])
        return (token, start..<safe)
    }

    // MARK: - context detection

    public static func detectContext(text: String, cursor: Int) -> Context {
        let chars = Array(text)
        let safe = max(0, min(cursor, chars.count))
        // 当前 token
        let cur = currentToken(text: text, cursor: cursor)
        if cur.token.contains(".") {
            let parts = cur.token.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            let prefix = String(parts.first ?? "")
            return .afterDot(prefix)
        }
        // 往前扫描最近的关键字
        // 跳过当前 token 本身
        var i = cur.range.lowerBound
        // 反向取若干非空白字符
        var lastWord = ""
        var phase = 0   // 0: skip whitespace, 1: collecting
        while i > 0 {
            i -= 1
            let c = chars[i]
            if phase == 0 {
                if c.isWhitespace { continue }
                phase = 1
            }
            if c.isLetter || c == "_" {
                lastWord.append(c)
            } else {
                break
            }
        }
        let kw = String(lastWord.reversed()).uppercased()
        switch kw {
        case "FROM", "JOIN":      return .afterFrom
        case "INTO":              return .afterInto
        case "UPDATE":            return .afterUpdate
        case "TABLE":             return .afterFrom    // "DROP TABLE", "ALTER TABLE", etc.
        case "SET":               return .afterSet
        case "WHERE", "AND", "OR", "ON", "HAVING":
            return .afterWhere
        case "BY":
            // 区分 ORDER BY / GROUP BY
            let prev = previousKeyword(chars: chars, before: i)
            if prev == "ORDER" { return .afterOrderBy }
            if prev == "GROUP" { return .afterGroupBy }
            return .afterWhere
        case "SELECT":            return .afterSelect
        default:                  return .generic
        }
    }

    private static func previousKeyword(chars: [Character], before idx: Int) -> String {
        var i = idx
        var word = ""
        // skip non-letters
        while i > 0 {
            i -= 1
            if chars[i].isWhitespace { continue }
            break
        }
        // collect letters
        while i >= 0 {
            let c = chars[i]
            if c.isLetter || c == "_" {
                word.append(c)
            } else { break }
            if i == 0 { break }
            i -= 1
        }
        return String(word.reversed()).uppercased()
    }

    // MARK: - candidates

    private static func candidatesFor(
        context: Context,
        schema: SchemaSnapshot,
        prefix: String
    ) -> [Suggestion] {
        switch context {
        case .afterFrom, .afterUpdate, .afterInto, .afterJoin:
            return schema.tables.map { Suggestion(text: $0, kind: .table) }
                + schema.databases.map { Suggestion(text: $0, kind: .database) }

        case .afterDot(let qualifier):
            // db.<table> or table.<column>
            if let cols = schema.columnsByTable[qualifier] {
                return cols.map { Suggestion(text: $0, kind: .column, detail: qualifier) }
            }
            // 可能是 db. → 列出表
            return schema.tables.map { Suggestion(text: $0, kind: .table, detail: qualifier) }

        case .afterSelect:
            var out: [Suggestion] = [Suggestion(text: "*", kind: .keyword)]
            for cols in schema.columnsByTable.values {
                out.append(contentsOf: cols.map { Suggestion(text: $0, kind: .column) })
            }
            out.append(contentsOf: functions.map { Suggestion(text: $0, kind: .function) })
            return out

        case .afterWhere, .afterSet, .afterOrderBy, .afterGroupBy:
            var out: [Suggestion] = []
            for cols in schema.columnsByTable.values {
                out.append(contentsOf: cols.map { Suggestion(text: $0, kind: .column) })
            }
            // WHERE / SET / ORDER 里也常用 NOW() / IFNULL() 等
            out.append(contentsOf: functions.map { Suggestion(text: $0, kind: .function) })
            return out

        case .generic:
            var out: [Suggestion] = keywords.map { Suggestion(text: $0, kind: .keyword) }
            // 函数（VERSION / NOW / CONCAT 等）也算通用候选
            out.append(contentsOf: functions.map { Suggestion(text: $0, kind: .function) })
            out.append(contentsOf: schema.tables.map { Suggestion(text: $0, kind: .table) })
            for cols in schema.columnsByTable.values {
                out.append(contentsOf: cols.map { Suggestion(text: $0, kind: .column) })
            }
            return out
        }
    }

    // MARK: - ranking

    /// 按 prefix 过滤 + 排序：完全匹配 > 前缀匹配 > 包含匹配。大小写不敏感。
    public static func rank(_ candidates: [Suggestion], prefix: String) -> [Suggestion] {
        // 取 prefix 的尾部（去掉 db. 这种限定）
        // "users." → ""（只想列出所有列，不再过滤）
        // "users.na" → "na"
        let needle: String
        if prefix.contains(".") {
            // 取最后一个 . 之后的内容（可以为空）
            if let lastDotRange = prefix.range(of: ".", options: .backwards) {
                needle = String(prefix[lastDotRange.upperBound...]).lowercased()
            } else {
                needle = prefix.lowercased()
            }
        } else {
            needle = prefix.lowercased()
        }
        guard !needle.isEmpty else {
            // 空 prefix → 限定数量返回前 50 个，按字典序去重
            var seen = Set<String>()
            return candidates.filter { seen.insert($0.text).inserted }.prefix(50).map { $0 }
        }
        var matches: [(Suggestion, Int)] = []
        for c in candidates {
            let lower = c.text.lowercased()
            let score: Int
            if lower == needle { score = 1000 }
            else if lower.hasPrefix(needle) { score = 500 - lower.count }
            else if lower.contains(needle) { score = 100 - lower.count }
            else { continue }
            matches.append((c, score))
        }
        // 去重（keyword 与 column 同名时 keyword 优先）
        var seen = Set<String>()
        let sorted = matches.sorted { $0.1 > $1.1 }.map(\.0)
        return sorted.filter { seen.insert($0.text).inserted }
    }
}

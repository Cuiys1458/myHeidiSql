import Foundation

/// SQL 生成（UPDATE / INSERT / DELETE）— 表编辑提交流程的核心（PRD §5.3.7）。
///
/// 这是个**纯函数**模块，不知道 driver、不知道 actor。所有 IO 在上层。
/// 输出的 SQL 字符串已转义且可直接发给 MySQL。
public enum SQLGeneratorError: Error, Equatable {
    case noChangedColumns
    case noValues
    case rowSizeMismatch
    case columnNotFound(name: String)
    case noPKAndExcludedColumnEdited(column: String)
    case unsupportedColumnType(column: String)
}

public struct UpdateGenerationResult: Sendable {
    public let sql: String
    public let warnings: [String]
}

public enum SQLGenerator {

    // MARK: UPDATE

    /// 生成 UPDATE 语句。
    /// - 有 PK：`WHERE pk = ?`（多列 PK 用 AND）
    /// - 无 PK：`WHERE col1 <=> ? AND col2 <=> ? ...`，BLOB/TEXT 自动排除
    public static func update(
        database: String,
        table: String,
        schema: TableSchema,
        originalRow: [CellValue],
        changedColumns: [String: CellValue]
    ) throws -> String {
        try updateWithDiagnostics(
            database: database, table: table, schema: schema,
            originalRow: originalRow, changedColumns: changedColumns
        ).sql
    }

    /// 同 ``update(...)`` 但额外返回警告（如 BLOB/TEXT 被排除）。
    public static func updateWithDiagnostics(
        database: String,
        table: String,
        schema: TableSchema,
        originalRow: [CellValue],
        changedColumns: [String: CellValue]
    ) throws -> UpdateGenerationResult {
        guard !changedColumns.isEmpty else {
            throw SQLGeneratorError.noChangedColumns
        }
        guard originalRow.count == schema.columns.count else {
            throw SQLGeneratorError.rowSizeMismatch
        }

        // 校验：无 PK 且修改了"真二进制 BLOB"或大 TEXT → 拒绝（无法用 WHERE 锁定该行）
        // BLOB-as-JSON（内容是 JSON 字符串）允许：可以用字符串字面量写回。
        if !schema.hasPrimaryKey {
            for (colName, newValue) in changedColumns {
                guard let col = schema.columns.first(where: { $0.name == colName }) else {
                    throw SQLGeneratorError.columnNotFound(name: colName)
                }
                if col.normalizedType == .blob {
                    if !isJSONFlavoredEdit(newValue) {
                        throw SQLGeneratorError.noPKAndExcludedColumnEdited(column: colName)
                    }
                } else if isLargeText(col) {
                    throw SQLGeneratorError.noPKAndExcludedColumnEdited(column: colName)
                }
            }
        }

        let qualified = try SQLIdentifier.qualified(database: database, table: table)

        // SET 子句 —— 按 schema.columns 顺序保证稳定
        let setParts: [String] = try schema.columns.compactMap { col in
            guard let newVal = changedColumns[col.name] else { return nil }
            let qcol = try SQLIdentifier.quote(col.name)
            return "\(qcol) = \(literal(newVal))"
        }

        // WHERE 子句
        var whereParts: [String] = []
        var warnings: [String] = []

        if schema.hasPrimaryKey {
            for pkName in schema.primaryKey {
                guard let idx = schema.columns.firstIndex(where: { $0.name == pkName }) else {
                    throw SQLGeneratorError.columnNotFound(name: pkName)
                }
                let qcol = try SQLIdentifier.quote(pkName)
                whereParts.append("\(qcol) = \(literal(originalRow[idx]))")
            }
        } else {
            // 无 PK → 全列 NULL-safe equal
            for (idx, col) in schema.columns.enumerated() {
                if col.normalizedType == .blob || isLargeText(col) {
                    warnings.append("BLOB/TEXT column '\(col.name)' excluded from WHERE")
                    continue
                }
                let qcol = try SQLIdentifier.quote(col.name)
                whereParts.append("\(qcol) <=> \(literal(originalRow[idx]))")
            }
        }

        let sql = "UPDATE \(qualified) SET \(setParts.joined(separator: ", ")) WHERE \(whereParts.joined(separator: " AND "))"
        return UpdateGenerationResult(sql: sql, warnings: warnings)
    }

    // MARK: INSERT

    public static func insert(
        database: String,
        table: String,
        schema: TableSchema,
        values: [String: CellValue]
    ) throws -> String {
        guard !values.isEmpty else { throw SQLGeneratorError.noValues }
        let qualified = try SQLIdentifier.qualified(database: database, table: table)

        // 列顺序按 schema 顺序 → SQL 稳定可比对
        var cols: [String] = []
        var vals: [String] = []
        for col in schema.columns {
            guard let v = values[col.name] else { continue }
            cols.append(try SQLIdentifier.quote(col.name))
            vals.append(literal(v))
        }
        guard !cols.isEmpty else { throw SQLGeneratorError.noValues }

        return "INSERT INTO \(qualified) (\(cols.joined(separator: ", "))) VALUES (\(vals.joined(separator: ", ")))"
    }

    // MARK: DELETE

    public static func delete(
        database: String,
        table: String,
        schema: TableSchema,
        originalRow: [CellValue]
    ) throws -> String {
        guard originalRow.count == schema.columns.count else {
            throw SQLGeneratorError.rowSizeMismatch
        }
        let qualified = try SQLIdentifier.qualified(database: database, table: table)

        var whereParts: [String] = []
        if schema.hasPrimaryKey {
            for pkName in schema.primaryKey {
                guard let idx = schema.columns.firstIndex(where: { $0.name == pkName }) else {
                    throw SQLGeneratorError.columnNotFound(name: pkName)
                }
                let qcol = try SQLIdentifier.quote(pkName)
                whereParts.append("\(qcol) = \(literal(originalRow[idx]))")
            }
        } else {
            for (idx, col) in schema.columns.enumerated() {
                if col.normalizedType == .blob || isLargeText(col) { continue }
                let qcol = try SQLIdentifier.quote(col.name)
                whereParts.append("\(qcol) <=> \(literal(originalRow[idx]))")
            }
        }

        return "DELETE FROM \(qualified) WHERE \(whereParts.joined(separator: " AND "))"
    }

    // MARK: literal escaping

    /// 把 ``CellValue`` 转成 MySQL 字面量（已转义，可直接拼）。
    public static func literal(_ v: CellValue) -> String {
        switch v {
        case .null:           return "NULL"
        case .int(let n):     return String(n)
        case .uint(let n):    return String(n)
        case .double(let d):  return String(d)
        case .decimal(let s): return s
        case .bool(let b):    return b ? "1" : "0"
        case .string(let s):  return "'\(escapeString(s))'"
        case .date(let d), .datetime(let d):
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            f.timeZone = TimeZone(secondsFromGMT: 0)
            return "'\(f.string(from: d))'"
        case .time(let s):    return "'\(escapeString(s))'"
        case .blob(let d):    return blobLiteral(d)
        case .json(let s):    return "'\(escapeString(s))'"
        case .unknown(let s): return "'\(escapeString(s))'"
        }
    }

    private static func escapeString(_ s: String) -> String {
        // MySQL 字符串字面量：'…'，单引号转义为两个单引号
        // 反斜杠转义保持（与 NO_BACKSLASH_ESCAPES sql_mode 兼容）
        s.replacingOccurrences(of: "'", with: "''")
    }

    /// BLOB 字面量：
    /// - 空 Data → `''`（与历史行为一致，避免破坏旧 commit）
    /// - 是合法 UTF-8 + 像 JSON → 字符串字面量（content 入库可读）
    /// - 否则 → MySQL 十六进制字面量 `0xABCD...`，二进制安全
    private static func blobLiteral(_ d: Data) -> String {
        if d.isEmpty { return "''" }
        if let s = JSONHelper.looksLikeJSONBLOB(d) {
            return "'\(escapeString(s))'"
        }
        // 不是 JSON：用十六进制字面量保留二进制原貌
        return "0x" + d.map { String(format: "%02X", $0) }.joined()
    }

    private static func isLargeText(_ col: ColumnMeta) -> Bool {
        // PRD §5.3.7.2：BLOB/TEXT 排除
        // text/mediumtext/longtext 都视为 large text
        let t = col.mysqlType.lowercased()
        return t.contains("text")
    }

    /// 该值是否能"按 JSON 文本"写入 BLOB 列。
    /// .null 也算（删 BLOB 是允许的）；.blob 内容若是合法 JSON 也算。
    private static func isJSONFlavoredEdit(_ v: CellValue) -> Bool {
        switch v {
        case .null:           return true
        case .json:           return true
        case .blob(let d):    return JSONHelper.looksLikeJSONBLOB(d) != nil
        case .string(let s):  return JSONHelper.isJSON(s)
        default:              return false
        }
    }
}

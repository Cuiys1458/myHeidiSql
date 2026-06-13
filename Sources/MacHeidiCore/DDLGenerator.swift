import Foundation

/// 表结构修改操作（PRD §11 v0.3）。
public enum AlterColumnOperation: Equatable, Sendable {
    case add(column: ColumnSpec, position: Position?)
    case drop(name: String)
    case modify(name: String, newSpec: ColumnSpec)
    case rename(oldName: String, newSpec: ColumnSpec)

    public enum Position: Hashable, Sendable {
        case first
        case after(String)
    }
}

/// 列规格定义（用于 ADD/MODIFY/CHANGE）。
public struct ColumnSpec: Equatable, Sendable {
    public var name: String
    public var mysqlType: String           // 如 "INT", "VARCHAR(100)", "BIGINT UNSIGNED"
    public var nullable: Bool
    public var defaultLiteral: String?      // 已是 SQL literal，如 "'active'", "0", "NULL", "CURRENT_TIMESTAMP"
    public var isAutoIncrement: Bool
    public var isPrimaryKey: Bool          // ADD COLUMN ... PRIMARY KEY 内联
    public var comment: String?

    public init(name: String, mysqlType: String,
                nullable: Bool = true,
                defaultLiteral: String? = nil,
                isAutoIncrement: Bool = false,
                isPrimaryKey: Bool = false,
                comment: String? = nil) {
        self.name = name; self.mysqlType = mysqlType
        self.nullable = nullable; self.defaultLiteral = defaultLiteral
        self.isAutoIncrement = isAutoIncrement; self.isPrimaryKey = isPrimaryKey
        self.comment = comment
    }
}

public enum DDLGeneratorError: Error, Equatable {
    case duplicateColumn(String)
    case columnNotFound(String)
    case emptyIdentifier
    case noColumns
}

public struct DDLResult: Sendable, Equatable {
    public let sql: String
    public let warnings: [String]
}

public enum DDLGenerator {

    // MARK: - Foreign keys

    public struct ForeignKeySpec: Equatable, Sendable {
        public var name: String
        public var columns: [String]
        public var refDatabase: String?
        public var refTable: String
        public var refColumns: [String]
        public var onDelete: ReferentialAction
        public var onUpdate: ReferentialAction

        public enum ReferentialAction: String, Sendable, CaseIterable {
            case noAction = "NO ACTION"
            case restrict = "RESTRICT"
            case cascade  = "CASCADE"
            case setNull  = "SET NULL"
        }

        public init(name: String, columns: [String],
                    refDatabase: String? = nil, refTable: String, refColumns: [String],
                    onDelete: ReferentialAction = .noAction,
                    onUpdate: ReferentialAction = .noAction) {
            self.name = name; self.columns = columns
            self.refDatabase = refDatabase; self.refTable = refTable
            self.refColumns = refColumns
            self.onDelete = onDelete; self.onUpdate = onUpdate
        }
    }

    public static func addForeignKey(
        database: String, table: String, fk: ForeignKeySpec
    ) throws -> String {
        let name = fk.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw DDLGeneratorError.emptyIdentifier }
        let cols = fk.columns.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let refCols = fk.refColumns.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !cols.isEmpty, !refCols.isEmpty else { throw DDLGeneratorError.noColumns }
        guard !fk.refTable.trimmingCharacters(in: .whitespaces).isEmpty
        else { throw DDLGeneratorError.emptyIdentifier }

        let qualified = try SQLIdentifier.qualified(database: database, table: table)
        let qFK = try SQLIdentifier.quote(name)
        let qCols = try cols.map { try SQLIdentifier.quote($0) }.joined(separator: ", ")
        let qRefTable: String
        if let refDb = fk.refDatabase, !refDb.isEmpty {
            qRefTable = try SQLIdentifier.qualified(database: refDb, table: fk.refTable)
        } else {
            qRefTable = try SQLIdentifier.quote(fk.refTable)
        }
        let qRefCols = try refCols.map { try SQLIdentifier.quote($0) }.joined(separator: ", ")
        return "ALTER TABLE \(qualified) ADD CONSTRAINT \(qFK) "
            + "FOREIGN KEY (\(qCols)) REFERENCES \(qRefTable) (\(qRefCols)) "
            + "ON DELETE \(fk.onDelete.rawValue) ON UPDATE \(fk.onUpdate.rawValue)"
    }

    public static func dropForeignKey(
        database: String, table: String, name: String
    ) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw DDLGeneratorError.emptyIdentifier }
        let qualified = try SQLIdentifier.qualified(database: database, table: table)
        let qFK = try SQLIdentifier.quote(trimmed)
        return "ALTER TABLE \(qualified) DROP FOREIGN KEY \(qFK)"
    }

    // MARK: - Table options

    public static func setTableOptions(
        database: String, table: String,
        engine: String? = nil,
        charset: String? = nil,
        collation: String? = nil,
        comment: String? = nil
    ) throws -> String? {
        let qualified = try SQLIdentifier.qualified(database: database, table: table)
        var parts: [String] = []
        if let e = engine?.trimmingCharacters(in: .whitespaces), !e.isEmpty {
            parts.append("ENGINE=\(e)")
        }
        if let c = charset?.trimmingCharacters(in: .whitespaces), !c.isEmpty {
            parts.append("DEFAULT CHARSET=\(c)")
        }
        if let cl = collation?.trimmingCharacters(in: .whitespaces), !cl.isEmpty {
            parts.append("COLLATE=\(cl)")
        }
        if let cm = comment {
            let escaped = cm.replacingOccurrences(of: "'", with: "''")
            parts.append("COMMENT='\(escaped)'")
        }
        guard !parts.isEmpty else { return nil }
        return "ALTER TABLE \(qualified) " + parts.joined(separator: ", ")
    }

    public static func renameTable(
        database: String, table: String, newName: String
    ) throws -> String {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw DDLGeneratorError.emptyIdentifier }
        let qualified = try SQLIdentifier.qualified(database: database, table: table)
        let qNew = try SQLIdentifier.qualified(database: database, table: trimmed)
        return "RENAME TABLE \(qualified) TO \(qNew)"
    }

    // MARK: - Index operations

    /// 生成 ADD INDEX 语句。
    public static func addIndex(
        database: String,
        table: String,
        indexName: String,
        columns: [String],
        unique: Bool
    ) throws -> String {
        let trimmedIdx = indexName.trimmingCharacters(in: .whitespaces)
        guard !trimmedIdx.isEmpty else { throw DDLGeneratorError.emptyIdentifier }
        let cleanCols = columns.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !cleanCols.isEmpty else { throw DDLGeneratorError.noColumns }

        let qualified = try SQLIdentifier.qualified(database: database, table: table)
        let qIdx = try SQLIdentifier.quote(trimmedIdx)
        let qCols = try cleanCols.map { try SQLIdentifier.quote($0) }
            .joined(separator: ", ")
        let kind = unique ? "UNIQUE INDEX" : "INDEX"
        return "ALTER TABLE \(qualified) ADD \(kind) \(qIdx) (\(qCols))"
    }

    /// 生成 DROP INDEX 语句。`PRIMARY` 走 `DROP PRIMARY KEY`。
    public static func dropIndex(
        database: String,
        table: String,
        indexName: String
    ) throws -> String {
        let trimmed = indexName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw DDLGeneratorError.emptyIdentifier }
        let qualified = try SQLIdentifier.qualified(database: database, table: table)
        if trimmed.uppercased() == "PRIMARY" {
            return "ALTER TABLE \(qualified) DROP PRIMARY KEY"
        }
        let qIdx = try SQLIdentifier.quote(trimmed)
        return "ALTER TABLE \(qualified) DROP INDEX \(qIdx)"
    }

    // MARK: - Column operations

    /// 生成 ALTER TABLE 语句 + 警告。
    public static func alter(
        database: String,
        table: String,
        currentColumns: [ColumnMeta],
        currentPrimaryKey: [String],
        operation: AlterColumnOperation
    ) throws -> DDLResult {
        let qualified = try SQLIdentifier.qualified(database: database, table: table)
        var warnings: [String] = []

        switch operation {
        case .add(let spec, let position):
            try validateNew(spec: spec, existing: currentColumns)
            let frag = try renderColumnFragment(spec: spec)
            var posSQL = ""
            if let position = position {
                switch position {
                case .first: posSQL = " FIRST"
                case .after(let name):
                    posSQL = " AFTER " + (try SQLIdentifier.quote(name))
                }
            }
            return DDLResult(
                sql: "ALTER TABLE \(qualified) ADD COLUMN \(frag)\(posSQL)",
                warnings: warnings
            )

        case .drop(let name):
            try validateExists(name: name, in: currentColumns)
            if currentPrimaryKey.contains(name) {
                warnings.append("dropping PRIMARY KEY column '\(name)'")
            }
            let q = try SQLIdentifier.quote(name)
            return DDLResult(
                sql: "ALTER TABLE \(qualified) DROP COLUMN \(q)",
                warnings: warnings
            )

        case .modify(let name, let newSpec):
            try validateExists(name: name, in: currentColumns)
            // MODIFY 保留原列名，改类型/可空性/默认值
            var spec = newSpec
            spec.name = name
            let frag = try renderColumnFragment(spec: spec)
            return DDLResult(
                sql: "ALTER TABLE \(qualified) MODIFY COLUMN \(frag)",
                warnings: warnings
            )

        case .rename(let oldName, let newSpec):
            try validateExists(name: oldName, in: currentColumns)
            // 重命名要用 CHANGE，可同时改类型
            let qOld = try SQLIdentifier.quote(oldName)
            let qNew = try SQLIdentifier.quote(newSpec.name)
            let typePart = try renderTypeAndNullability(spec: newSpec)
            return DDLResult(
                sql: "ALTER TABLE \(qualified) CHANGE COLUMN \(qOld) \(qNew) \(typePart)",
                warnings: warnings
            )
        }
    }

    // MARK: - private

    /// 校验新增列：名字非空 + 不重复
    private static func validateNew(spec: ColumnSpec, existing: [ColumnMeta]) throws {
        let trimmed = spec.name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { throw DDLGeneratorError.emptyIdentifier }
        if existing.contains(where: { $0.name == spec.name }) {
            throw DDLGeneratorError.duplicateColumn(spec.name)
        }
    }

    private static func validateExists(name: String, in existing: [ColumnMeta]) throws {
        if !existing.contains(where: { $0.name == name }) {
            throw DDLGeneratorError.columnNotFound(name)
        }
    }

    /// `\`col\` TYPE [NULL|NOT NULL] [DEFAULT ...] [AUTO_INCREMENT] [PRIMARY KEY] [COMMENT '...']`
    private static func renderColumnFragment(spec: ColumnSpec) throws -> String {
        let q = try SQLIdentifier.quote(spec.name)
        var parts: [String] = [q, try renderTypeAndNullability(spec: spec)]

        if let def = spec.defaultLiteral {
            parts.append("DEFAULT \(def)")
        }
        if spec.isAutoIncrement {
            parts.append("AUTO_INCREMENT")
        }
        if spec.isPrimaryKey {
            parts.append("PRIMARY KEY")
        }
        if let c = spec.comment, !c.isEmpty {
            let escaped = c.replacingOccurrences(of: "'", with: "''")
            parts.append("COMMENT '\(escaped)'")
        }
        // type+null 已经合并；这里把 SQL 片段从 [name, type+null, ...] 拼起来：
        // parts[0] = `name`，parts[1] = "TYPE NULL/NOT NULL"，后面是 DEFAULT/AUTO_INC/...
        // 合并为：`name` TYPE NULL DEFAULT ...
        let head = parts[0]
        let typePart = parts[1]
        let tail = parts.dropFirst(2).joined(separator: " ")
        return tail.isEmpty ? "\(head) \(typePart)" : "\(head) \(typePart) \(tail)"
    }

    /// `TYPE [NULL|NOT NULL]`
    private static func renderTypeAndNullability(spec: ColumnSpec) throws -> String {
        let t = spec.mysqlType.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { throw DDLGeneratorError.emptyIdentifier }
        let nullability = spec.nullable ? "NULL" : "NOT NULL"
        return "\(t) \(nullability)"
    }
}

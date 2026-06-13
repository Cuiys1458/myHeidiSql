import Foundation

// MARK: - ResultSet / ExecResult

public struct ResultSet: Sendable, Equatable {
    public let columns: [ColumnMeta]
    public let rows: [[CellValue]]
    public let executionTime: Duration
    public let warnings: [String]

    public init(columns: [ColumnMeta], rows: [[CellValue]],
                executionTime: Duration, warnings: [String]) {
        self.columns = columns
        self.rows = rows
        self.executionTime = executionTime
        self.warnings = warnings
    }
}

public struct ExecResult: Sendable, Equatable {
    public let affectedRows: UInt64
    public let lastInsertId: UInt64?
    public let executionTime: Duration
    public let warnings: [String]

    public init(affectedRows: UInt64, lastInsertId: UInt64?,
                executionTime: Duration, warnings: [String]) {
        self.affectedRows = affectedRows
        self.lastInsertId = lastInsertId
        self.executionTime = executionTime
        self.warnings = warnings
    }
}

// MARK: - Column / Table 元数据

public struct ColumnMeta: Sendable, Equatable {
    public let name: String
    public let mysqlType: String            // 原始类型字符串，如 "varchar(255)"
    public let normalizedType: NormalizedType
    public let nullable: Bool
    public let defaultValue: CellValue?
    public let isAutoIncrement: Bool
    public let isUnsigned: Bool
    public let maxLength: Int?
    public let precision: Int?
    public let scale: Int?
    public let comment: String

    public init(name: String, mysqlType: String, normalizedType: NormalizedType,
                nullable: Bool, defaultValue: CellValue?, isAutoIncrement: Bool,
                isUnsigned: Bool, maxLength: Int?, precision: Int?, scale: Int?,
                comment: String) {
        self.name = name; self.mysqlType = mysqlType; self.normalizedType = normalizedType
        self.nullable = nullable; self.defaultValue = defaultValue
        self.isAutoIncrement = isAutoIncrement; self.isUnsigned = isUnsigned
        self.maxLength = maxLength; self.precision = precision; self.scale = scale
        self.comment = comment
    }
}

public enum NormalizedType: String, Sendable, Equatable {
    case int, uint, double, decimal, string, bool, date, datetime, time, blob, json, unknown
}

// MARK: - CellValue（PRD §A 类型映射表）

public enum CellValue: Sendable, Equatable {
    case null
    case int(Int64)
    case uint(UInt64)
    case double(Double)
    case decimal(String)        // 字符串保精度
    case string(String)
    case bool(Bool)
    case date(Date)
    case datetime(Date)
    case time(String)           // MySQL TIME 可超 24h
    case blob(Data)
    case json(String)
    case unknown(String)
}

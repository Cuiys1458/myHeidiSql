import Foundation

/// 表结构信息：列定义 + 主键 + 索引（最小集，beta 用）。
public struct TableSchema: Sendable, Equatable {
    public let columns: [ColumnMeta]
    public let primaryKey: [String]    // 空数组 = 无 PK
    public let indices: [IndexMeta]

    public init(columns: [ColumnMeta], primaryKey: [String], indices: [IndexMeta]) {
        self.columns = columns
        self.primaryKey = primaryKey
        self.indices = indices
    }

    /// 主键列在 columns 中的索引；用于从 row 取值。
    public var primaryKeyIndices: [Int] {
        primaryKey.compactMap { name in columns.firstIndex { $0.name == name } }
    }

    /// 是否有主键（影响 UPDATE/DELETE WHERE 生成策略）。
    public var hasPrimaryKey: Bool { !primaryKey.isEmpty }
}

public struct IndexMeta: Sendable, Equatable {
    public let name: String
    public let columns: [String]
    public let unique: Bool
    public init(name: String, columns: [String], unique: Bool) {
        self.name = name
        self.columns = columns
        self.unique = unique
    }
}

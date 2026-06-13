import Foundation

/// 表数据浏览中的"待提交编辑"集合（PRD §5.3.6 ~ §5.3.9）。
///
/// 包含三类挂起操作：
/// - **UPDATE**：现有行某些单元格被修改，记录为 `(rowId → [colName: newValue])`
/// - **DELETE**：现有行被标记删除
/// - **INSERT**：用户在末尾添加的新行
public struct PendingEdits: Sendable {

    public typealias RowID = String   // 主键 hash 或 UUID 串

    /// 每行的脏单元格：rowId → (columnName → newValue)
    private var updates: [RowID: [String: CellValue]] = [:]

    /// 标记删除的行 id
    private var deletes: Set<RowID> = []

    /// 用户新增的行
    public private(set) var pendingInserts: [PendingInsertRow] = []

    public init() {}

    // MARK: dirty queries

    public var dirtyCellCount: Int {
        updates.values.reduce(0) { $0 + $1.count }
    }

    public func isDirty(rowId: RowID) -> Bool {
        (updates[rowId]?.isEmpty == false)
    }

    public func dirtyCells(rowId: RowID) -> [String: CellValue] {
        updates[rowId] ?? [:]
    }

    public var dirtyRowIds: [RowID] { Array(updates.keys) }
    public var deletedRowIds: [RowID] { Array(deletes) }

    public func isMarkedForDeletion(rowId: RowID) -> Bool {
        deletes.contains(rowId)
    }

    // MARK: mutations

    /// 编辑一个单元格。如果新值与原始值相等 → 自动从 updates 中移除。
    public mutating func editCell(
        rowId: RowID,
        originalValues: [CellValue],
        columnIndex: Int,
        newValue: CellValue,
        columns: [ColumnMeta]
    ) {
        guard columnIndex >= 0, columnIndex < columns.count else { return }
        let colName = columns[columnIndex].name
        let original = originalValues[columnIndex]

        var rowMap = updates[rowId] ?? [:]
        if newValue == original {
            rowMap.removeValue(forKey: colName)
        } else {
            rowMap[colName] = newValue
        }
        if rowMap.isEmpty {
            updates.removeValue(forKey: rowId)
        } else {
            updates[rowId] = rowMap
        }
    }

    public mutating func markRowDelete(rowId: RowID) {
        deletes.insert(rowId)
    }

    public mutating func unmarkRowDelete(rowId: RowID) {
        deletes.remove(rowId)
    }

    @discardableResult
    public mutating func addNewRow(initialValues: [String: CellValue]) -> UUID {
        let row = PendingInsertRow(localId: UUID(), values: initialValues)
        pendingInserts.append(row)
        return row.localId
    }

    public mutating func setInsertCell(localId: UUID, column: String, value: CellValue) {
        if let idx = pendingInserts.firstIndex(where: { $0.localId == localId }) {
            pendingInserts[idx].values[column] = value
        }
    }

    public mutating func removeInsertRow(localId: UUID) {
        pendingInserts.removeAll { $0.localId == localId }
    }

    public mutating func discard() {
        updates.removeAll()
        deletes.removeAll()
        pendingInserts.removeAll()
    }

    public var isEmpty: Bool {
        updates.isEmpty && deletes.isEmpty && pendingInserts.isEmpty
    }
}

/// 用户新增但未提交的行。
public struct PendingInsertRow: Sendable, Equatable, Identifiable {
    public let localId: UUID
    public var values: [String: CellValue]

    public var id: UUID { localId }

    /// 用户填了至少一个字段，才生成 INSERT。
    public var hasUserSetValues: Bool {
        !values.isEmpty
    }
}

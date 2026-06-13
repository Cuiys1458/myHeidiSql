import Foundation

/// 根据当前选中节点决定 F5 刷新的目标（PRD §5.2.5）。
///
/// 这是个纯函数，把 UI 上的选中状态映射成"该刷新什么"，方便 TDD。
public enum RefreshTarget: Equatable, Sendable {
    /// 刷新整个 session：重新 SHOW DATABASES（保留 expanded 状态）
    case sessionDatabases

    /// 刷新某个库下的表/视图列表
    case databaseTables(String)
}

public enum RefreshPolicy {

    public static func target(
        for selection: RefreshSelection
    ) -> RefreshTarget {
        switch selection {
        case .none:
            return .sessionDatabases
        case .session:
            return .sessionDatabases
        case .database(let name):
            return .databaseTables(name)
        case .table(let database, _):
            // 表选中时刷新其父库 → 这个表会以新元数据重新出现
            return .databaseTables(database)
        case .view(let database, _):
            return .databaseTables(database)
        }
    }
}

/// 与 ``AppEnvironment.TreeSelection`` 同构的 Core 层枚举（避免 App 层依赖反射进 Core）。
public enum RefreshSelection: Equatable, Sendable {
    case none
    case session
    case database(String)
    case table(database: String, table: String)
    case view(database: String, view: String)
}

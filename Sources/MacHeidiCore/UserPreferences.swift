import Foundation

/// 用户偏好持久化（UserDefaults 包装）。
///
/// 显式指定 suite name，避免 SPM executable 的 bundle id 不确定问题。
public final class UserPreferences: @unchecked Sendable {

    public static let suiteName = "com.macheidi.app"
    public static let shared = UserPreferences(
        defaults: UserDefaults(suiteName: suiteName) ?? .standard
    )

    private let defaults: UserDefaults
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    // MARK: keys

    private enum Key {
        static let pageSize = "macheidi.pref.pageSize"
        static let columnWidthPrefix = "macheidi.pref.colWidth."  // + db.table.column
    }

    // MARK: page size

    public var pageSize: Int {
        get {
            let v = defaults.integer(forKey: Key.pageSize)
            return v > 0 ? v : 100   // 默认 100
        }
        set { defaults.set(newValue, forKey: Key.pageSize) }
    }

    // MARK: column widths

    public func columnWidth(database: String, table: String, column: String) -> Double? {
        let k = Key.columnWidthPrefix + "\(database).\(table).\(column)"
        let v = defaults.double(forKey: k)
        return v > 0 ? v : nil
    }

    public func setColumnWidth(_ width: Double,
                                database: String, table: String, column: String) {
        let k = Key.columnWidthPrefix + "\(database).\(table).\(column)"
        defaults.set(width, forKey: k)
    }
}

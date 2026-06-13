import Foundation
import MacHeidiCore
import MacHeidiMySQL

/// `SessionManagerView` 不直接 import MacHeidiMySQL（避免把它泄露给视图层），
/// 这里集中提供工厂。
func _make() -> any DBClient {
    MySQLClient()
}

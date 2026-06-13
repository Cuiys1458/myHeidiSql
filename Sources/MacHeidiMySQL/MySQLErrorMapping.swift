import Foundation
import MySQLNIO
import MacHeidiCore

/// 把 MySQLNIO 抛出的错误统一翻译成 ``DBError``。
///
/// `MySQLError` 的 `.server(ERR_Packet)` 里带 errno + sqlstate，是主要信息来源；
/// 其他 case（连接关闭、协议错）按性质归类。
func mapMySQLError(_ error: any Error) -> DBError {
    if let already = error as? DBError { return already }

    if let my = error as? MySQLError {
        switch my {
        case .server(let pkt):
            let raw = MySQLRawError(
                errno: Int(pkt.errorCode.rawValue),
                sqlState: pkt.sqlState ?? "",
                message: pkt.errorMessage
            )
            return DBError.normalize(raw)

        case .duplicateEntry(let msg):
            return .constraint(mysqlErrno: 1062, sqlState: "23000", message: msg)

        case .invalidSyntax(let msg):
            return .syntax(mysqlErrno: 1064, sqlState: "42000", message: msg)

        case .closed:
            return .network(message: "Connection closed", underlying: my)

        case .secureConnectionRequired,
             .unsupportedAuthPlugin,
             .authPluginDataError,
             .missingOrInvalidAuthMoreDataStatusTag,
             .missingOrInvalidAuthPluginInlineCommand,
             .missingAuthPluginInlineData:
            return .auth(message: my.message, mysqlErrno: nil)

        case .unsupportedServer(let msg):
            return .server(mysqlErrno: -1, sqlState: "", message: msg)

        case .protocolError:
            return .network(message: "MySQL protocol error", underlying: my)
        }
    }

    // NIO/Posix 网络错（包括 ChannelError、IOError、connection refused）
    let desc = String(describing: error)
    let lower = desc.lowercased()
    if lower.contains("refused") || lower.contains("unreachable")
        || lower.contains("timed out") || lower.contains("timeout")
        || lower.contains("nio") || lower.contains("nameresolution")
        || lower.contains("eof") || lower.contains("connection reset") {
        return .network(message: desc, underlying: error)
    }

    return DBError.normalize(error)
}

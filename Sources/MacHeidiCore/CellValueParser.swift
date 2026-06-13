import Foundation

/// 用户字符串输入 → 类型化 ``CellValue``，含校验（PRD §5.3.6.2）。
public enum CellValueParseError: Error, Equatable {
    case invalidInteger(String)
    case invalidFloat(String)
    case invalidDecimal(String)
    case invalidBool(String)
    case nullNotAllowed
    case unsupported
}

public enum CellValueParser {

    /// 把 NULL 显式作为输入。校验 NOT NULL 列。
    public static func parseNull(column: ColumnMeta) throws -> CellValue {
        guard column.nullable else {
            throw CellValueParseError.nullNotAllowed
        }
        return .null
    }

    /// 文本输入 → CellValue，按列类型路由。
    public static func parse(_ raw: String, column: ColumnMeta) throws -> CellValue {
        switch column.normalizedType {
        case .int:
            if column.isUnsigned {
                guard let v = UInt64(raw) else { throw CellValueParseError.invalidInteger(raw) }
                return .uint(v)
            }
            guard let v = Int64(raw) else { throw CellValueParseError.invalidInteger(raw) }
            return .int(v)
        case .uint:
            guard let v = UInt64(raw) else { throw CellValueParseError.invalidInteger(raw) }
            return .uint(v)
        case .double:
            guard let v = Double(raw) else { throw CellValueParseError.invalidFloat(raw) }
            return .double(v)
        case .decimal:
            // DECIMAL 保字符串精度（PRD §A）。但仍校验是否合法数字字面量。
            guard isValidDecimalLiteral(raw) else {
                throw CellValueParseError.invalidDecimal(raw)
            }
            return .decimal(raw)
        case .bool:
            switch raw.lowercased() {
            case "true", "1", "yes", "on": return .bool(true)
            case "false", "0", "no", "off", "": return .bool(false)
            default: throw CellValueParseError.invalidBool(raw)
            }
        case .string:
            return .string(raw)
        case .json:
            return .json(raw)
        case .date, .datetime:
            // 文本透传，由 server 校验（MVP）
            return .string(raw)
        case .time:
            return .time(raw)
        case .blob, .unknown:
            // PRD §A：BLOB / 空间类型 MVP 只读
            throw CellValueParseError.unsupported
        }
    }

    private static func isValidDecimalLiteral(_ s: String) -> Bool {
        // 简单宽松校验：可选 ± / 数字 / 一个小数点
        let chars = Array(s)
        guard !chars.isEmpty else { return false }
        var i = 0
        if chars[0] == "-" || chars[0] == "+" { i += 1 }
        var sawDigit = false
        var sawDot = false
        while i < chars.count {
            if chars[i].isNumber { sawDigit = true }
            else if chars[i] == "." {
                if sawDot { return false }
                sawDot = true
            } else { return false }
            i += 1
        }
        return sawDigit
    }
}

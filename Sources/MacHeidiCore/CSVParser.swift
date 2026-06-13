import Foundation

/// 严格按 RFC 4180 解析 CSV：
/// - 字段分隔符可定制
/// - `"..."` 包裹的字段中：`""` = 一个字面双引号
/// - 包裹字段内可包含换行 / 逗号
/// - 行尾支持 \n / \r\n
public enum CSVParser {

    public enum ParseError: Error, Equatable {
        case unterminatedQuote(line: Int)
    }

    /// 解析整段 CSV 为二维字符串数组（不含 NULL 概念，空字段是空串）。
    public static func parse(_ text: String, separator: Character = ",")
        throws -> [[String]] {
        // 关键：Swift String 把 "\r\n" 视为一个 grapheme cluster，
        // 直接 Array(text) 会丢掉 CRLF 的边界。先用 unicodeScalars 处理。
        var rows: [[String]] = []
        var current: [String] = []
        var field = ""
        var inQuotes = false
        var lineNum = 1
        var hadAnyContentInRow = false

        let scalars = Array(text.unicodeScalars)
        let sepScalar = separator.unicodeScalars.first!
        let CR: Unicode.Scalar = "\r"
        let LF: Unicode.Scalar = "\n"
        let DQ: Unicode.Scalar = "\""

        func endRow() {
            if hadAnyContentInRow || !current.isEmpty {
                current.append(field)
                rows.append(current)
            }
            current = []
            field = ""
            hadAnyContentInRow = false
        }

        var i = 0
        while i < scalars.count {
            let s = scalars[i]
            if inQuotes {
                if s == DQ {
                    if i + 1 < scalars.count, scalars[i + 1] == DQ {
                        field.append(Character(DQ))
                        i += 2; continue
                    }
                    inQuotes = false
                    hadAnyContentInRow = true
                    i += 1; continue
                }
                if s == LF { lineNum += 1 }
                field.unicodeScalars.append(s)
                i += 1; continue
            }
            if s == DQ && field.isEmpty {
                inQuotes = true
                i += 1; continue
            }
            if s == sepScalar {
                current.append(field); field = ""
                hadAnyContentInRow = true
                i += 1; continue
            }
            if s == CR {
                let isCRLF = i + 1 < scalars.count && scalars[i + 1] == LF
                endRow()
                lineNum += 1
                i += isCRLF ? 2 : 1
                continue
            }
            if s == LF {
                endRow()
                lineNum += 1
                i += 1; continue
            }
            field.unicodeScalars.append(s)
            hadAnyContentInRow = true
            i += 1
        }
        if inQuotes {
            throw ParseError.unterminatedQuote(line: lineNum)
        }
        if hadAnyContentInRow || !current.isEmpty {
            current.append(field)
            rows.append(current)
        }
        return rows
    }
}

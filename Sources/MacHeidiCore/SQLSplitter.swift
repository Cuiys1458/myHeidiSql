import Foundation

/// 拆分 SQL 编辑器文本为独立语句，识别 SELECT-like vs DML/DDL（PRD §5.4.3）。
///
/// 用单字符状态机：跟踪 4 个 in-* 状态（单引号 / 双引号 / 反引号 / 注释），
/// 任一为 true 时 `;` 不分隔。状态机不嵌套块注释（与 MySQL 行为一致）。
public enum SQLSplitter {

    public enum Classification: Equatable, Sendable {
        case query   // SELECT-like：返回结果集
        case exec    // DML/DDL：返回 affected rows
    }

    /// 将自由文本拆为独立语句。Trim 后丢弃空。
    public static func split(_ text: String) -> [String] {
        var statements: [String] = []
        var current = ""

        var inSingle = false
        var inDouble = false
        var inBacktick = false
        var inLineComment = false
        var inBlockComment = false
        var escapeNext = false

        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]

            // escape: 上一字符是反斜杠 → 当前字符不解释，直接吞
            if escapeNext {
                current.append(c)
                escapeNext = false
                i += 1
                continue
            }

            // line comment: 遇 \n 结束（注释字符也加入 current，等 trim 时一起算）
            if inLineComment {
                current.append(c)
                if c == "\n" { inLineComment = false }
                i += 1
                continue
            }

            // block comment: 找 */ 结束
            if inBlockComment {
                current.append(c)
                if c == "*" && i + 1 < chars.count && chars[i + 1] == "/" {
                    current.append("/")
                    inBlockComment = false
                    i += 2
                    continue
                }
                i += 1
                continue
            }

            // 进入注释判定（仅当不在字符串内）
            if !inSingle && !inDouble && !inBacktick {
                if c == "-" && i + 1 < chars.count && chars[i + 1] == "-" {
                    // 严格 MySQL 是 "-- " （后跟空白），但实践中编辑器都接受 "--"
                    inLineComment = true
                    current.append("--")
                    i += 2
                    continue
                }
                if c == "/" && i + 1 < chars.count && chars[i + 1] == "*" {
                    inBlockComment = true
                    current.append("/*")
                    i += 2
                    continue
                }
            }

            // 字符串边界（4 种引号）
            if !inDouble && !inBacktick {
                if c == "'" {
                    inSingle.toggle()
                    current.append(c)
                    i += 1
                    continue
                }
            }
            if !inSingle && !inBacktick {
                if c == "\"" {
                    inDouble.toggle()
                    current.append(c)
                    i += 1
                    continue
                }
            }
            if !inSingle && !inDouble {
                if c == "`" {
                    inBacktick.toggle()
                    current.append(c)
                    i += 1
                    continue
                }
            }

            // 反斜杠转义（仅在字符串内有效）
            if (inSingle || inDouble) && c == "\\" {
                current.append(c)
                escapeNext = true
                i += 1
                continue
            }

            // 分号分隔
            if c == ";" && !inSingle && !inDouble && !inBacktick {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    statements.append(trimmed)
                }
                current = ""
                i += 1
                continue
            }

            current.append(c)
            i += 1
        }

        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            statements.append(trimmed)
        }
        return statements
    }

    /// 判断语句类型 —— 第一个非空白非注释 token 决定。
    public static func classify(_ sql: String) -> Classification {
        let first = firstKeyword(sql)?.uppercased() ?? ""
        let queryKeywords: Set<String> = [
            "SELECT", "SHOW", "DESCRIBE", "DESC",
            "EXPLAIN", "WITH", "VALUES", "TABLE", "CALL"
        ]
        return queryKeywords.contains(first) ? .query : .exec
    }

    /// 用光标 offset 找到所在语句（PRD §5.4.3）。
    /// 光标在分号上 → 返回分号之前的语句；光标在尾部空白 → 返回最后一条。
    public static func statementAtCursor(text: String, offset: Int) -> String? {
        let ranges = splitWithRanges(text)
        if ranges.isEmpty { return nil }
        for (statement, range) in ranges {
            if offset >= range.lowerBound && offset <= range.upperBound {
                return statement
            }
        }
        // 越过最后一条 → 返回最后一条
        return ranges.last?.0
    }

    // MARK: - Internal helpers

    /// 跟 `split` 一样的状态机，但同时记录每条语句在原文中的 (lowerBound, upperBound) offset。
    static func splitWithRanges(_ text: String) -> [(String, Range<Int>)] {
        var out: [(String, Range<Int>)] = []
        var current = ""
        var startIdx = 0

        var inSingle = false
        var inDouble = false
        var inBacktick = false
        var inLineComment = false
        var inBlockComment = false
        var escapeNext = false

        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]

            if escapeNext { current.append(c); escapeNext = false; i += 1; continue }

            if inLineComment {
                current.append(c)
                if c == "\n" { inLineComment = false }
                i += 1; continue
            }

            if inBlockComment {
                current.append(c)
                if c == "*" && i + 1 < chars.count && chars[i + 1] == "/" {
                    current.append("/"); inBlockComment = false; i += 2; continue
                }
                i += 1; continue
            }

            if !inSingle && !inDouble && !inBacktick {
                if c == "-" && i + 1 < chars.count && chars[i + 1] == "-" {
                    inLineComment = true; current.append("--"); i += 2; continue
                }
                if c == "/" && i + 1 < chars.count && chars[i + 1] == "*" {
                    inBlockComment = true; current.append("/*"); i += 2; continue
                }
            }

            if !inDouble && !inBacktick, c == "'" { inSingle.toggle(); current.append(c); i += 1; continue }
            if !inSingle && !inBacktick, c == "\"" { inDouble.toggle(); current.append(c); i += 1; continue }
            if !inSingle && !inDouble, c == "`" { inBacktick.toggle(); current.append(c); i += 1; continue }

            if (inSingle || inDouble) && c == "\\" {
                current.append(c); escapeNext = true; i += 1; continue
            }

            if c == ";" && !inSingle && !inDouble && !inBacktick {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    out.append((trimmed, startIdx..<i))
                }
                current = ""
                startIdx = i + 1
                i += 1
                continue
            }

            current.append(c)
            i += 1
        }

        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            out.append((trimmed, startIdx..<chars.count))
        }
        return out
    }

    /// 跳过前导空白、行注释、块注释，返回第一个"实际"单词。
    private static func firstKeyword(_ sql: String) -> String? {
        var i = sql.startIndex
        let end = sql.endIndex
        while i < end {
            let c = sql[i]
            if c.isWhitespace { i = sql.index(after: i); continue }

            // 行注释
            if c == "-", let next = sql.index(i, offsetBy: 1, limitedBy: end),
               next < end, sql[next] == "-" {
                if let lf = sql[i...].firstIndex(of: "\n") {
                    i = sql.index(after: lf)
                } else {
                    return nil
                }
                continue
            }
            // 块注释
            if c == "/", let next = sql.index(i, offsetBy: 1, limitedBy: end),
               next < end, sql[next] == "*" {
                i = sql.index(i, offsetBy: 2)
                while i < end {
                    if sql[i] == "*", let after = sql.index(i, offsetBy: 1, limitedBy: end),
                       after < end, sql[after] == "/" {
                        i = sql.index(i, offsetBy: 2)
                        break
                    }
                    i = sql.index(after: i)
                }
                continue
            }

            // 找到第一个非空白非注释字符：截取直到下一个空白/`(`/分号
            let stopChars: Set<Character> = [" ", "\t", "\n", "(", ";"]
            var end2 = i
            while end2 < end && !stopChars.contains(sql[end2]) {
                end2 = sql.index(after: end2)
            }
            return String(sql[i..<end2])
        }
        return nil
    }
}

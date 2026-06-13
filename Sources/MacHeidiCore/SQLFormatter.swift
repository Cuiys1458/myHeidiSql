import Foundation

/// 极简 SQL 格式化（PRD §11 v0.6 提前到 v0.3）。
///
/// 不做语法解析（成本高），只做：
/// - 关键字大写
/// - 主子句换行（SELECT/FROM/WHERE/AND/OR/JOIN/GROUP BY/ORDER BY/LIMIT/HAVING）
/// - 子句首层缩进 2 空格
///
/// 不动：字符串字面量、注释、反引号标识符内的内容。
public enum SQLFormatter {

    public static func format(_ sql: String) -> String {
        // 用状态机扫描，避开字符串/注释里的关键字大写化
        let tokens = tokenize(sql)
        var out = ""
        var indent = 0
        var atLineStart = true

        let majorClauses: Set<String> = [
            "SELECT", "FROM", "WHERE", "GROUP", "ORDER", "HAVING",
            "LIMIT", "OFFSET", "UNION", "INSERT", "UPDATE", "DELETE",
            "VALUES", "SET", "INTO", "WITH"
        ]
        let joinKeywords: Set<String> = ["JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "CROSS"]
        let subClauseKeywords: Set<String> = ["AND", "OR", "ON"]

        var i = 0
        while i < tokens.count {
            let tok = tokens[i]
            switch tok.kind {
            case .word:
                let upper = tok.text.uppercased()
                // 找下一个非 whitespace token
                let next: Tok? = {
                    var j = i + 1
                    while j < tokens.count, tokens[j].kind == .whitespace { j += 1 }
                    return j < tokens.count ? tokens[j] : nil
                }()
                let nextNonWsIndex: Int = {
                    var j = i + 1
                    while j < tokens.count, tokens[j].kind == .whitespace { j += 1 }
                    return j
                }()

                // 主子句 → 换行 + 不缩进
                if majorClauses.contains(upper) {
                    if !out.isEmpty { trimTrailingSpaces(&out); out.append("\n") }
                    out.append(upper)
                    atLineStart = false
                    indent = 0
                    // GROUP BY / ORDER BY 把 BY 一起吞
                    if (upper == "GROUP" || upper == "ORDER"),
                       let nxt = next, nxt.kind == .word, nxt.text.uppercased() == "BY" {
                        out.append(" BY")
                        i = nextNonWsIndex
                    }
                    out.append("\n  ")
                    indent = 1
                    atLineStart = true
                    i += 1
                    continue
                }

                // JOIN → 单独换行
                if joinKeywords.contains(upper) {
                    if !out.isEmpty { trimTrailingSpaces(&out); out.append("\n") }
                    out.append(upper)
                    atLineStart = false
                    // 后跟 JOIN
                    if let nxt = next, nxt.kind == .word,
                       ["JOIN", "OUTER"].contains(nxt.text.uppercased()) {
                        out.append(" \(nxt.text.uppercased())")
                        i = nextNonWsIndex + 1
                        continue
                    }
                    i += 1
                    continue
                }

                // AND / OR → 缩进对齐
                if subClauseKeywords.contains(upper) {
                    trimTrailingSpaces(&out)
                    out.append("\n  ")
                    out.append(upper)
                    out.append(" ")
                    atLineStart = false
                    i += 1
                    continue
                }

                // 其它单词：大写化 SQL 关键字，原样保留 identifier
                if isLikelyKeyword(upper) {
                    appendWithSpace(&out, upper, atLineStart: &atLineStart)
                } else {
                    appendWithSpace(&out, tok.text, atLineStart: &atLineStart)
                }
                i += 1

            case .string, .quotedIdent, .lineComment, .blockComment, .symbol, .number:
                // 不动
                appendWithSpace(&out, tok.text, atLineStart: &atLineStart)
                i += 1
            case .whitespace:
                i += 1
            }
        }
        // 末尾分号回退到上一行末尾
        let result = out
            .replacingOccurrences(of: "\n  ;", with: ";")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result + (sql.hasSuffix(";") && !result.hasSuffix(";") ? ";" : "")
    }

    private static let knownKeywords: Set<String> = [
        "SELECT","FROM","WHERE","AND","OR","NOT","IN","IS","NULL","LIKE","BETWEEN",
        "GROUP","BY","ORDER","HAVING","LIMIT","OFFSET","JOIN","LEFT","RIGHT","INNER",
        "OUTER","CROSS","ON","AS","DISTINCT","UNION","ALL","CASE","WHEN","THEN","ELSE","END",
        "INSERT","INTO","VALUES","UPDATE","SET","DELETE","CREATE","TABLE","DROP","ALTER",
        "ADD","COLUMN","INDEX","KEY","PRIMARY","FOREIGN","REFERENCES","DESCRIBE","DESC",
        "ASC","EXPLAIN","SHOW","TRUNCATE","WITH","BEGIN","COMMIT","ROLLBACK","TRANSACTION",
        "IF","EXISTS","USE","CONSTRAINT","DEFAULT","UNIQUE","CHECK","TRUE","FALSE"
    ]
    private static func isLikelyKeyword(_ upper: String) -> Bool {
        knownKeywords.contains(upper)
    }

    private static func trimTrailingSpaces(_ s: inout String) {
        while let last = s.last, last == " " || last == "\t" { s.removeLast() }
    }

    private static func appendWithSpace(_ s: inout String, _ text: String,
                                         atLineStart: inout Bool) {
        if !atLineStart, !s.isEmpty,
           let last = s.last, last != " ", last != "\n",
           text.first.map({ !$0.isPunctuation || $0 == "(" }) ?? true {
            // 简单粗暴：词与词之间补空格；标点不强加（")" 不补空格的细节略）
            if !"()[],;.".contains(text.first ?? " ") {
                s.append(" ")
            }
        }
        s.append(text)
        atLineStart = false
    }

    // MARK: - tokenizer

    enum TokKind { case word, number, string, quotedIdent, lineComment, blockComment, symbol, whitespace }
    struct Tok { let text: String; let kind: TokKind }

    private static func tokenize(_ s: String) -> [Tok] {
        var out: [Tok] = []
        let chars = Array(s.unicodeScalars)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            // whitespace
            if Character(c).isWhitespace {
                var w = ""
                while i < chars.count, Character(chars[i]).isWhitespace {
                    w.unicodeScalars.append(chars[i]); i += 1
                }
                out.append(Tok(text: w, kind: .whitespace))
                continue
            }
            // line comment
            if c == "-", i + 1 < chars.count, chars[i + 1] == "-" {
                var t = ""
                while i < chars.count, chars[i] != "\n" {
                    t.unicodeScalars.append(chars[i]); i += 1
                }
                out.append(Tok(text: t, kind: .lineComment))
                continue
            }
            // block comment
            if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                var t = "/*"; i += 2
                while i < chars.count {
                    if chars[i] == "*", i + 1 < chars.count, chars[i + 1] == "/" {
                        t += "*/"; i += 2; break
                    }
                    t.unicodeScalars.append(chars[i]); i += 1
                }
                out.append(Tok(text: t, kind: .blockComment))
                continue
            }
            // string
            if c == "'" || c == "\"" {
                let quote = c
                var t = String(Character(quote)); i += 1
                while i < chars.count {
                    if chars[i] == "\\", i + 1 < chars.count {
                        t.unicodeScalars.append(chars[i]); t.unicodeScalars.append(chars[i + 1]); i += 2; continue
                    }
                    if chars[i] == quote {
                        t.unicodeScalars.append(chars[i]); i += 1; break
                    }
                    t.unicodeScalars.append(chars[i]); i += 1
                }
                out.append(Tok(text: t, kind: .string))
                continue
            }
            // backtick identifier
            if c == "`" {
                var t = "`"; i += 1
                while i < chars.count {
                    if chars[i] == "`" {
                        t += "`"; i += 1; break
                    }
                    t.unicodeScalars.append(chars[i]); i += 1
                }
                out.append(Tok(text: t, kind: .quotedIdent))
                continue
            }
            // number
            if Character(c).isNumber {
                var t = ""
                while i < chars.count, (Character(chars[i]).isNumber || chars[i] == ".") {
                    t.unicodeScalars.append(chars[i]); i += 1
                }
                out.append(Tok(text: t, kind: .number))
                continue
            }
            // word (letter / underscore / dot continuation)
            if Character(c).isLetter || c == "_" {
                var t = ""
                while i < chars.count {
                    let ch = chars[i]
                    if Character(ch).isLetter || Character(ch).isNumber || ch == "_" {
                        t.unicodeScalars.append(ch); i += 1
                    } else { break }
                }
                out.append(Tok(text: t, kind: .word))
                continue
            }
            // symbol
            var t = ""
            t.unicodeScalars.append(c); i += 1
            out.append(Tok(text: t, kind: .symbol))
        }
        return out
    }
}

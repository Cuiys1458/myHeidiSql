import Testing
import Foundation
@testable import MacHeidiCore

@Suite("JSONHelper — JSON detection / pretty-print / validate")
struct JSONHelperTests {

    // MARK: - isJSON

    @Test("Object is JSON")
    func objectIsJSON() {
        #expect(JSONHelper.isJSON(#"{"a":1}"#))
    }

    @Test("Array is JSON")
    func arrayIsJSON() {
        #expect(JSONHelper.isJSON(#"[1,2,3]"#))
    }

    @Test("Nested object is JSON")
    func nestedIsJSON() {
        #expect(JSONHelper.isJSON(#"{"outer":{"inner":[1,2]}}"#))
    }

    @Test("Object with whitespace and newlines is JSON")
    func whitespaceIsJSON() {
        #expect(JSONHelper.isJSON("  \n  {\n  \"a\": 1\n}\n"))
    }

    @Test("Chinese strings are JSON")
    func chineseIsJSON() {
        #expect(JSONHelper.isJSON(#"{"msg":"登录成功"}"#))
    }

    @Test("Bare number is NOT JSON (heuristic stricter than RFC)")
    func bareNumberIsNotJSON() {
        #expect(!JSONHelper.isJSON("42"))
    }

    @Test("Bare string is NOT JSON")
    func bareStringIsNotJSON() {
        #expect(!JSONHelper.isJSON("\"hello\""))
    }

    @Test("Empty string is NOT JSON")
    func emptyIsNotJSON() {
        #expect(!JSONHelper.isJSON(""))
    }

    @Test("Unbalanced brace is NOT JSON")
    func unbalancedIsNotJSON() {
        #expect(!JSONHelper.isJSON(#"{"a":1"#))
    }

    @Test("Single-quoted is NOT JSON (only double quotes are valid)")
    func singleQuotedIsNotJSON() {
        #expect(!JSONHelper.isJSON("{'a':1}"))
    }

    @Test("Trailing comma is accepted (Foundation lenient parser)")
    func trailingCommaIsAccepted() {
        // Foundation 的 JSONSerialization 在 macOS 14+ 接受 trailing comma。
        // 我们用它做底层校验，所以这里也接受。MySQL JSON 也常常接受。
        #expect(JSONHelper.isJSON(#"{"a":1,}"#))
    }

    @Test("Random binary-looking text is NOT JSON")
    func randomTextIsNotJSON() {
        #expect(!JSONHelper.isJSON("hello world"))
    }

    // MARK: - looksLikeJSONBLOB

    @Test("UTF-8 JSON Data → returns string")
    func blobOfJSON() {
        let s = #"{"code":500,"msg":"oops"}"#
        let data = Data(s.utf8)
        #expect(JSONHelper.looksLikeJSONBLOB(data) == s)
    }

    @Test("Empty Data → nil")
    func emptyBlob() {
        #expect(JSONHelper.looksLikeJSONBLOB(Data()) == nil)
    }

    @Test("Random binary bytes → nil")
    func binaryBlob() {
        // FFD8 FFE0 = JPEG header
        let data = Data([0xFF, 0xD8, 0xFF, 0xE0])
        #expect(JSONHelper.looksLikeJSONBLOB(data) == nil)
    }

    @Test("Plain text Data is NOT JSON BLOB")
    func plainTextBlob() {
        let data = Data("hello world".utf8)
        #expect(JSONHelper.looksLikeJSONBLOB(data) == nil)
    }

    @Test("Bare quoted string Data is NOT JSON BLOB")
    func bareStringBlob() {
        let data = Data(#""just a string""#.utf8)
        #expect(JSONHelper.looksLikeJSONBLOB(data) == nil)
    }

    // MARK: - prettyPrint

    @Test("Pretty-print indents with 2 spaces")
    func prettyPrintIndents() {
        let pretty = JSONHelper.prettyPrint(#"{"a":1,"b":2}"#)
        #expect(pretty != nil)
        // Foundation 默认是 2 空格缩进，sortedKeys 让 a 在 b 前
        let expected = "{\n  \"a\" : 1,\n  \"b\" : 2\n}"
        #expect(pretty == expected)
    }

    @Test("Pretty-print sorts keys")
    func prettyPrintSortsKeys() {
        let pretty = JSONHelper.prettyPrint(#"{"z":1,"a":2}"#)
        #expect(pretty != nil)
        // a 应该出现在 z 之前
        if let pretty {
            let aPos = pretty.range(of: "\"a\"")?.lowerBound
            let zPos = pretty.range(of: "\"z\"")?.lowerBound
            #expect(aPos != nil && zPos != nil)
            if let a = aPos, let z = zPos { #expect(a < z) }
        }
    }

    @Test("Pretty-print fails on invalid JSON")
    func prettyPrintFails() {
        #expect(JSONHelper.prettyPrint("{invalid") == nil)
    }

    @Test("Pretty-print handles nested arrays")
    func prettyPrintNested() {
        let pretty = JSONHelper.prettyPrint(#"{"arr":[1,[2,3]]}"#)
        #expect(pretty != nil)
        #expect(pretty?.contains("[") == true)
    }

    // MARK: - minify

    @Test("Minify removes whitespace")
    func minifyRemovesWhitespace() {
        let mini = JSONHelper.minify("{\n  \"a\" : 1,\n  \"b\" : 2\n}")
        #expect(mini != nil)
        // Foundation 输出形如 {"a":1,"b":2}
        #expect(mini == #"{"a":1,"b":2}"#)
    }

    @Test("Minify fails on invalid JSON")
    func minifyFails() {
        #expect(JSONHelper.minify("{still invalid") == nil)
    }

    // MARK: - validate

    @Test("Valid JSON → .valid")
    func validateValid() {
        #expect(JSONHelper.validate(#"{"a":1}"#) == .valid)
    }

    @Test("Trailing comma → .valid (Foundation lenient)")
    func validateTrailingComma() {
        // 与 isJSON 行为一致：trailing comma 被 Foundation 接受
        #expect(JSONHelper.validate(#"{"a":1,}"#) == .valid)
    }

    @Test("Unbalanced brace → .invalid")
    func validateUnbalanced() {
        let r = JSONHelper.validate(#"{"a":1"#)
        if case .invalid = r {} else {
            Issue.record("Expected .invalid, got \(r)")
        }
    }

    @Test("Empty string → .invalid")
    func validateEmpty() {
        let r = JSONHelper.validate("")
        if case .invalid = r {} else {
            Issue.record("Expected .invalid, got \(r)")
        }
    }

    // MARK: - stats

    @Test("Stats counts top-level object keys")
    func statsObject() {
        let s = JSONHelper.stats(#"{"a":1,"b":2,"c":3}"#)
        #expect(s.topLevelKeys == 3)
        #expect(s.topLevelItems == -1)
        #expect(s.byteCount == 19)
    }

    @Test("Stats counts top-level array items")
    func statsArray() {
        let s = JSONHelper.stats(#"[1,2,3,4]"#)
        #expect(s.topLevelKeys == -1)
        #expect(s.topLevelItems == 4)
    }

    @Test("Stats on invalid JSON still gives byte count")
    func statsInvalid() {
        let s = JSONHelper.stats("{invalid")
        #expect(s.topLevelKeys == -1)
        #expect(s.topLevelItems == -1)
        #expect(s.byteCount == 8)
    }
}

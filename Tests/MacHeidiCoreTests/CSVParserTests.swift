import Testing
@testable import MacHeidiCore

@Suite("CSVParser")
struct CSVParserTests {

    @Test("Plain comma-separated rows")
    func plain() throws {
        let r = try CSVParser.parse("a,b,c\n1,2,3\n4,5,6")
        #expect(r == [["a","b","c"], ["1","2","3"], ["4","5","6"]])
    }

    @Test("Trailing newline ignored")
    func trailingNewline() throws {
        let r = try CSVParser.parse("a,b\n1,2\n")
        #expect(r == [["a","b"], ["1","2"]])
    }

    @Test("Quoted field with embedded comma")
    func embeddedComma() throws {
        let csv = "a,b,c\n\"hi, world\",2,3"
        let r = try CSVParser.parse(csv)
        #expect(r == [["a","b","c"], ["hi, world","2","3"]])
    }

    @Test("Quoted field with embedded newline")
    func embeddedNewline() throws {
        let csv = "a,b\n\"line1\nline2\",2"
        let r = try CSVParser.parse(csv)
        #expect(r == [["a","b"], ["line1\nline2","2"]])
    }

    @Test("Doubled quote inside quoted field → single quote")
    func doubledQuote() throws {
        let csv = "a,b\n\"he said \"\"hi\"\"\",2"
        let r = try CSVParser.parse(csv)
        #expect(r == [["a","b"], ["he said \"hi\"", "2"]])
    }

    @Test("CRLF line endings")
    func crlf() throws {
        let r = try CSVParser.parse("a,b\r\n1,2\r\n")
        #expect(r == [["a","b"], ["1","2"]])
    }

    @Test("Empty fields preserved")
    func emptyFields() throws {
        let r = try CSVParser.parse("a,b,c\n,,\n1,,3")
        #expect(r == [["a","b","c"], ["","",""], ["1","","3"]])
    }

    @Test("Tab separator")
    func tabSep() throws {
        let r = try CSVParser.parse("a\tb\n1\t2", separator: "\t")
        #expect(r == [["a","b"], ["1","2"]])
    }

    @Test("Unterminated quote throws")
    func unterminated() {
        let csv = "a,b\n\"oops"
        #expect(throws: CSVParser.ParseError.self) {
            _ = try CSVParser.parse(csv)
        }
    }

    @Test("Blank lines filtered")
    func blankLines() throws {
        let r = try CSVParser.parse("a,b\n\n1,2\n\n")
        #expect(r == [["a","b"], ["1","2"]])
    }
}

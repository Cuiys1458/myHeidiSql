import Testing
@testable import MacHeidiCore

@Suite("SQL Splitter S4.2/S4.3")
struct SQLSplitterTests {

    // MARK: Basic

    @Test("Single no-semicolon")
    func singleNoSemicolon() {
        #expect(SQLSplitter.split("SELECT 1") == ["SELECT 1"])
    }

    @Test("Single with semicolon")
    func singleWithSemicolon() {
        #expect(SQLSplitter.split("SELECT 1;") == ["SELECT 1"])
    }

    @Test("Two statements")
    func two() {
        #expect(SQLSplitter.split("SELECT 1; SELECT 2") == ["SELECT 1", "SELECT 2"])
    }

    @Test("Trailing semicolons ignored")
    func trailing() {
        #expect(SQLSplitter.split("SELECT 1;;;") == ["SELECT 1"])
    }

    @Test("Blank lines between statements ignored")
    func blankLines() {
        #expect(SQLSplitter.split("SELECT 1;\n\n\nSELECT 2;") == ["SELECT 1", "SELECT 2"])
    }

    @Test("Whitespace-only input → empty")
    func whitespaceOnly() {
        #expect(SQLSplitter.split("   \n\n  ") == [])
    }

    @Test("Just semicolons → empty")
    func justSemicolons() {
        #expect(SQLSplitter.split(";;;;") == [])
    }

    // MARK: Strings

    @Test("Semicolon inside single-quote does not split")
    func semicolonInsideSingleQuote() {
        let r = SQLSplitter.split("SELECT 'a;b;c'; SELECT 2")
        #expect(r == ["SELECT 'a;b;c'", "SELECT 2"])
    }

    @Test("Semicolon inside double-quote does not split")
    func semicolonInsideDoubleQuote() {
        let r = SQLSplitter.split("SELECT \"a;b\"; SELECT 2")
        #expect(r == ["SELECT \"a;b\"", "SELECT 2"])
    }

    @Test("Semicolon inside backtick does not split")
    func semicolonInsideBacktick() {
        let r = SQLSplitter.split("SELECT * FROM `weird;name`; SELECT 2")
        #expect(r == ["SELECT * FROM `weird;name`", "SELECT 2"])
    }

    @Test("Backslash escape inside single-quote")
    func escapedSingleQuote() {
        let r = SQLSplitter.split("SELECT 'it\\'s ok'; SELECT 2")
        #expect(r == ["SELECT 'it\\'s ok'", "SELECT 2"])
    }

    // MARK: Comments

    @Test("Line comment semicolon ignored")
    func lineCommentSemicolon() {
        // 注释保留在语句里（HeidiSQL 同样行为）；关键是它内部的 `;` 不分裂语句
        let r = SQLSplitter.split("SELECT 1 -- ; comment\n; SELECT 2")
        #expect(r.count == 2)
        #expect(r[0].hasPrefix("SELECT 1"))
        #expect(r[1] == "SELECT 2")
    }

    @Test("Block comment semicolon ignored")
    func blockCommentSemicolon() {
        let r = SQLSplitter.split("SELECT /* ; nope ; */ 1; SELECT 2")
        #expect(r == ["SELECT /* ; nope ; */ 1", "SELECT 2"])
    }

    @Test("Multi-line block comment")
    func multiLineBlockComment() {
        let r = SQLSplitter.split("/* multi\nline\ncomment */ SELECT 1")
        #expect(r == ["/* multi\nline\ncomment */ SELECT 1"])
    }

    // MARK: Classification

    @Test("SELECT-like classification")
    func selectLike() {
        let queries = [
            "SELECT 1",
            "SHOW DATABASES",
            "DESCRIBE x",
            "DESC x",
            "EXPLAIN SELECT 1",
            "WITH cte AS (SELECT 1) SELECT * FROM cte",
            "VALUES (1)",
            "CALL p()"
        ]
        for q in queries {
            #expect(SQLSplitter.classify(q) == .query, "\(q) should be query")
        }
    }

    @Test("DML/DCL/D classification → exec")
    func execLike() {
        let xs = [
            "UPDATE u SET x=1",
            "INSERT INTO u VALUES (1)",
            "DELETE FROM u",
            "CREATE TABLE t (id INT)",
            "DROP TABLE t",
            "TRUNCATE TABLE t",
        ]
        for x in xs {
            #expect(SQLSplitter.classify(x) == .exec, "\(x) should be exec")
        }
    }

    @Test("Leading whitespace/comments don't affect classification")
    func leadingNoiseIgnoredForClassification() {
        #expect(SQLSplitter.classify("  -- a\n  /* block */ SELECT 1") == .query)
    }

    @Test("Classification is case-insensitive")
    func caseInsensitive() {
        #expect(SQLSplitter.classify("select 1") == .query)
        #expect(SQLSplitter.classify("update x set a=1") == .exec)
    }

    // MARK: Cursor

    @Test("Cursor inside first")
    func cursorInsideFirst() {
        #expect(SQLSplitter.statementAtCursor(
            text: "SELECT 1; SELECT 2; SELECT 3",
            offset: 4
        ) == "SELECT 1")
    }

    @Test("Cursor on semicolon returns preceding")
    func cursorOnSemicolon() {
        #expect(SQLSplitter.statementAtCursor(
            text: "SELECT 1; SELECT 2",
            offset: 8
        ) == "SELECT 1")
    }

    @Test("Cursor inside last")
    func cursorInsideLast() {
        #expect(SQLSplitter.statementAtCursor(
            text: "SELECT 1; SELECT 2",
            offset: 15
        ) == "SELECT 2")
    }

    @Test("Cursor in trailing whitespace returns last")
    func cursorAfterEndReturnsLast() {
        #expect(SQLSplitter.statementAtCursor(
            text: "SELECT 1;\n\n",
            offset: 11
        ) == "SELECT 1")
    }
}

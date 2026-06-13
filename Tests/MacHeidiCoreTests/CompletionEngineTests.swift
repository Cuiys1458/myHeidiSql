import Testing
@testable import MacHeidiCore

@Suite("CompletionEngine")
struct CompletionEngineTests {

    private func snap() -> CompletionEngine.SchemaSnapshot {
        CompletionEngine.SchemaSnapshot(
            databases: ["app_prod", "app_test"],
            tables: ["users", "orders", "products"],
            columnsByTable: [
                "users":    ["id", "name", "email", "age"],
                "orders":   ["id", "user_id", "total", "created_at"],
                "products": ["id", "title", "price"]
            ]
        )
    }

    // MARK: token detection

    @Test("Current token at end of word")
    func curTokenEnd() {
        let t = CompletionEngine.currentToken(text: "SELECT use", cursor: 10)
        #expect(t.token == "use")
    }

    @Test("Current token empty when cursor on space")
    func curTokenEmpty() {
        let t = CompletionEngine.currentToken(text: "SELECT ", cursor: 7)
        #expect(t.token.isEmpty)
    }

    @Test("Current token includes dot for qualified")
    func curTokenWithDot() {
        let t = CompletionEngine.currentToken(text: "SELECT users.na", cursor: 15)
        #expect(t.token == "users.na")
    }

    // MARK: context detection

    @Test("After FROM expects tables")
    func afterFrom() {
        let r = CompletionEngine.detectContext(text: "SELECT * FROM ", cursor: 14)
        #expect(r == .afterFrom)
    }

    @Test("After UPDATE expects tables")
    func afterUpdate() {
        let r = CompletionEngine.detectContext(text: "UPDATE ", cursor: 7)
        #expect(r == .afterUpdate)
    }

    @Test("After WHERE expects columns")
    func afterWhere() {
        let r = CompletionEngine.detectContext(text: "SELECT * FROM users WHERE ", cursor: 26)
        #expect(r == .afterWhere)
    }

    @Test("Dot triggers column-of-table")
    func afterDot() {
        let r = CompletionEngine.detectContext(text: "SELECT users.", cursor: 13)
        if case .afterDot(let p) = r { #expect(p == "users") }
        else { Issue.record("expected afterDot, got \(r)") }
    }

    @Test("After ORDER BY expects columns")
    func afterOrderBy() {
        let r = CompletionEngine.detectContext(
            text: "SELECT * FROM users ORDER BY ", cursor: 29
        )
        #expect(r == .afterOrderBy)
    }

    // MARK: ranking

    @Test("Prefix match beats substring match")
    func prefixOrdering() {
        let cands = [
            CompletionEngine.Suggestion(text: "user_id", kind: .column),
            CompletionEngine.Suggestion(text: "users", kind: .table),
            CompletionEngine.Suggestion(text: "name", kind: .column)
        ]
        let r = CompletionEngine.rank(cands, prefix: "use")
        #expect(r.first?.text == "user_id" || r.first?.text == "users")
    }

    @Test("Exact match goes first")
    func exactFirst() {
        let cands = [
            CompletionEngine.Suggestion(text: "users", kind: .table),
            CompletionEngine.Suggestion(text: "user_settings", kind: .table)
        ]
        let r = CompletionEngine.rank(cands, prefix: "users")
        #expect(r.first?.text == "users")
    }

    @Test("Empty prefix returns top entries")
    func emptyPrefix() {
        let cands = [
            CompletionEngine.Suggestion(text: "a", kind: .column),
            CompletionEngine.Suggestion(text: "b", kind: .column)
        ]
        let r = CompletionEngine.rank(cands, prefix: "")
        #expect(r.count == 2)
    }

    // MARK: end-to-end

    @Test("FROM + prefix narrows tables")
    func e2eFromTable() {
        let r = CompletionEngine.suggest(
            text: "SELECT * FROM use",
            cursor: 17,
            schema: snap()
        )
        #expect(r.first?.text == "users")
    }

    @Test("WHERE + prefix narrows columns")
    func e2eWhereColumn() {
        let r = CompletionEngine.suggest(
            text: "SELECT * FROM users WHERE em",
            cursor: 28,
            schema: snap()
        )
        #expect(r.first?.text == "email")
    }

    @Test("users. lists user columns")
    func e2eDotColumn() {
        let r = CompletionEngine.suggest(
            text: "SELECT users.",
            cursor: 13,
            schema: snap()
        )
        let texts = r.map(\.text)
        #expect(texts.contains("id"))
        #expect(texts.contains("name"))
        #expect(texts.contains("email"))
    }
}

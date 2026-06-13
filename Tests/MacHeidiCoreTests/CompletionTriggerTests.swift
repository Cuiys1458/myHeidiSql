import Testing
@testable import MacHeidiCore

@Suite("CompletionTrigger")
struct CompletionTriggerTests {

    // MARK: evaluate

    @Test("Empty text → hide")
    func emptyHides() {
        #expect(CompletionTrigger.evaluate(text: "", cursor: 0) == .hide)
    }

    @Test("Single letter → show")
    func singleLetter() {
        #expect(CompletionTrigger.evaluate(text: "S", cursor: 1) == .show(prefix: "S"))
    }

    @Test("Multi-letter prefix → show with prefix")
    func multiLetter() {
        #expect(CompletionTrigger.evaluate(text: "SEL", cursor: 3) == .show(prefix: "SEL"))
    }

    @Test("After space → hide")
    func afterSpaceHides() {
        #expect(CompletionTrigger.evaluate(text: "SELECT ", cursor: 7) == .hide)
    }

    @Test("After paren → hide")
    func afterParen() {
        #expect(CompletionTrigger.evaluate(text: "COUNT(", cursor: 6) == .hide)
    }

    @Test("Mid-word cursor → show with full token")
    func midWord() {
        let r = CompletionTrigger.evaluate(text: "SELECT users", cursor: 12)
        #expect(r == .show(prefix: "users"))
    }

    @Test("Dot in token → show with full qualified")
    func dotKept() {
        let r = CompletionTrigger.evaluate(text: "SELECT users.na", cursor: 15)
        #expect(r == .show(prefix: "users.na"))
    }

    @Test("Just dot → show empty-ish (so engine lists all columns)")
    func bareDot() {
        let r = CompletionTrigger.evaluate(text: "SELECT users.", cursor: 13)
        #expect(r == .show(prefix: "users."))
    }

    // MARK: applyCompletion

    @Test("Replace single-token prefix")
    func applySimple() {
        let r = CompletionTrigger.applyCompletion(
            text: "SELECT use",
            cursor: 10,
            suggestion: "users"
        )
        #expect(r.text == "SELECT users")
        #expect(r.cursor == 12)
    }

    @Test("Insert when cursor at empty token")
    func applyAtEnd() {
        let r = CompletionTrigger.applyCompletion(
            text: "SELECT ",
            cursor: 7,
            suggestion: "users"
        )
        #expect(r.text == "SELECT users")
        #expect(r.cursor == 12)
    }

    @Test("Replace tail after dot, keep qualifier")
    func applyAfterDot() {
        let r = CompletionTrigger.applyCompletion(
            text: "SELECT users.na",
            cursor: 15,
            suggestion: "name"
        )
        #expect(r.text == "SELECT users.name")
        #expect(r.cursor == 17)
    }

    @Test("Insert column right after dot")
    func applyImmediatelyAfterDot() {
        let r = CompletionTrigger.applyCompletion(
            text: "SELECT users.",
            cursor: 13,
            suggestion: "id"
        )
        #expect(r.text == "SELECT users.id")
        #expect(r.cursor == 15)
    }

    @Test("Preserves suffix after token")
    func preservesSuffix() {
        let r = CompletionTrigger.applyCompletion(
            text: "SELECT use FROM users",
            cursor: 10,                  // cursor on "use"
            suggestion: "user_id"
        )
        #expect(r.text == "SELECT user_id FROM users")
        #expect(r.cursor == 14)
    }
}

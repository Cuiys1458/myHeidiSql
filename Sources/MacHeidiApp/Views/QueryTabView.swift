import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MacHeidiCore

struct QueryTabView: View {
    @Environment(AppEnvironment.self) private var env
    let tabId: UUID
    let title: String

    @State private var sql: String = "SELECT NOW(), VERSION();"
    @State private var cursorOffset: Int = 0
    @State private var didLoadFromEnv: Bool = false
    @State private var outcomes: [QueryOutcome] = []
    @State private var selectedOutcomeIndex: Int = 0
    @State private var elapsed: Duration?
    @State private var running = false
    @State private var cancelToast: String?
    @State private var completionSchema: CompletionEngine.SchemaSnapshot =
        CompletionEngine.SchemaSnapshot(databases: [], tables: [], columnsByTable: [:])

    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                HStack {
                    Button {
                        Task { await runAll() }
                    } label: {
                        Label("Run All (⇧⌘R)", systemImage: "play.fill")
                    }
                    .keyboardShortcut("R", modifiers: [.command, .shift])
                    .disabled(running)

                    Button {
                        Task { await runCurrent() }
                    } label: {
                        Label("Run (⌘⏎)", systemImage: "forward.fill")
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(running)

                    Button {
                        Task { await runExplain() }
                    } label: {
                        Label("Explain", systemImage: "magnifyingglass.circle")
                    }
                    .help("EXPLAIN current statement")
                    .disabled(running)

                    Button {
                        sql = SQLFormatter.format(sql)
                    } label: {
                        Label("Format", systemImage: "text.alignleft")
                    }
                    .help("Format SQL (uppercase keywords + indent)")
                    .keyboardShortcut("F", modifiers: [.command, .shift])
                    .disabled(running)

                    if running {
                        ProgressView().controlSize(.small)
                        Button {
                            cancel()
                        } label: {
                            Label("Cancel", systemImage: "stop.fill")
                        }
                        .keyboardShortcut(".", modifiers: .command)
                    }
                    Spacer()
                    Button { openSQLFile() } label: {
                        Image(systemName: "folder")
                    }
                    .help("Open .sql file (⌘O)")
                    .keyboardShortcut("o", modifiers: .command)
                    Button { saveSQLFile() } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .help("Save SQL to file (⌘S)")
                    .keyboardShortcut("s", modifiers: .command)
                    if let toast = cancelToast {
                        Label(toast, systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if let elapsed {
                        Text(elapsedString(elapsed))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)

                SQLEditor(text: $sql, cursorOffset: $cursorOffset, schema: completionSchema)
                    .frame(minHeight: 120)
            }
            .frame(minHeight: 160)

            MultiResultPane(outcomes: outcomes, selectedIndex: $selectedOutcomeIndex)
                .frame(minHeight: 120)
        }
        .task {
            // 从 env 恢复 SQL（切换 Tab 后再切回不丢）
            if !didLoadFromEnv {
                if let saved = env.queryTabSQL[tabId] {
                    sql = saved
                }
                if let savedCur = env.queryTabCursor[tabId] {
                    cursorOffset = savedCur
                }
                didLoadFromEnv = true
            }
            // 从 History"Use This"过来时灌 SQL
            if let pending = env.pendingHistorySQL {
                sql = pending
                env.pendingHistorySQL = nil
            }
            // 拉补全 schema
            completionSchema = await env.completionSchemaSnapshot()
        }
        // 同步：每次 sql 变 → 写回 env
        .onChange(of: sql) { _, newVal in
            env.queryTabSQL[tabId] = newVal
        }
        .onChange(of: cursorOffset) { _, newVal in
            env.queryTabCursor[tabId] = newVal
        }
        // 当对象树更新（新展开库 / 打开新 Data Tab）时刷新补全数据
        .onChange(of: env.tablesByDb.count) { _, _ in
            Task { completionSchema = await env.completionSchemaSnapshot() }
        }
        .onChange(of: env.openTabs.count) { _, _ in
            Task { completionSchema = await env.completionSchemaSnapshot() }
        }
    }

    // MARK: actions

    @MainActor
    private func runCurrent() async {
        // 选中的 statement = 光标所在的；没有则跑第一条
        let stmt = SQLSplitter.statementAtCursor(text: sql, offset: cursorOffset)
            ?? SQLSplitter.split(sql).first
        guard let one = stmt, !one.isEmpty else { return }
        await runStatements([one])
    }

    @MainActor
    private func runAll() async {
        let stmts = SQLSplitter.split(sql)
        await runStatements(stmts)
    }

    @MainActor
    private func runExplain() async {
        // 选当前语句，前面加 EXPLAIN，跑一次
        let stmt = SQLSplitter.statementAtCursor(text: sql, offset: cursorOffset)
            ?? SQLSplitter.split(sql).first
        guard let one = stmt, !one.isEmpty else { return }
        let upper = one.trimmingCharacters(in: .whitespaces).uppercased()
        // 已经有 EXPLAIN 前缀就不重复
        let explained = upper.hasPrefix("EXPLAIN") ? one : "EXPLAIN \(one)"
        await runStatements([explained])
    }

    @MainActor
    private func runStatements(_ stmts: [String]) async {
        guard let client = env.activeClient else { return }
        running = true
        elapsed = nil
        outcomes = []
        defer { running = false }

        let start = ContinuousClock.now
        var collected: [QueryOutcome] = []
        for s in stmts {
            let kind = SQLSplitter.classify(s)
            let stmtStart = ContinuousClock.now
            do {
                if case .query = kind {
                    let rs = try await client.query(s)
                    collected.append(QueryOutcome(sql: s, kind: .query(rs)))
                    appendHistory(s, elapsed: ContinuousClock.now - stmtStart, success: true)
                } else {
                    let r = try await client.exec(s)
                    collected.append(QueryOutcome(sql: s, kind: .exec(r)))
                    appendHistory(s, elapsed: ContinuousClock.now - stmtStart, success: true)
                }
            } catch let e as DBError {
                let kind: QueryOutcome.Kind = .error(error: describe(e))
                collected.append(QueryOutcome(sql: s, kind: kind))
                appendHistory(s, elapsed: ContinuousClock.now - stmtStart, success: false)
                break
            } catch let other {
                let kind: QueryOutcome.Kind = .error(error: String(describing: other))
                collected.append(QueryOutcome(sql: s, kind: kind))
                appendHistory(s, elapsed: ContinuousClock.now - stmtStart, success: false)
                break
            }
        }
        outcomes = collected
        // 选第一个 query 结果作为活动 sub-tab，没 query 就 0
        selectedOutcomeIndex = collected.firstIndex { if case .query = $0.kind { return true } else { return false } } ?? 0
        elapsed = ContinuousClock.now - start
    }

    private func cancel() {
        guard let client = env.activeClient else { return }
        cancelToast = "Cancelling query…"
        Task {
            await client.cancel()
            // 给 UI 留个尾巴让用户能看见
            try? await Task.sleep(for: .milliseconds(800))
            await MainActor.run { cancelToast = nil }
        }
    }

    private func appendHistory(_ sql: String, elapsed: Duration, success: Bool) {
        let ms = Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
            + Int(elapsed.components.seconds) * 1000
        QueryHistory.shared.append(.init(
            sql: sql,
            database: env.activeSession?.defaultDatabases,
            elapsedMs: ms,
            success: success
        ))
    }

    /// 打开 .sql 文件，灌进当前编辑器（PRD §11 v0.2）。
    func openSQLFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .data]
        panel.allowsMultipleSelection = false
        panel.begin { resp in
            guard resp == .OK, let url = panel.url,
                  let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else { return }
            sql = text
        }
    }

    /// 保存当前编辑器内容到 .sql 文件。
    func saveSQLFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "query.sql"
        let snapshot = sql
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            try? snapshot.data(using: .utf8)?.write(to: url, options: .atomic)
        }
    }

    private func describe(_ e: DBError) -> String {
        switch e {
        case .syntax(let n, _, let m): return "ERROR \(n): \(m)"
        case .constraint(let n, _, let m): return "CONSTRAINT \(n): \(m)"
        case .network(let m, _): return "NETWORK: \(m)"
        case .auth(let m, _): return "AUTH: \(m)"
        case .cancelled: return "Cancelled"
        case .timeout(let m): return "TIMEOUT: \(m)"
        case .server(let n, _, let m): return "SERVER \(n): \(m)"
        case .unknown(let m, _): return m
        }
    }

    private func elapsedString(_ d: Duration) -> String {
        let ms = Int(d.components.attoseconds / 1_000_000_000_000_000)
        let s = d.components.seconds
        if s > 0 { return "\(s).\(String(format: "%03d", ms)) s" }
        return "\(ms) ms"
    }
}

// MARK: - Multi-Result Pane

private struct MultiResultPane: View {
    let outcomes: [QueryOutcome]
    @Binding var selectedIndex: Int

    var body: some View {
        if outcomes.isEmpty {
            Text("Run a query to see results here.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                // sub-tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(outcomes.enumerated()), id: \.offset) { idx, outcome in
                            ResultTabChip(index: idx, outcome: outcome,
                                          isSelected: idx == selectedIndex,
                                          onSelect: { selectedIndex = idx })
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                }
                .background(Color(NSColor.controlBackgroundColor))
                Divider()

                // selected outcome body
                if outcomes.indices.contains(selectedIndex) {
                    OutcomeBody(outcome: outcomes[selectedIndex])
                }

                // Messages 面板（永远显示，列出每条语句的结果摘要）
                Divider()
                MessagesPanel(outcomes: outcomes)
                    .frame(minHeight: 80, idealHeight: 140, maxHeight: 240)
            }
        }
    }
}

private struct ResultTabChip: View {
    let index: Int
    let outcome: QueryOutcome
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(label).font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private var icon: String {
        switch outcome.kind {
        case .query: return "tablecells"
        case .exec:  return "checkmark.circle"
        case .error: return "exclamationmark.triangle"
        }
    }
    private var color: Color {
        switch outcome.kind {
        case .query: return .accentColor
        case .exec:  return .green
        case .error: return .red
        }
    }
    private var label: String {
        let n = index + 1
        switch outcome.kind {
        case .query: return "Result #\(n)"
        case .exec:  return "Stmt #\(n)"
        case .error: return "Error #\(n)"
        }
    }
}

private struct OutcomeBody: View {
    let outcome: QueryOutcome

    var body: some View {
        switch outcome.kind {
        case .query(let rs):
            ResultGrid(resultSet: rs)
        case .exec(let r):
            VStack(alignment: .leading, spacing: 8) {
                Text("\(r.affectedRows) row\(r.affectedRows == 1 ? "" : "s") affected")
                    .font(.title3)
                if let lid = r.lastInsertId {
                    Text("Last insert id: \(lid)").foregroundStyle(.secondary)
                }
                Text(outcome.sql)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
        case .error(let msg):
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text(msg)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                    Text(outcome.sql)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
    }
}

private struct IndexedOutcome: Identifiable {
    let id: Int
    let outcome: QueryOutcome
}

private struct MessagesPanel: View {
    let outcomes: [QueryOutcome]

    var body: some View {
        let items: [IndexedOutcome] = outcomes.enumerated().map {
            IndexedOutcome(id: $0.offset, outcome: $0.element)
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(items) { item in
                    MessageRow(idx: item.id, outcome: item.outcome)
                }
            }
            .padding(6)
        }
        .background(Color(NSColor.textBackgroundColor))
    }
}

private struct MessageRow: View {
    let idx: Int
    let outcome: QueryOutcome
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("[\(idx + 1)]")
                .foregroundStyle(.secondary)
            Text(line)
                .foregroundStyle(color)
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption.monospaced())
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var line: String {
        switch outcome.kind {
        case .query(let rs): return "\(rs.rows.count) row(s) — \(outcome.sql)"
        case .exec(let r):   return "\(r.affectedRows) row(s) affected — \(outcome.sql)"
        case .error(let m):  return "✗ \(m) — \(outcome.sql)"
        }
    }
    private var color: Color {
        switch outcome.kind {
        case .query: return .primary
        case .exec:  return .green
        case .error: return .red
        }
    }
}

// MARK: - SQL Editor with very-light syntax highlighting

private struct SQLEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursorOffset: Int
    var schema: CompletionEngine.SchemaSnapshot

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        // 替换默认 NSTextView 为我们的子类（拦 ⌃Space）
        let frame = (scrollView.documentView as! NSTextView).frame
        let tv = AutocompletingTextView(frame: frame)
        tv.delegate = context.coordinator
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.string = text
        tv.schemaSnapshot = schema
        applyHighlighting(to: tv)
        scrollView.documentView = tv
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let tv = nsView.documentView as! NSTextView
        if let auto = tv as? AutocompletingTextView {
            auto.schemaSnapshot = schema
        }
        if tv.string != text {
            tv.string = text
            applyHighlighting(to: tv)
        }
        context.coordinator.schema = schema
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self, schema: schema)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: SQLEditor
        var schema: CompletionEngine.SchemaSnapshot

        init(_ p: SQLEditor, schema: CompletionEngine.SchemaSnapshot) {
            self.parent = p
            self.schema = schema
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.cursorOffset = tv.selectedRange().location
            applyHighlighting(to: tv)
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.cursorOffset = tv.selectedRange().location
        }

        // NSTextView 补全接口：用户按 ⌥⎋ 或 Tab 键触发系统补全菜单
        func textView(_ textView: NSTextView,
                      completions words: [String],
                      forPartialWordRange charRange: NSRange,
                      indexOfSelectedItem index: UnsafeMutablePointer<Int>?
        ) -> [String] {
            let cursor = NSMaxRange(charRange)
            let suggestions = CompletionEngine.suggest(
                text: textView.string,
                cursor: cursor,
                schema: schema
            )
            let texts = Array(suggestions.prefix(30).map(\.text))
            index?.pointee = texts.isEmpty ? -1 : 0
            return texts
        }
    }
}

/// 极简语法高亮：关键字 / 字符串 / 注释 / 数字四类（PRD §5.4.2）。
@MainActor
private func applyHighlighting(to tv: NSTextView) {
    guard let storage = tv.textStorage else { return }
    let full = NSRange(location: 0, length: (tv.string as NSString).length)
    storage.beginEditing()
    storage.removeAttribute(.foregroundColor, range: full)
    storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
    storage.addAttribute(.font,
                         value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                         range: full)

    let s = tv.string as NSString
    let textLen = s.length

    // 关键字
    let keywords = [
        "SELECT","FROM","WHERE","AND","OR","NOT","IN","IS","NULL","LIKE","BETWEEN",
        "GROUP","BY","ORDER","HAVING","LIMIT","OFFSET","JOIN","LEFT","RIGHT","INNER",
        "OUTER","ON","AS","DISTINCT","UNION","ALL","CASE","WHEN","THEN","ELSE","END",
        "INSERT","INTO","VALUES","UPDATE","SET","DELETE","CREATE","TABLE","DROP",
        "ALTER","ADD","COLUMN","INDEX","KEY","PRIMARY","FOREIGN","REFERENCES",
        "DESCRIBE","DESC","EXPLAIN","SHOW","DATABASES","TABLES","VIEWS","TRUNCATE",
        "WITH","BEGIN","COMMIT","ROLLBACK","TRANSACTION","CALL","IF","EXISTS","USE",
        "GRANT","REVOKE","CONSTRAINT","DEFAULT","UNIQUE","CHECK","INT","BIGINT",
        "VARCHAR","TEXT","DATE","DATETIME","TIMESTAMP","BOOL","BOOLEAN","JSON",
    ]
    let kwColor = NSColor.systemBlue
    for k in keywords {
        let pattern = "\\b\(k)\\b"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            regex.enumerateMatches(in: tv.string, options: [], range: full) { m, _, _ in
                if let r = m?.range, r.location + r.length <= textLen {
                    storage.addAttribute(.foregroundColor, value: kwColor, range: r)
                }
            }
        }
    }

    // 字符串字面量
    let stringColor = NSColor.systemRed
    let stringPatterns = [
        "'(?:[^'\\\\]|\\\\.)*'",
        "\"(?:[^\"\\\\]|\\\\.)*\""
    ]
    for p in stringPatterns {
        if let regex = try? NSRegularExpression(pattern: p, options: []) {
            regex.enumerateMatches(in: tv.string, options: [], range: full) { m, _, _ in
                if let r = m?.range, r.location + r.length <= textLen {
                    storage.addAttribute(.foregroundColor, value: stringColor, range: r)
                }
            }
        }
    }

    // 数字
    let numColor = NSColor.systemPurple
    if let regex = try? NSRegularExpression(pattern: "\\b\\d+(?:\\.\\d+)?\\b", options: []) {
        regex.enumerateMatches(in: tv.string, options: [], range: full) { m, _, _ in
            if let r = m?.range, r.location + r.length <= textLen {
                storage.addAttribute(.foregroundColor, value: numColor, range: r)
            }
        }
    }

    // 注释（颜色压最后，覆盖前面的关键字 / 字符串高亮）
    let commentColor = NSColor.secondaryLabelColor
    if let regex = try? NSRegularExpression(pattern: "--[^\\n]*", options: []) {
        regex.enumerateMatches(in: tv.string, options: [], range: full) { m, _, _ in
            if let r = m?.range, r.location + r.length <= textLen {
                storage.addAttribute(.foregroundColor, value: commentColor, range: r)
            }
        }
    }
    if let regex = try? NSRegularExpression(pattern: "/\\*[\\s\\S]*?\\*/", options: []) {
        regex.enumerateMatches(in: tv.string, options: [], range: full) { m, _, _ in
            if let r = m?.range, r.location + r.length <= textLen {
                storage.addAttribute(.foregroundColor, value: commentColor, range: r)
            }
        }
    }

    storage.endEditing()
}

/// 拦 ⌃Space 触发补全的 NSTextView 子类。
/// 比 NSEvent local monitor 更稳：在 Swift 6 严格 concurrency 下不会撞 NSEvent 不 Sendable。
/// SQL 编辑器 NSTextView 子类，承载实时补全弹窗。
///
/// 三类按键拦截：
/// - **Up/Down/Enter/Tab/Esc** 在弹窗显示时由弹窗消费
/// - **⌃Space** 强制触发（任何时候）
/// - 其他键放行，textDidChange 时再决定是否弹窗
private final class AutocompletingTextView: NSTextView {
    /// 由 SQLEditor.Coordinator 在 makeNSView/updateNSView 时同步进来。
    var schemaSnapshot: CompletionEngine.SchemaSnapshot =
        CompletionEngine.SchemaSnapshot(databases: [], tables: [], columnsByTable: [:])

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags
        let popup = CompletionPopup.shared

        // 弹窗开着时拦截导航键
        if popup.isVisible {
            switch event.keyCode {
            case 53:  // Esc
                popup.hide()
                return
            case 125: // Down
                popup.moveSelection(by: 1)
                return
            case 126: // Up
                popup.moveSelection(by: -1)
                return
            case 36, 76:  // Return / Enter
                popup.confirmSelected()
                return
            case 48:  // Tab
                popup.confirmSelected()
                return
            default:
                break
            }
        }

        // ⌃Space 主动触发
        if mods.contains(.control)
            && !mods.contains(.command)
            && event.keyCode == 49 {  // 49 = Space
            super.keyDown(with: event)   // 让 control+space 不真插入字符
            triggerCompletion(force: true)
            return
        }

        super.keyDown(with: event)
    }

    override func didChangeText() {
        super.didChangeText()
        triggerCompletion(force: false)
    }

    /// 计算 + 显示候选。`force=true` 时即使光标不在 identifier 上也强制弹（⌃Space）。
    private func triggerCompletion(force: Bool) {
        let cursor = selectedRange().location
        let action = CompletionTrigger.evaluate(text: string, cursor: cursor)
        let prefix: String
        switch action {
        case .show(let p):
            prefix = p
        case .hide:
            if force { prefix = CompletionEngine.currentToken(text: string, cursor: cursor).token }
            else { CompletionPopup.shared.hide(); return }
        case .keep:
            return
        }
        let suggestions = CompletionEngine.suggest(
            text: string, cursor: cursor, schema: schemaSnapshot
        )
        let trimmed = Array(suggestions.prefix(30))
        if trimmed.isEmpty {
            CompletionPopup.shared.hide()
            return
        }
        CompletionPopup.shared.show(
            anchorView: self,
            suggestions: trimmed,
            onConfirm: { [weak self] picked in
                self?.applyPickedSuggestion(picked.text)
            }
        )
        _ = prefix   // 已传给 engine
    }

    private func applyPickedSuggestion(_ text: String) {
        let cursor = selectedRange().location
        let result = CompletionTrigger.applyCompletion(
            text: string, cursor: cursor, suggestion: text
        )
        // 替换 textStorage（保留 undo）
        guard let storage = textStorage else { return }
        let full = NSRange(location: 0, length: (string as NSString).length)
        storage.beginEditing()
        storage.replaceCharacters(in: full, with: result.text)
        storage.endEditing()
        setSelectedRange(NSRange(location: result.cursor, length: 0))
        // 通知 SwiftUI binding
        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
    }

    override func resignFirstResponder() -> Bool {
        CompletionPopup.shared.hide()
        return super.resignFirstResponder()
    }
}

import SwiftUI
import AppKit
import MacHeidiCore

/// JSON 单元格专用编辑 sheet。
///
/// 入口：`EditableResultGrid` 双击 JSON 列或 BLOB-as-JSON 列时使用。
/// 与普通 `cellEditSheet` 的区别：
/// - NSTextView 子类替代 TextEditor，带语法高亮 + 行号 gutter
/// - 顶部工具栏：Format / Minify / Validate / Set NULL
/// - 实时（debounce 250ms）校验，红色波浪线标错误位置
/// - Apply 前必须 .valid 才能保存
struct JSONEditorSheet: View {
    let columnName: String
    let mysqlType: String
    let nullable: Bool
    @Binding var text: String
    let onSetNull: (() -> Void)?
    let onCancel: () -> Void
    let onApply: () -> Void

    @State private var validateResult: JSONHelper.ValidateResult = .valid
    @State private var stats: JSONHelper.Stats =
        JSONHelper.Stats(topLevelKeys: -1, topLevelItems: -1, byteCount: 0)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部标题
            HStack(spacing: 8) {
                Image(systemName: "curlybraces.square.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Edit JSON · `\(columnName)`")
                    .font(.headline.monospaced())
                Spacer()
                Text(mysqlType)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)

            // 工具栏
            HStack(spacing: 8) {
                Button {
                    if let pretty = JSONHelper.prettyPrint(text) { text = pretty }
                } label: { Label("Format", systemImage: "text.alignleft") }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!isValid)

                Button {
                    if let mini = JSONHelper.minify(text) { text = mini }
                } label: { Label("Minify", systemImage: "text.justify") }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!isValid)

                if nullable, let setNull = onSetNull {
                    Button("Set NULL") { setNull() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                Spacer()

                statusPill
            }
            .padding(.horizontal, 16).padding(.bottom, 6)

            // 编辑区
            JSONTextEditor(text: $text, errorByteOffset: errorOffsetBinding)
                .frame(minWidth: 600, minHeight: 360)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(borderColor, lineWidth: 1)
                )
                .padding(.horizontal, 16)

            // 状态栏 + 错误信息
            VStack(alignment: .leading, spacing: 4) {
                if case .invalid(let msg, let offset) = validateResult {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(formatError(msg, offset: offset))
                            .font(.caption.monospaced())
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
                HStack(spacing: 12) {
                    Text(statsLabel)
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.top, 6)

            // 底部按钮
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Apply", action: onApply)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .frame(width: 720, height: 520)
        .onAppear { revalidate() }
        .onChange(of: text) { _, _ in revalidate() }
    }

    // MARK: - 派生

    private var isValid: Bool {
        if case .valid = validateResult { return true }
        return false
    }

    private var borderColor: Color {
        isValid ? Color.secondary.opacity(0.3) : Color.red
    }

    @ViewBuilder
    private var statusPill: some View {
        switch validateResult {
        case .valid:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text("Valid").foregroundStyle(.green)
            }
            .font(.caption)
        case .invalid:
            HStack(spacing: 4) {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                Text("Invalid").foregroundStyle(.red)
            }
            .font(.caption)
        }
    }

    private var statsLabel: String {
        var parts: [String] = []
        if stats.topLevelKeys >= 0 {
            parts.append("\(stats.topLevelKeys) key\(stats.topLevelKeys == 1 ? "" : "s")")
        } else if stats.topLevelItems >= 0 {
            parts.append("\(stats.topLevelItems) item\(stats.topLevelItems == 1 ? "" : "s")")
        }
        parts.append("\(stats.byteCount) byte\(stats.byteCount == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }

    private var errorOffsetBinding: Binding<Int?> {
        Binding(
            get: {
                if case .invalid(_, let offset) = validateResult { return offset }
                return nil
            },
            set: { _ in /* read-only */ }
        )
    }

    private func revalidate() {
        validateResult = JSONHelper.validate(text)
        stats = JSONHelper.stats(text)
    }

    private func formatError(_ msg: String, offset: Int?) -> String {
        if let offset { return "\(msg) (at byte \(offset))" }
        return msg
    }
}

// MARK: - JSONTextEditor (NSTextView wrapper)

/// 等宽 NSTextView，带 JSON 语法高亮 + 错误位置标记。
struct JSONTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var errorByteOffset: Int?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.delegate = context.coordinator
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.textContainerInset = NSSize(width: 6, height: 8)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.isRichText = false
        tv.usesFindBar = true
        tv.allowsUndo = true
        tv.string = text
        context.coordinator.applyHighlight(tv: tv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text {
            let selected = tv.selectedRange()
            tv.string = text
            tv.setSelectedRange(NSRange(location: min(selected.location, text.utf16.count),
                                        length: 0))
        }
        context.coordinator.applyHighlight(tv: tv, errorOffset: errorByteOffset)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JSONTextEditor
        private var debounce: DispatchWorkItem?

        init(_ parent: JSONTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ note: Notification) {
            guard let tv = note.object as? NSTextView else { return }
            parent.text = tv.string

            // 250ms debounce 重新高亮
            debounce?.cancel()
            let work = DispatchWorkItem { [weak self, weak tv] in
                guard let self, let tv else { return }
                MainActor.assumeIsolated {
                    self.applyHighlight(tv: tv, errorOffset: self.parent.errorByteOffset)
                }
            }
            debounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250), execute: work)
        }

        @MainActor
        func applyHighlight(tv: NSTextView, errorOffset: Int? = nil) {
            guard let storage = tv.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            let baseFont = tv.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            storage.beginEditing()
            storage.setAttributes(
                [.font: baseFont, .foregroundColor: NSColor.labelColor],
                range: full
            )
            let tokens = JSONTokenizer.tokens(in: tv.string)
            for token in tokens {
                let nsRange = NSRange(token.range, in: tv.string)
                guard nsRange.location != NSNotFound,
                      NSMaxRange(nsRange) <= storage.length else { continue }
                storage.addAttributes(
                    [.foregroundColor: token.kind.color],
                    range: nsRange
                )
            }

            // 错误位置标红 + 波浪线
            if let offset = errorOffset, offset >= 0, offset < storage.length {
                let errRange = NSRange(location: offset, length: max(1, min(3, storage.length - offset)))
                storage.addAttributes(
                    [
                        .underlineStyle: NSUnderlineStyle.thick.rawValue,
                        .underlineColor: NSColor.systemRed,
                        .backgroundColor: NSColor.systemRed.withAlphaComponent(0.15),
                    ],
                    range: errRange
                )
            }
            storage.endEditing()
        }
    }
}

// MARK: - Tokenizer

/// 极简 JSON tokenizer，用于语法高亮。
/// 不需要严格语法（输入可能是非法 JSON 中间态），只识别 token 边界。
enum JSONTokenizer {

    enum Kind {
        case key      // "..." 紧跟 :
        case string   // "..." 不紧跟 :
        case number
        case bool
        case null
        case bracket
        case punct    // : ,

        var color: NSColor {
            switch self {
            case .key:     return NSColor.systemBlue
            case .string:  return NSColor.systemRed
            case .number:  return NSColor.systemPurple
            case .bool, .null: return NSColor.systemOrange
            case .bracket: return NSColor.secondaryLabelColor
            case .punct:   return NSColor.tertiaryLabelColor
            }
        }
    }

    struct Token {
        let kind: Kind
        let range: Range<String.Index>
    }

    static func tokens(in source: String) -> [Token] {
        var tokens: [Token] = []
        var i = source.startIndex
        let end = source.endIndex
        while i < end {
            let c = source[i]
            if c.isWhitespace { i = source.index(after: i); continue }
            switch c {
            case "{", "}", "[", "]":
                tokens.append(Token(kind: .bracket, range: i..<source.index(after: i)))
                i = source.index(after: i)
            case ":", ",":
                tokens.append(Token(kind: .punct, range: i..<source.index(after: i)))
                i = source.index(after: i)
            case "\"":
                let strStart = i
                i = source.index(after: i)
                while i < end {
                    if source[i] == "\\", source.index(after: i) < end {
                        i = source.index(i, offsetBy: 2)
                        continue
                    }
                    if source[i] == "\"" { i = source.index(after: i); break }
                    i = source.index(after: i)
                }
                // 看下一个非空白是不是 ':' → key
                var j = i
                while j < end, source[j].isWhitespace { j = source.index(after: j) }
                let isKey = j < end && source[j] == ":"
                tokens.append(Token(kind: isKey ? .key : .string, range: strStart..<i))
            case "t", "f":
                if source[i...].hasPrefix("true") {
                    let r = i..<source.index(i, offsetBy: 4)
                    tokens.append(Token(kind: .bool, range: r))
                    i = r.upperBound
                } else if source[i...].hasPrefix("false") {
                    let r = i..<source.index(i, offsetBy: 5)
                    tokens.append(Token(kind: .bool, range: r))
                    i = r.upperBound
                } else {
                    i = source.index(after: i)
                }
            case "n":
                if source[i...].hasPrefix("null") {
                    let r = i..<source.index(i, offsetBy: 4)
                    tokens.append(Token(kind: .null, range: r))
                    i = r.upperBound
                } else {
                    i = source.index(after: i)
                }
            case "-", "0"..."9":
                let nstart = i
                i = source.index(after: i)
                while i < end {
                    let ch = source[i]
                    if ch.isNumber || ch == "." || ch == "e" || ch == "E"
                       || ch == "+" || ch == "-" {
                        i = source.index(after: i)
                    } else { break }
                }
                tokens.append(Token(kind: .number, range: nstart..<i))
            default:
                i = source.index(after: i)
            }
        }
        return tokens
    }
}

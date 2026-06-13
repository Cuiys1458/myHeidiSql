import AppKit
import MacHeidiCore

/// 实时补全弹窗（IDE 风格）。
///
/// 关键设计：
/// 1. 是 NSPanel，非 NSWindow → 不抢主窗口 firstResponder，文本框继续接收输入
/// 2. 用 NSTableView 渲染候选 → 高性能 + 内置 selection
/// 3. 上下键 / Enter / Tab / Esc 由 textView 自己拦截后调本类的 select/confirm/dismiss
/// 4. 输入新字符时 textView 调 update(prefix:) 刷新候选；空匹配自动 hide
@MainActor
final class CompletionPopup {

    static let shared = CompletionPopup()

    // MARK: state

    private var panel: NSPanel?
    private var tableView: NSTableView?
    private var dataSource: DataSource?    // 必须强引用，NSTableView.dataSource 是 weak
    private var delegateImpl: Delegate?    // 同上
    private var suggestions: [CompletionEngine.Suggestion] = []
    private weak var anchorTextView: NSTextView?
    private var onConfirm: ((CompletionEngine.Suggestion) -> Void)?

    var isVisible: Bool { panel?.isVisible == true }

    // MARK: API

    /// 显示或更新弹窗。
    func show(
        anchorView: NSTextView,
        suggestions: [CompletionEngine.Suggestion],
        onConfirm: @escaping (CompletionEngine.Suggestion) -> Void
    ) {
        guard !suggestions.isEmpty else { hide(); return }
        self.suggestions = suggestions
        self.anchorTextView = anchorView
        self.onConfirm = onConfirm
        if panel == nil { buildPanel() }
        guard let panel = panel, let tv = tableView else { return }
        tv.reloadData()
        if !suggestions.isEmpty {
            tv.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tv.scrollRowToVisible(0)
        }
        positionPanel(below: anchorView)
        if !panel.isVisible {
            panel.orderFront(nil)
        }
    }

    func hide() {
        panel?.orderOut(nil)
        suggestions = []
        onConfirm = nil
    }

    func moveSelection(by delta: Int) {
        guard let tv = tableView, !suggestions.isEmpty else { return }
        let cur = tv.selectedRow >= 0 ? tv.selectedRow : 0
        let next = max(0, min(suggestions.count - 1, cur + delta))
        tv.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tv.scrollRowToVisible(next)
    }

    func confirmSelected() {
        guard let tv = tableView, tv.selectedRow >= 0,
              tv.selectedRow < suggestions.count else { return }
        let pick = suggestions[tv.selectedRow]
        onConfirm?(pick)
        hide()
    }

    // MARK: internals

    private func buildPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.hasShadow = true
        p.isFloatingPanel = true
        p.level = .popUpMenu
        p.becomesKeyOnlyIfNeeded = true
        p.hidesOnDeactivate = true
        p.backgroundColor = .clear

        let tv = NSTableView()
        tv.headerView = nil
        tv.allowsMultipleSelection = false
        tv.gridStyleMask = []
        tv.intercellSpacing = NSSize(width: 0, height: 0)
        tv.rowHeight = 22
        tv.style = .plain
        tv.selectionHighlightStyle = .regular
        tv.target = self
        tv.action = #selector(handleClick(_:))
        tv.doubleAction = #selector(handleDoubleClick(_:))
        let ds = DataSource(owner: self)
        let dg = Delegate(owner: self)
        tv.dataSource = ds
        tv.delegate = dg
        self.dataSource = ds
        self.delegateImpl = dg

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("CompletionCol"))
        col.title = ""
        col.width = 320
        col.minWidth = 200
        tv.addTableColumn(col)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = tv
        scroll.borderType = .lineBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(name: nil) { trait in
            trait.name == .darkAqua
                ? NSColor.windowBackgroundColor.withAlphaComponent(0.95)
                : NSColor.windowBackgroundColor.withAlphaComponent(0.98)
        }

        p.contentView = scroll
        self.panel = p
        self.tableView = tv
    }

    private func positionPanel(below anchor: NSTextView) {
        guard let panel = panel,
              let lm = anchor.layoutManager,
              let tc = anchor.textContainer,
              let window = anchor.window else { return }
        let cursor = anchor.selectedRange().location
        let glyphIdx = lm.glyphIndexForCharacter(at: max(cursor - 1, 0))
        var caretRect = lm.boundingRect(
            forGlyphRange: NSRange(location: glyphIdx, length: 1),
            in: tc
        )
        // textView 的 textContainerOrigin 偏移
        caretRect.origin.x += anchor.textContainerOrigin.x
        caretRect.origin.y += anchor.textContainerOrigin.y
        // textView 自身坐标 → 屏幕坐标
        let inWindow = anchor.convert(caretRect, to: nil)
        let inScreen = window.convertToScreen(inWindow)
        // 弹窗放在光标行下方
        let height = panel.frame.height
        let panelOrigin = NSPoint(
            x: inScreen.origin.x,
            y: inScreen.origin.y - height - 4    // y 向下：屏幕坐标减
        )
        panel.setFrameOrigin(panelOrigin)
        panel.setContentSize(NSSize(width: 360, height: min(220, CGFloat(suggestions.count) * 22 + 4)))
    }

    @objc private func handleClick(_ sender: AnyObject?) {
        // 单击只选中，不确认（双击才确认）
    }

    @objc private func handleDoubleClick(_ sender: AnyObject?) {
        confirmSelected()
    }

    // MARK: data source / delegate

    private final class DataSource: NSObject, NSTableViewDataSource {
        weak var owner: CompletionPopup?
        init(owner: CompletionPopup) { self.owner = owner }
        func numberOfRows(in tableView: NSTableView) -> Int {
            owner?.suggestions.count ?? 0
        }
    }

    private final class Delegate: NSObject, NSTableViewDelegate {
        weak var owner: CompletionPopup?
        init(owner: CompletionPopup) { self.owner = owner }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                       row: Int) -> NSView? {
            guard let owner = owner, row < owner.suggestions.count else { return nil }
            let s = owner.suggestions[row]
            let id = NSUserInterfaceItemIdentifier("Cell")
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? CompletionCell)
                ?? CompletionCell()
            cell.identifier = id
            cell.configure(s)
            return cell
        }
    }
}

// MARK: - cell

private final class CompletionCell: NSTableCellView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        addSubview(icon); addSubview(label); addSubview(detail)
        icon.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        detail.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        label.lineBreakMode = .byTruncatingTail
        detail.font = NSFont.systemFont(ofSize: 10)
        detail.textColor = .tertiaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        icon.imageScaling = .scaleProportionallyDown
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            detail.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 8),
            detail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            detail.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ s: CompletionEngine.Suggestion) {
        label.stringValue = s.text
        detail.stringValue = s.kind.rawValue
        switch s.kind {
        case .keyword:
            icon.image = NSImage(systemSymbolName: "k.square.fill", accessibilityDescription: nil)
            icon.contentTintColor = .systemBlue
        case .table:
            icon.image = NSImage(systemSymbolName: "tablecells", accessibilityDescription: nil)
            icon.contentTintColor = .systemTeal
        case .column:
            icon.image = NSImage(systemSymbolName: "circle.grid.cross", accessibilityDescription: nil)
            icon.contentTintColor = .systemPurple
        case .database:
            icon.image = NSImage(systemSymbolName: "cylinder", accessibilityDescription: nil)
            icon.contentTintColor = .systemGreen
        case .function:
            icon.image = NSImage(systemSymbolName: "function", accessibilityDescription: nil)
            icon.contentTintColor = .systemOrange
        }
    }
}

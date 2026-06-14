import SwiftUI
import AppKit
import MacHeidiCore

/// 高性能版数据网格 —— 完全用 NSTableView 渲染，编辑通过弹窗。
///
/// 性能：百万行也不卡（NSTableView 视图复用）。
/// 编辑：双击单元格 → 弹出独立编辑窗，不阻塞表格滚动。
struct EditableResultGrid: View {
    @Bindable var vm: DataTabViewModel
    @State private var editingTarget: EditTarget?
    @State private var editText: String = ""
    @State private var editError: String?

    enum EditTarget: Identifiable {
        case existing(rowIdx: Int, columnIndex: Int)
        case insert(localId: UUID, columnIndex: Int)
        var id: String {
            switch self {
            case .existing(let r, let c): return "e-\(r)-\(c)"
            case .insert(let id, let c):  return "i-\(id)-\(c)"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NativeGridRepresentable(vm: vm) { rowIdx, colIdx in
                guard let cols = vm.resultSet?.columns,
                      colIdx >= 0, colIdx < cols.count else { return }
                let col = cols[colIdx]
                let original = vm.resultSet?.rows[rowIdx][colIdx] ?? .null
                let displayed = vm.newValue(rowIdx: rowIdx, column: col.name) ?? original
                editText = cellString(displayed)
                editError = nil
                editingTarget = .existing(rowIdx: rowIdx, columnIndex: colIdx)
            }

            // 行操作工具条（替代右键 → 因为 NSTableView 右键已用作 mark delete）
            insertBar
            footer
        }
        .sheet(item: $editingTarget) { target in
            cellEditSheet(for: target)
        }
    }

    @ViewBuilder
    private var insertBar: some View {
        HStack(spacing: 8) {
            Button {
                let id = vm.addInsertRow()
                if let firstCol = vm.resultSet?.columns
                    .firstIndex(where: { !$0.isAutoIncrement }) {
                    editText = ""
                    editError = nil
                    editingTarget = .insert(localId: id, columnIndex: firstCol)
                }
            } label: {
                Label("Insert Row", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)

            if !vm.pending.pendingInserts.isEmpty {
                Text("\(vm.pending.pendingInserts.count) pending insert(s) — fill cells via the panel below")
                    .font(.caption).foregroundStyle(.orange)
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(.bar)
    }

    @ViewBuilder
    private var footer: some View {
        Divider()
        HStack(spacing: 12) {
            Text("\(vm.resultSet?.rows.count ?? 0) row\((vm.resultSet?.rows.count ?? 0) == 1 ? "" : "s")")
            if let total = vm.totalRows { Text("/ \(total) total") }
            if vm.schema?.hasPrimaryKey == false {
                Label("No PK", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("This table has no primary key.")
            }
            Spacer()
            if let err = vm.commitError {
                Text(err).foregroundStyle(.red).lineLimit(1).help(err)
                    .textSelection(.enabled)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(.bar)
    }

    @ViewBuilder
    private func cellEditSheet(for target: EditTarget) -> some View {
        let col = currentColumn(for: target)
        // JSON-flavored 单元格走专用编辑器
        if let col = col, isJSONFlavored(col: col, target: target) {
            JSONEditorSheet(
                columnName: col.name,
                mysqlType: col.mysqlType,
                nullable: col.nullable,
                text: $editText,
                onSetNull: col.nullable ? {
                    commitEdit(target: target, parsed: .null, column: col)
                } : nil,
                onCancel: { editingTarget = nil },
                onApply: {
                    do {
                        let parsed: CellValue
                        if editText.isEmpty && col.nullable {
                            parsed = try CellValueParser.parseNull(column: col)
                        } else {
                            parsed = try CellValueParser.parse(editText, column: col)
                        }
                        commitEdit(target: target, parsed: parsed, column: col)
                    } catch let e as CellValueParseError {
                        editError = describe(e, column: col)
                    } catch {
                        editError = String(describing: error)
                    }
                }
            )
        } else {
            defaultEditSheet(for: target, column: col)
        }
    }

    @ViewBuilder
    private func defaultEditSheet(for target: EditTarget, column col: ColumnMeta?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "pencil.circle.fill").foregroundStyle(Color.accentColor)
                Text("Edit `\(col?.name ?? "")`")
                    .font(.headline.monospaced())
                Spacer()
                if let c = col {
                    Text(c.mysqlType).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
            TextEditor(text: $editText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(editError != nil ? Color.red : Color.secondary.opacity(0.3),
                                lineWidth: 1)
                )

            if let col = col, col.nullable {
                Button("Set NULL") {
                    commitEdit(target: target, parsed: .null, column: col)
                }
                .buttonStyle(.borderless)
            }

            // SQL 美化按钮（任意 string 列都可用）
            if let col = col,
               col.normalizedType == .string,
               looksLikeSQL(editText) {
                Button("Format SQL") {
                    editText = SQLFormatter.format(editText)
                }
                .buttonStyle(.borderless)
            }

            if let err = editError {
                Text(err).foregroundStyle(.red).font(.caption.monospaced())
            }

            HStack {
                Spacer()
                Button("Cancel") { editingTarget = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    guard let col = col else { return }
                    do {
                        let parsed: CellValue
                        if editText.isEmpty && col.nullable {
                            parsed = try CellValueParser.parseNull(column: col)
                        } else {
                            parsed = try CellValueParser.parse(editText, column: col)
                        }
                        commitEdit(target: target, parsed: parsed, column: col)
                    } catch let e as CellValueParseError {
                        editError = describe(e, column: col)
                    } catch {
                        editError = String(describing: error)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    /// 判断当前编辑的单元格是否应当走 JSON 编辑器：
    /// - 列类型本身就是 JSON
    /// - 列类型是 BLOB（charset=binary），但内容是 JSON（即"BLOB-as-JSON"）
    /// - 列类型是 string（charset≠binary 的 TEXT 系列 / VARCHAR），且当前内容是 JSON
    ///   （即"TEXT-as-JSON"，常见于 log 表 error_msg / params 这类列）
    private func isJSONFlavored(col: ColumnMeta, target: EditTarget) -> Bool {
        if col.normalizedType == .json { return true }
        // 取当前值（含 pending）或原值
        let value: CellValue
        switch target {
        case .existing(let r, let c):
            let original = vm.resultSet?.rows[r][c] ?? .null
            value = vm.newValue(rowIdx: r, column: col.name) ?? original
        case .insert:
            // INSERT 占位行：默认走老路径（用户可输文本，parser 会按 JSON 启发式判断）
            return false
        }
        switch (col.normalizedType, value) {
        case (.blob, .blob(let d)):
            return JSONHelper.looksLikeJSONBLOB(d) != nil
        case (.string, .string(let s)):
            // TEXT-as-JSON 启发式：内容必须是 object/array，避免短字符串误判
            return JSONHelper.isJSON(s)
        default:
            return false
        }
    }

    // MARK: helpers

    private func currentColumn(for target: EditTarget) -> ColumnMeta? {
        guard let cols = vm.resultSet?.columns else { return nil }
        let i: Int
        switch target {
        case .existing(_, let c): i = c
        case .insert(_, let c):   i = c
        }
        guard i >= 0, i < cols.count else { return nil }
        return cols[i]
    }

    private func commitEdit(target: EditTarget, parsed: CellValue, column: ColumnMeta) {
        switch target {
        case .existing(let rowIdx, let columnIndex):
            vm.editCell(rowIdx: rowIdx, columnIndex: columnIndex, newValue: parsed)
        case .insert(let id, _):
            vm.setInsertCell(localId: id, column: column.name, value: parsed)
        }
        editingTarget = nil
        editText = ""
        editError = nil
    }

    private func describe(_ err: CellValueParseError, column: ColumnMeta) -> String {
        switch err {
        case .invalidInteger(let s): return "Not a valid integer: \(s)"
        case .invalidFloat(let s):   return "Not a valid number: \(s)"
        case .invalidDecimal(let s): return "Not a valid decimal: \(s)"
        case .invalidBool(let s):    return "Not a valid boolean: \(s)"
        case .invalidJSON(let m):    return "Invalid JSON: \(m)"
        case .nullNotAllowed:        return "Column \(column.name) does not allow NULL"
        case .unsupported:           return "Editing this type is not supported"
        }
    }

    private func cellString(_ cell: CellValue) -> String {
        switch cell {
        case .null:           return ""
        case .int(let v):     return String(v)
        case .uint(let v):    return String(v)
        case .double(let v):  return String(v)
        case .decimal(let s): return s
        case .string(let s):  return s
        case .bool(let b):    return b ? "true" : "false"
        case .date(let d), .datetime(let d):
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            f.timeZone = .current
            return f.string(from: d)
        case .time(let s):    return s
        case .blob(let d):
            // BLOB-as-JSON：内容是 JSON 字符串时直接显示
            if let s = JSONHelper.looksLikeJSONBLOB(d) { return s }
            return "[BLOB \(d.count) bytes]"
        case .json(let s):    return s
        case .unknown(let s): return s
        }
    }

    /// JSON 美化（解析 → 重新 encode）。失败返回 nil。
    private func prettyPrintJSON(_ s: String) -> String? {
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: obj,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let result = String(data: pretty, encoding: .utf8) else { return nil }
        return result
    }

    /// 粗略判断像 SQL（含 SELECT/UPDATE/INSERT/DELETE 关键字）
    private func looksLikeSQL(_ s: String) -> Bool {
        let upper = s.uppercased()
        return upper.contains("SELECT") || upper.contains("INSERT")
            || upper.contains("UPDATE") || upper.contains("DELETE")
    }
}

// MARK: - NSTableView wrapper

private struct NativeGridRepresentable: NSViewRepresentable {
    @Bindable var vm: DataTabViewModel
    let onCellDoubleClick: (Int, Int) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = false
        scroll.borderType = .noBorder

        let table = CopyableTableView()
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.allowsColumnResizing = true
        table.allowsColumnReordering = false
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.gridStyleMask = [.solidVerticalGridLineMask, .solidHorizontalGridLineMask]
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.rowHeight = 22
        table.style = .plain
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.doubleAction = #selector(Coordinator.cellDoubleClicked(_:))
        table.target = context.coordinator
        table.menu = makeMenu(coord: context.coordinator)

        scroll.documentView = table
        context.coordinator.tableView = table
        rebuildColumns(table: table, coord: context.coordinator)

        // 注册列宽变化通知
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.columnDidResize(_:)),
            name: NSTableView.columnDidResizeNotification,
            object: table
        )

        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? NSTableView else { return }
        context.coordinator.parent = self
        let cols = vm.resultSet?.columns.map(\.name) ?? []
        if context.coordinator.lastColumns != cols {
            rebuildColumns(table: table, coord: context.coordinator)
        }
        table.reloadData()
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    private func rebuildColumns(table: NSTableView, coord: Coordinator) {
        while !table.tableColumns.isEmpty {
            table.removeTableColumn(table.tableColumns.last!)
        }
        let lineCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("__line__"))
        lineCol.title = "#"
        lineCol.width = 56; lineCol.minWidth = 40; lineCol.maxWidth = 80
        lineCol.headerCell.alignment = .right
        table.addTableColumn(lineCol)
        let prefs = UserPreferences.shared
        let pkSet = Set(vm.schema?.primaryKey ?? [])
        for col in vm.resultSet?.columns ?? [] {
            let id = NSUserInterfaceItemIdentifier(col.name)
            let tc = NSTableColumn(identifier: id)

            // PK 列加 🔑；NOT NULL 加 *
            var title = col.name
            if pkSet.contains(col.name) { title = "🔑 \(title)" }
            if !col.nullable { title += " *" }
            tc.title = title
            tc.headerToolTip = "\(col.mysqlType)"
                + (pkSet.contains(col.name) ? " · PRIMARY KEY" : "")
                + (col.nullable ? "" : " · NOT NULL")

            tc.minWidth = 60
            tc.maxWidth = 800
            if let saved = prefs.columnWidth(database: vm.database, table: vm.table, column: col.name) {
                tc.width = saved
            } else {
                tc.width = 140
            }
            tc.sortDescriptorPrototype = NSSortDescriptor(key: col.name, ascending: true)
            table.addTableColumn(tc)
        }
        coord.lastColumns = vm.resultSet?.columns.map(\.name) ?? []

        // 给每个数据列做 KVO 监听 width，保证拖拽实时存（columnDidResizeNotification 在某些 macOS 版本不发）
        coord.installWidthObservers(on: table)
    }

    private func makeMenu(coord: Coordinator) -> NSMenu {
        let menu = NSMenu()
        let mark = NSMenuItem(title: "Mark for Delete",
                              action: #selector(Coordinator.markDelete(_:)),
                              keyEquivalent: "")
        mark.target = coord
        menu.addItem(mark)
        let unmark = NSMenuItem(title: "Unmark Delete",
                                action: #selector(Coordinator.unmarkDelete(_:)),
                                keyEquivalent: "")
        unmark.target = coord
        menu.addItem(unmark)
        return menu
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: NativeGridRepresentable
        weak var tableView: NSTableView?
        var lastColumns: [String] = []
        private var widthObservers: [NSKeyValueObservation] = []

        init(parent: NativeGridRepresentable) { self.parent = parent }

        deinit {
            widthObservers.forEach { $0.invalidate() }
        }

        /// 给每个非行号列做 KVO，width 一变就 → UserPreferences。
        /// 比 NSTableViewColumnDidResizeNotification 更可靠（后者仅在用户拖完才发，
        /// 且部分 macOS 版本只在 columnAutoresizingStyle = .uniformColumnAutoresizingStyle 下才发）。
        func installWidthObservers(on table: NSTableView) {
            widthObservers.forEach { $0.invalidate() }
            widthObservers = []
            let db = parent.vm.database
            let tb = parent.vm.table
            for tc in table.tableColumns {
                let key = tc.identifier.rawValue
                guard key != "__line__", !key.isEmpty else { continue }
                let obs = tc.observe(\.width, options: [.new]) { _, change in
                    guard let newVal = change.newValue else { return }
                    UserPreferences.shared.setColumnWidth(
                        Double(newVal),
                        database: db, table: tb, column: key
                    )
                }
                widthObservers.append(obs)
            }
        }

        // MARK: data source
        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.vm.sortedRowsWithOrigIdx().count
        }

        func tableView(_ tableView: NSTableView,
                       sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let desc = tableView.sortDescriptors.first,
                  let key = desc.key else {
                parent.vm.sortColumn = nil
                tableView.reloadData()
                return
            }
            parent.vm.sortColumn = key
            parent.vm.sortAscending = desc.ascending
            tableView.reloadData()
        }

        // MARK: view-based delegate
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                       row: Int) -> NSView? {
            guard let tc = tableColumn,
                  let rs = parent.vm.resultSet else { return nil }
            let sorted = parent.vm.sortedRowsWithOrigIdx()
            guard row < sorted.count else { return nil }
            let origRow = sorted[row].origIdx
            let rowValues = sorted[row].row

            let id = NSUserInterfaceItemIdentifier("Cell")
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? CellTextView)
                ?? CellTextView()
            cell.identifier = id

            let key = tc.identifier.rawValue
            let isDeleted = parent.vm.isRowMarkedForDeletion(rowIdx: origRow)

            if key == "__line__" {
                cell.label.alignment = .right
                cell.label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                if isDeleted {
                    cell.label.stringValue = "✗ \(origRow + 1)"
                    cell.label.textColor = .systemRed
                } else if parent.vm.isRowDirty(rowIdx: origRow) {
                    cell.label.stringValue = "● \(origRow + 1)"
                    cell.label.textColor = .systemYellow
                } else {
                    cell.label.stringValue = "\(origRow + 1)"
                    cell.label.textColor = .tertiaryLabelColor
                }
                cell.dirty = false
                cell.deleted = isDeleted
            } else {
                let colIdx = rs.columns.firstIndex { $0.name == key } ?? -1
                guard colIdx >= 0, colIdx < rowValues.count else {
                    cell.label.stringValue = ""
                    return cell
                }
                let displayed = parent.vm.newValue(rowIdx: origRow, column: key)
                    ?? rowValues[colIdx]
                cell.label.alignment = .left
                cell.label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                cell.label.stringValue = parent.cellString(displayed)
                cell.label.textColor = parent.cellColor(displayed)
                if case .null = displayed {
                    cell.label.stringValue = "(NULL)"
                    cell.label.textColor = .tertiaryLabelColor
                }
                cell.dirty = parent.vm.isCellDirty(rowIdx: origRow, column: key)
                cell.deleted = isDeleted
            }
            return cell
        }

        @objc func cellDoubleClicked(_ sender: AnyObject?) {
            guard let table = tableView else { return }
            let visibleRow = table.clickedRow
            let col = table.clickedColumn
            guard visibleRow >= 0, col >= 1 else { return }
            // 把 visible row 映射回 orig idx
            let sorted = parent.vm.sortedRowsWithOrigIdx()
            guard visibleRow < sorted.count else { return }
            let origRow = sorted[visibleRow].origIdx
            parent.onCellDoubleClick(origRow, col - 1)
        }

        @objc func markDelete(_ sender: AnyObject?) {
            guard let table = tableView else { return }
            let sorted = parent.vm.sortedRowsWithOrigIdx()
            let visibleRows = table.selectedRowIndexes.isEmpty
                ? [table.clickedRow].filter { $0 >= 0 }
                : Array(table.selectedRowIndexes)
            for vr in visibleRows where vr < sorted.count {
                let origRow = sorted[vr].origIdx
                if !parent.vm.isRowMarkedForDeletion(rowIdx: origRow) {
                    parent.vm.toggleRowDeletion(rowIdx: origRow)
                }
            }
            table.reloadData()
        }

        @objc func unmarkDelete(_ sender: AnyObject?) {
            guard let table = tableView else { return }
            let sorted = parent.vm.sortedRowsWithOrigIdx()
            let visibleRows = table.selectedRowIndexes.isEmpty
                ? [table.clickedRow].filter { $0 >= 0 }
                : Array(table.selectedRowIndexes)
            for vr in visibleRows where vr < sorted.count {
                let origRow = sorted[vr].origIdx
                if parent.vm.isRowMarkedForDeletion(rowIdx: origRow) {
                    parent.vm.toggleRowDeletion(rowIdx: origRow)
                }
            }
            table.reloadData()
        }

        // MARK: column resize → 持久化
        // 三层兜底：(1) NSTableViewDelegate 方法 (2) Notification (3) KVO
        // 至少有一个会触发。
        func tableViewColumnDidResize(_ notification: Notification) {
            guard let col = notification.userInfo?["NSTableColumn"] as? NSTableColumn else { return }
            saveWidth(col)
        }
        @objc func columnDidResize(_ note: Notification) {
            guard let col = note.userInfo?["NSTableColumn"] as? NSTableColumn else { return }
            saveWidth(col)
        }
        private func saveWidth(_ col: NSTableColumn) {
            let key = col.identifier.rawValue
            guard key != "__line__", !key.isEmpty else { return }
            UserPreferences.shared.setColumnWidth(
                Double(col.width),
                database: parent.vm.database,
                table: parent.vm.table,
                column: key
            )
            // 让用户能从命令行验证：
            UserDefaults.standard.synchronize()
        }
    }
}

// MARK: - Cell view

private final class CellTextView: NSTableCellView {
    let label = NSTextField(labelWithString: "")
    var dirty: Bool = false { didSet { needsDisplay = true } }
    var deleted: Bool = false { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        if deleted {
            NSColor.systemRed.withAlphaComponent(0.10).setFill()
            dirtyRect.fill()
        } else if dirty {
            NSColor.systemYellow.withAlphaComponent(0.18).setFill()
            dirtyRect.fill()
        }
        super.draw(dirtyRect)
    }
}

// MARK: - debug log to file

private let debugLogURL: URL = {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                        in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
    let folder = dir.appendingPathComponent("MacHeidi", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appendingPathComponent("debug.log")
}()

private func debugLog(_ msg: String) {
    let f = ISO8601DateFormatter()
    let line = "\(f.string(from: Date())) \(msg)\n"
    NSLog("[MacHeidi] %@", msg)
    if let data = line.data(using: .utf8) {
        if let h = try? FileHandle(forWritingTo: debugLogURL) {
            h.seekToEndOfFile()
            try? h.write(contentsOf: data)
            try? h.close()
        } else {
            // 文件还没创建 → 先创建
            try? "".write(to: debugLogURL, atomically: true, encoding: .utf8)
            try? data.write(to: debugLogURL)
        }
    }
}

// MARK: - shared helpers (used by parent + coordinator)

extension NativeGridRepresentable {
    fileprivate func cellString(_ cell: CellValue) -> String {
        switch cell {
        case .null:           return ""
        case .int(let v):     return String(v)
        case .uint(let v):    return String(v)
        case .double(let v):  return String(v)
        case .decimal(let s): return s
        case .string(let s):  return s
        case .bool(let b):    return b ? "true" : "false"
        case .date(let d), .datetime(let d):
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            f.timeZone = .current
            return f.string(from: d)
        case .time(let s):    return s
        case .blob(let d):
            // BLOB-as-JSON：表格里以单行 minified 形式预览
            if let s = JSONHelper.looksLikeJSONBLOB(d), let mini = JSONHelper.minify(s) {
                return mini
            }
            return "[BLOB \(d.count) bytes]"
        case .json(let s):    return s
        case .unknown(let s): return s
        }
    }
    fileprivate func cellColor(_ cell: CellValue) -> NSColor {
        switch cell {
        case .null:                              return .tertiaryLabelColor
        case .int, .uint, .double, .decimal:     return .labelColor
        case .bool:                              return .systemBlue
        case .date, .datetime, .time:            return .systemPurple
        case .json:                              return .systemGreen
        case .blob(let d):
            // BLOB-as-JSON 也用绿色 → 与 JSON 列视觉一致
            return JSONHelper.looksLikeJSONBLOB(d) != nil
                ? .systemGreen
                : .secondaryLabelColor
        case .string(let s):
            // TEXT-as-JSON：fast-path 看首字符避免每行全量 JSON 解析
            return looksLikeJSONFast(s) ? .systemGreen : .labelColor
        default:                                 return .labelColor
        }
    }

    /// 单帧渲染热路径用的快速 JSON 启发式：只看首尾，不调 JSONSerialization。
    /// false negative 可接受（颜色判错没大事），目标是 O(1) 不卡渲染。
    fileprivate func looksLikeJSONFast(_ s: String) -> Bool {
        guard s.count >= 2 else { return false }
        let trimmed = s.drop { $0.isWhitespace }
        guard let first = trimmed.first else { return false }
        if first != "{" && first != "[" { return false }
        // 已经像 JSON：再走一次完整解析以排除 "{ broken" 这种纯文本
        return JSONHelper.isJSON(s)
    }
}

/// 支持 Cmd+C 复制选中行（TSV 格式，含 header）的 NSTableView 子类。
private final class CopyableTableView: NSTableView {
    override func keyDown(with event: NSEvent) {
        // Cmd+C
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "c" {
            copyToPasteboard()
            return
        }
        super.keyDown(with: event)
    }

    private func copyToPasteboard() {
        guard let ds = dataSource,
              let dg = delegate as? NSTableViewDelegate else { return }
        let rows = selectedRowIndexes.isEmpty
            ? IndexSet(integer: max(0, clickedRow))
            : selectedRowIndexes
        guard !rows.isEmpty else { return }

        // 收集列名（跳过行号列）
        let dataCols = tableColumns.filter { $0.identifier.rawValue != "__line__" }
        var lines: [String] = []
        // header
        lines.append(dataCols.map { $0.identifier.rawValue }.joined(separator: "\t"))
        // body
        for r in rows {
            var fields: [String] = []
            for c in dataCols {
                if let view = dg.tableView?(self, viewFor: c, row: r) as? CellTextView {
                    fields.append(view.label.stringValue)
                } else {
                    fields.append("")
                }
            }
            lines.append(fields.joined(separator: "\t"))
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(lines.joined(separator: "\n"), forType: .string)
        _ = ds  // silence unused
    }
}

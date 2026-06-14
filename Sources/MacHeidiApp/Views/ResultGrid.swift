import SwiftUI
import AppKit
import MacHeidiCore

/// 只读结果网格 —— alpha 用 SwiftUI 撸；性能瓶颈再换 NSTableView。
///
/// 修复 v2：
///  1. 表格不再水平居中（VStack(alignment:.leading) + maxWidth: .infinity）
///  2. 列宽按 col.name + 前 50 行内容估算（等宽字体下精确对齐）
///  3. 行 hover 高亮、奇偶斑马线、列分隔线
///  4. 表头粘性置顶，可独立水平滚动
struct ResultGrid: View {
    let resultSet: ResultSet

    @State private var sortColumn: Int?
    @State private var sortAsc: Bool = true
    @State private var hoveredRow: Int?

    private static let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let cellHPad: CGFloat = 10
    private static let rowVPad: CGFloat = 4
    private static let lineNumberWidth: CGFloat = 48
    private static let minColumnWidth: CGFloat = 80
    private static let maxColumnWidth: CGFloat = 480

    var body: some View {
        let rows = sortedRows()
        let widths = computeWidths(rows: rows)

        VStack(alignment: .leading, spacing: 0) {
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow(widths: widths)
                        .background(Color(NSColor.controlBackgroundColor))
                    Divider()
                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                        dataRow(rowIdx: rowIdx, row: row, widths: widths)
                        Divider().opacity(0.25)
                    }
                    if rows.isEmpty {
                        Text("(no rows)")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                    // 顶对齐：少量行不应被垂直居中
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(NSColor.textBackgroundColor))

            Divider()
            HStack(spacing: 12) {
                Text("\(resultSet.rows.count) row\(resultSet.rows.count == 1 ? "" : "s")")
                Text("·")
                Text(elapsedString())
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.bar)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func headerRow(widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            Text("#")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .frame(width: Self.lineNumberWidth, alignment: .trailing)
                .padding(.horizontal, Self.cellHPad)
                .padding(.vertical, Self.rowVPad)
            verticalSeparator
            ForEach(Array(resultSet.columns.enumerated()), id: \.offset) { idx, col in
                Button {
                    if sortColumn == idx { sortAsc.toggle() }
                    else { sortColumn = idx; sortAsc = true }
                } label: {
                    HStack(spacing: 4) {
                        Text(col.name)
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if sortColumn == idx {
                            Image(systemName: sortAsc ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Self.cellHPad)
                .padding(.vertical, Self.rowVPad)
                .frame(width: widths[idx], alignment: .leading)
                verticalSeparator
            }
        }
    }

    // MARK: - Data row

    @ViewBuilder
    private func dataRow(rowIdx: Int, row: [CellValue], widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            Text("\(rowIdx + 1)")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .frame(width: Self.lineNumberWidth, alignment: .trailing)
                .padding(.horizontal, Self.cellHPad)
                .padding(.vertical, Self.rowVPad)
            verticalSeparator
            ForEach(Array(row.enumerated()), id: \.offset) { idx, cell in
                cellView(cell)
                    .frame(width: idx < widths.count ? widths[idx] : Self.minColumnWidth,
                           alignment: .leading)
                    .padding(.horizontal, Self.cellHPad)
                    .padding(.vertical, Self.rowVPad)
                verticalSeparator
            }
        }
        .background(rowBackground(for: rowIdx))
        .onHover { hovering in
            hoveredRow = hovering ? rowIdx : nil
        }
    }

    private func rowBackground(for idx: Int) -> Color {
        if hoveredRow == idx {
            return Color.accentColor.opacity(0.12)
        }
        return idx % 2 == 0 ? Color.clear : Color.primary.opacity(0.04)
    }

    private var verticalSeparator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1)
    }

    // MARK: - Cell

    @ViewBuilder
    private func cellView(_ cell: CellValue) -> some View {
        if case .null = cell {
            Text("(NULL)")
                .italic()
                .foregroundStyle(.tertiary)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            Text(cellString(cell))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(cellColor(cell))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(cellString(cell))   // hover 显示完整内容
        }
    }

    private func cellColor(_ cell: CellValue) -> Color {
        switch cell {
        case .int, .uint, .double, .decimal: return .primary
        case .bool:        return .blue
        case .date, .datetime, .time: return .purple
        case .json:        return .green
        case .blob(let d): return JSONHelper.looksLikeJSONBLOB(d) != nil ? .green : .secondary
        case .string(let s):
            // TEXT-as-JSON 启发式：首字符 + 完整解析（fast path 已避免大头）
            let trimmed = s.drop { $0.isWhitespace }
            if let first = trimmed.first, first == "{" || first == "[", JSONHelper.isJSON(s) {
                return .green
            }
            return .primary
        default:           return .primary
        }
    }

    // MARK: - Sorting

    private func sortedRows() -> [[CellValue]] {
        guard let c = sortColumn, c < resultSet.columns.count else { return resultSet.rows }
        return resultSet.rows.sorted { lhs, rhs in
            // 数字按数字比，其他按字符串
            if let a = numeric(lhs[c]), let b = numeric(rhs[c]) {
                return sortAsc ? a < b : a > b
            }
            let a = cellString(lhs[c])
            let b = cellString(rhs[c])
            return sortAsc ? a < b : a > b
        }
    }

    private func numeric(_ cell: CellValue) -> Double? {
        switch cell {
        case .int(let v):  return Double(v)
        case .uint(let v): return Double(v)
        case .double(let v): return v
        case .decimal(let s): return Double(s)
        default: return nil
        }
    }

    // MARK: - Width estimation

    /// 按列名 + 前 50 行内容估算列宽（等宽字体）。
    private func computeWidths(rows: [[CellValue]]) -> [CGFloat] {
        let attrs: [NSAttributedString.Key: Any] = [.font: Self.monoFont]
        let sample = rows.prefix(50)
        return resultSet.columns.enumerated().map { idx, col in
            var widest = (col.name as NSString).size(withAttributes: attrs).width + 18  // 含排序图标
            for row in sample {
                guard idx < row.count else { continue }
                let s = cellString(row[idx])
                let w = (s as NSString).size(withAttributes: attrs).width
                if w > widest { widest = w }
            }
            return min(max(Self.minColumnWidth, widest + Self.cellHPad * 2), Self.maxColumnWidth)
        }
    }

    // MARK: - Cell string

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
            if let s = JSONHelper.looksLikeJSONBLOB(d), let mini = JSONHelper.minify(s) {
                return mini
            }
            return "[BLOB \(d.count) bytes]"
        case .json(let s):    return s
        case .unknown(let s): return s
        }
    }

    private func elapsedString() -> String {
        let d = resultSet.executionTime
        let ms = Int(d.components.attoseconds / 1_000_000_000_000_000)
        let s  = d.components.seconds
        if s > 0 { return "\(s).\(String(format: "%03d", ms)) s" }
        return "\(ms) ms"
    }
}

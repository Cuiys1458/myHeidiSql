import SwiftUI
import AppKit
import MacHeidiCore

/// 查询历史浏览（PRD §11 v0.2）。Sheet 形式打开。
struct QueryHistoryView: View {
    @Binding var isPresented: Bool
    let onUseQuery: (String) -> Void

    @State private var entries: [QueryHistory.Entry] = []
    @State private var selectedId: UUID?
    @State private var search: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Query History").font(.headline)
                Spacer()
                Text("\(entries.count) entries")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Button("Clear All", role: .destructive) {
                    QueryHistory.shared.clear()
                    reload()
                }
                .controlSize(.small)
                Button("Close") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(10)
            Divider()

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter by SQL or database…", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            Divider()

            HSplitView {
                // 左：列表
                List(filteredEntries, id: \.id, selection: $selectedId) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(firstLine(e.sql))
                            .font(.callout.monospaced())
                            .lineLimit(1)
                            .foregroundStyle(e.success ? Color.primary : Color.red)
                        HStack(spacing: 6) {
                            Text(formatTime(e.timestamp))
                            Text("·")
                            Text("\(e.elapsedMs) ms")
                            if let db = e.database, !db.isEmpty {
                                Text("·")
                                Text(db).foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                    .tag(e.id)
                }
                .listStyle(.inset)
                .frame(minWidth: 360)

                // 右：详情
                if let entry = selectedEntry {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(entry.success ? .green : .red)
                            Text(formatTime(entry.timestamp)).foregroundStyle(.secondary)
                            Text("·")
                            Text("\(entry.elapsedMs) ms")
                            if let db = entry.database, !db.isEmpty {
                                Text("·")
                                Text(db).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Copy") {
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setString(entry.sql, forType: .string)
                            }
                            Button("Use This") {
                                onUseQuery(entry.sql)
                                isPresented = false
                            }
                            .keyboardShortcut(.defaultAction)
                        }
                        .font(.caption)

                        ScrollView {
                            Text(entry.sql)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .textSelection(.enabled)
                        }
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(4)
                    }
                    .padding(10)
                    .frame(minWidth: 360)
                } else {
                    VStack {
                        Text("Select an entry").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .onAppear { reload() }
    }

    private var selectedEntry: QueryHistory.Entry? {
        entries.first { $0.id == selectedId }
    }

    private var filteredEntries: [QueryHistory.Entry] {
        let s = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return entries }
        return entries.filter {
            $0.sql.lowercased().contains(s)
            || ($0.database?.lowercased().contains(s) ?? false)
        }
    }

    private func reload() {
        entries = QueryHistory.shared.all()
        if selectedId == nil { selectedId = entries.first?.id }
    }

    private func firstLine(_ sql: String) -> String {
        sql.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    private func formatTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f.string(from: d)
    }
}

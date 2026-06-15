import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MacHeidiCore

/// 数据浏览 + 编辑 Tab。
///
/// - 双击单元格进入编辑（PRD §5.3.6）
/// - 顶部 WHERE 输入栏（PRD §5.3.4）
/// - 底部翻页栏（PRD §5.3.5；默认 100 行）
/// - 出现脏行时顶部条目显示 Commit/Discard
/// - 无 PK 表 commit 前弹二次确认（PRD §5.3.7.2 / R4）
struct DataTabView: View {
    @Environment(AppEnvironment.self) private var env
    let database: String
    let table: String

    @State private var vm: DataTabViewModel
    @State private var whereInput: String = ""
    @State private var appliedWhere: String = ""
    @State private var isExporting: Bool = false
    @State private var exportAllProgress: UInt64 = 0
    @State private var exportDoneMessage: String?

    init(database: String, table: String) {
        self.database = database
        self.table = table
        _vm = State(wrappedValue: DataTabViewModel(database: database, table: table))
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            whereBar
            if !vm.warnings.isEmpty { warningsBar }
            if vm.hasPending { pendingBar }
            if isExporting || exportDoneMessage != nil { exportBar }
            Divider()
            if vm.loading {
                VStack(spacing: 12) {
                    ProgressView()
                    Button {
                        Task { await env.activeClient?.cancel() }
                    } label: {
                        Label(L("query.cancel"), systemImage: "stop.fill")
                    }
                    .keyboardShortcut(".", modifiers: .command)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = vm.error {
                ScrollView {
                    Text(err).foregroundStyle(.red)
                        .font(.system(.body, design: .monospaced))
                        .padding().textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                EditableResultGrid(vm: vm)
            }
            Divider()
            paginationBar
        }
        .task { await vm.loadCurrentPage(env: env, whereClause: appliedWhere) }
        .onChange(of: env.tableRefreshTicker[
            AppEnvironment.TableKey(database: database, table: table)
        ] ?? 0) { _, _ in
            Task { await vm.resetToFirstPage(env: env, whereClause: appliedWhere) }
        }
        .onChange(of: vm.commitSuccessFlag) { _, _ in
            Task { await vm.reloadAfterCommit(env: env, whereClause: appliedWhere) }
        }
        .sheet(item: bindingForConfirmation) { conf in
            NoPKCommitConfirmationSheet(confirmation: conf, vm: vm, env: env)
        }
    }

    private var bindingForConfirmation: Binding<NoPKConfirmationItem?> {
        Binding(
            get: {
                vm.pendingCommitConfirmation.map {
                    NoPKConfirmationItem(payload: $0)
                }
            },
            set: { newValue in
                if newValue == nil { vm.pendingCommitConfirmation = nil }
            }
        )
    }

    @ViewBuilder
    private var headerBar: some View {
        HStack {
            Text("`\(database)`.`\(table)`")
                .font(.headline.monospaced())
            if !appliedWhere.isEmpty {
                Text("WHERE \(appliedWhere)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12)).cornerRadius(4)
            }
            Spacer()
            Menu {
                Section(header: Text(L("data.exportPage"))) {
                    Button(L("data.exportPageCSV")) { exportCurrent(.csv) }
                    Button(L("data.exportPageTSV")) { exportCurrent(.tsv) }
                    Button(L("data.exportPageSQL")) { exportCurrent(.sql) }
                }
                Section(header: Text(L("data.exportAll"))) {
                    Button(L("data.exportAllCSV")) { exportAll(.csv) }
                    Button(L("data.exportAllTSV")) { exportAll(.tsv) }
                    Button(L("data.exportAllSQL")) { exportAll(.sql) }
                }
            } label: {
                Label(L("data.export"), systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(vm.resultSet?.rows.isEmpty ?? true)
            .help("Export current page or entire table")

            Button {
                Task { await vm.loadCurrentPage(env: env, whereClause: appliedWhere) }
            } label: {
                Label(L("data.refresh"), systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(vm.hasPending)
            .help(vm.hasPending ? "Commit or discard pending changes first" : "Refresh (⌘R / F5)")
            // F5 备用键位（PRD §7.3）。注意 macOS 默认 F5 被 Mission Control 占用，
            // 用户需要在系统设置改 fn 键行为；不影响 ⌘R。
            Button("") {
                Task { await vm.loadCurrentPage(env: env, whereClause: appliedWhere) }
            }
            .keyboardShortcut(KeyEquivalent("\u{F705}"), modifiers: [])
            .opacity(0).frame(width: 0, height: 0)
            .disabled(vm.hasPending)
        }
        .padding(8)
    }

    @ViewBuilder
    private var whereBar: some View {
        HStack(spacing: 8) {
            Text(L("data.where"))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            TextField("", text: $whereInput,
                      prompt: Text(verbatim: "e.g.  status = 'active'"))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit { applyWhere() }
                .disabled(vm.hasPending)
            Button {
                applyWhere()
            } label: { Image(systemName: "play.fill") }
            .help(Text(L("data.applyWhere")))
            .disabled(vm.hasPending)
            if !appliedWhere.isEmpty || !whereInput.isEmpty {
                Button {
                    whereInput = ""; applyWhere()
                } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(vm.hasPending)
            }
        }
        .padding(.horizontal, 8).padding(.bottom, 6)
    }

    @ViewBuilder
    private var exportBar: some View {
        HStack(spacing: 12) {
            if isExporting {
                ProgressView().controlSize(.small)
                Text(String(format: NSLocalizedString(
                    "data.exporting", bundle: .module, comment: ""
                ), exportAllProgress))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let msg = exportDoneMessage {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(msg)
                    .font(.caption)
                    .textSelection(.enabled)
                Spacer()
                Button {
                    exportDoneMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(isExporting ? Color.blue.opacity(0.10) : Color.green.opacity(0.10))
    }

    @ViewBuilder
    private var warningsBar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(vm.warnings.enumerated()), id: \.offset) { _, msg in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(msg)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10))
    }

    @ViewBuilder
    private var pendingBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "pencil.circle.fill")
                .foregroundStyle(.orange)
            Text(vm.pendingSummary)
                .font(.callout)
            Spacer()
            Button {
                Task { await vm.attemptCommit(env: env) }
            } label: {
                Label(L("data.commit"), systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            Button {
                vm.discardAll()
            } label: {
                Label(L("data.discard"), systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Color.yellow.opacity(0.10))
    }

    @ViewBuilder
    private var paginationBar: some View {
        let p = vm.pagination
        let pageDisplay: String = {
            if let total = p.totalPages {
                return "Page \(p.currentPage) / \(total)"
            }
            return "Page \(p.currentPage) / ?"
        }()
        let totalDisplay: String = {
            if let total = vm.totalRows {
                return "\(total) row\(total == 1 ? "" : "s") total"
            }
            return "total ?"
        }()

        HStack(spacing: 6) {
            // First / Prev
            Button {
                Task { await vm.goFirst(env: env, whereClause: appliedWhere) }
            } label: {
                Image(systemName: "chevron.left.to.line")
            }
            .help("First page")
            .disabled(!p.canGoFirst || vm.hasPending)

            Button {
                Task { await vm.goPrev(env: env, whereClause: appliedWhere) }
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("Previous page")
            .disabled(!p.canGoPrev || vm.hasPending)

            Text(pageDisplay)
                .font(.caption.monospaced())
                .frame(minWidth: 80)

            // 跳页输入框
            if let pages = p.totalPages, pages > 1 {
                Text(L("data.go"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("", text: jumpPageBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                    .frame(width: 60)
                    .onSubmit { commitJump() }
                    .disabled(vm.hasPending)
            }

            Button {
                Task { await vm.goNext(env: env, whereClause: appliedWhere) }
            } label: {
                Image(systemName: "chevron.right")
            }
            .help("Next page")
            .disabled(!p.canGoNext || vm.hasPending)

            Button {
                Task { await vm.goLast(env: env, whereClause: appliedWhere) }
            } label: {
                Image(systemName: "chevron.right.to.line")
            }
            .help("Last page")
            .disabled(!p.canGoLast || vm.hasPending)

            Divider().frame(height: 14)

            Text(L("data.pageSizeLabel"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: pageSizeBinding) {
                ForEach(Pagination.allowedPageSizes, id: \.self) { s in
                    Text("\(s)").tag(s)
                }
            }
            .labelsHidden()
            .frame(width: 80)
            .disabled(vm.hasPending)

            Spacer()

            Text(totalDisplay)
                .font(.caption)
                .foregroundStyle(.secondary)

            if vm.hasPending {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("Commit or discard changes first")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bar)
    }

    @State private var jumpPageText: String = ""

    private var jumpPageBinding: Binding<String> {
        Binding(
            get: { jumpPageText },
            set: { jumpPageText = $0.filter(\.isNumber) }
        )
    }

    private func commitJump() {
        guard let p = Int(jumpPageText), p >= 1 else {
            jumpPageText = ""
            return
        }
        let pages = vm.pagination.totalPages ?? Int.max
        let target = min(p, pages)
        Task { await vm.goToPage(target, env: env, whereClause: appliedWhere) }
        jumpPageText = ""
    }

    private var pageSizeBinding: Binding<Int> {
        Binding(
            get: { vm.pagination.pageSize },
            set: { newSize in
                Task { await vm.setPageSize(newSize, env: env, whereClause: appliedWhere) }
            }
        )
    }

    private func applyWhere() {
        appliedWhere = whereInput.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await vm.resetToFirstPage(env: env, whereClause: appliedWhere) }
    }

    /// 导出当前页 ResultSet 到文件。
    private func exportCurrent(_ format: ResultExporter.Format) {
        guard let rs = vm.resultSet else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        switch format {
        case .csv: panel.nameFieldStringValue = "\(table).csv"
        case .tsv: panel.nameFieldStringValue = "\(table).tsv"
        case .sql: panel.nameFieldStringValue = "\(table).sql"
        }
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            let text: String
            switch format {
            case .csv: text = ResultExporter.toCSV(rs)
            case .tsv: text = ResultExporter.toTSV(rs)
            case .sql: text = ResultExporter.toSQL(rs, database: database, table: table)
            }
            try? text.data(using: .utf8)?.write(to: url, options: .atomic)
        }
    }

    /// 导出整张表（流式分块写）。
    private func exportAll(_ format: ResultExporter.Format) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        switch format {
        case .csv: panel.nameFieldStringValue = "\(table)_all.csv"
        case .tsv: panel.nameFieldStringValue = "\(table)_all.tsv"
        case .sql: panel.nameFieldStringValue = "\(table)_all.sql"
        }
        let whereCopy = appliedWhere
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            exportAllProgress = 0
            isExporting = true
            Task {
                do {
                    let total = try await vm.exportAll(
                        to: url,
                        format: format,
                        whereClause: whereCopy,
                        env: env,
                        chunkSize: 2000,
                        progress: { rows in
                            Task { @MainActor in exportAllProgress = rows }
                        }
                    )
                    await MainActor.run {
                        isExporting = false
                        exportDoneMessage = "Exported \(total) row\(total == 1 ? "" : "s") to \(url.lastPathComponent)"
                    }
                } catch {
                    await MainActor.run {
                        isExporting = false
                        exportDoneMessage = "Export failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}

// MARK: - No-PK confirmation

/// Identifiable 包装，sheet(item:) 用
private struct NoPKConfirmationItem: Identifiable, Equatable {
    let id = UUID()
    let payload: NoPKConfirmation
}

private struct NoPKCommitConfirmationSheet: View {
    let confirmation: NoPKConfirmationItem
    let vm: DataTabViewModel
    let env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Table has no primary key")
                        .font(.headline)
                    Text("UPDATE/DELETE statements will use ALL non-BLOB columns in the WHERE clause, which may match multiple rows unintentionally.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Pending changes:")
                    .font(.subheadline.bold())
                Group {
                    if confirmation.payload.updates > 0 {
                        Text("• \(confirmation.payload.updates) UPDATE\(confirmation.payload.updates == 1 ? "" : "s")")
                    }
                    if confirmation.payload.inserts > 0 {
                        Text("• \(confirmation.payload.inserts) INSERT\(confirmation.payload.inserts == 1 ? "" : "s")")
                    }
                    if confirmation.payload.deletes > 0 {
                        Text("• \(confirmation.payload.deletes) DELETE\(confirmation.payload.deletes == 1 ? "" : "s")")
                    }
                }
                .font(.callout.monospaced())
                .padding(.leading, 8)
            }

            HStack {
                Spacer()
                Button(L("common.cancel")) {
                    vm.pendingCommitConfirmation = nil
                }
                .keyboardShortcut(.cancelAction)
                Button("Continue") {
                    Task { await vm.performCommit(env: env) }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MacHeidiCore

/// CSV 导入向导（Sheet）。
struct CSVImportView: View {
    @Bindable var vm: CSVImportViewModel
    let env: AppEnvironment
    let onClose: () -> Void

    @State private var separatorChoice: SepChoice = .comma

    enum SepChoice: String, CaseIterable, Identifiable {
        case comma = ",", tab = "\\t", semicolon = ";", pipe = "|"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .comma: return "Comma (,)"
            case .tab: return "Tab"
            case .semicolon: return "Semicolon (;)"
            case .pipe: return "Pipe (|)"
            }
        }
        var character: Character {
            switch self {
            case .comma: return ","
            case .tab: return "\t"
            case .semicolon: return ";"
            case .pipe: return "|"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Group {
                if vm.fileURL == nil {
                    fileChooserBody
                } else if vm.importing || vm.importDone || vm.importError != nil {
                    progressBody
                } else {
                    mappingBody
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
        }
        .frame(minWidth: 820, idealWidth: 900,
               minHeight: 600, idealHeight: 680)
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.and.arrow.down.on.square")
            Text("Import CSV → `\(vm.database)`.`\(vm.table)`")
                .font(.headline.monospaced())
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private var fileChooserBody: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.text.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text("Choose a CSV file to import").font(.title3)
            Button {
                pickFile()
            } label: {
                Label("Choose File…", systemImage: "folder")
            }
            .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var mappingBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部：文件信息 + 选项（不滚动）
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "doc.fill").foregroundStyle(.blue)
                    Text(vm.fileName).font(.callout.monospaced())
                    Spacer()
                    Text("\(vm.totalRows) row\(vm.totalRows == 1 ? "" : "s")")
                        .foregroundStyle(.secondary).font(.caption)
                    Button("Change…") { pickFile() }
                        .controlSize(.small)
                }
                HStack(spacing: 16) {
                    Picker("Separator", selection: $separatorChoice) {
                        ForEach(SepChoice.allCases) { c in
                            Text(c.label).tag(c)
                        }
                    }
                    .frame(maxWidth: 240)
                    .onChange(of: separatorChoice) { _, new in
                        vm.setSeparator(new.character)
                    }
                    Toggle("First row is header", isOn: Binding(
                        get: { vm.hasHeader },
                        set: { vm.setHasHeader($0) }
                    ))
                    Spacer()
                }
                if let err = vm.parseError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
                if !vm.missingRequiredColumns.isEmpty {
                    Label("Required columns not mapped: \(vm.missingRequiredColumns.joined(separator: ", "))",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)

            Divider()

            // 中间：列映射（可滚动，固定占用一半空间）
            VStack(alignment: .leading, spacing: 6) {
                Text("Column Mapping")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 16)
                ScrollView {
                    mappingTable
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.top, 8)

            // 预览区（固定高度，独立滚动）
            if !vm.preview.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Preview (first 20 rows)")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 16)
                    ScrollView([.horizontal, .vertical]) {
                        previewTable
                    }
                    .frame(height: 180)
                    .background(Color(NSColor.textBackgroundColor))
                }
                .padding(.top, 8).padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private var mappingTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                col("Table Column", width: 220)
                col("Type", width: 160)
                col("←", width: 30)
                col("CSV Column", width: 240)
            }
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            Divider()
            ForEach(Array(vm.schema.columns.enumerated()), id: \.offset) { idx, c in
                HStack(spacing: 0) {
                    HStack(spacing: 4) {
                        if vm.schema.primaryKey.contains(c.name) {
                            Image(systemName: "key.fill").foregroundStyle(.yellow).font(.caption2)
                        }
                        Text(c.name).font(.callout.monospaced())
                        if !c.nullable {
                            Text("*").foregroundStyle(.red).font(.caption2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(width: 220, alignment: .leading)

                    Text(c.mysqlType)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 160, alignment: .leading)
                        .padding(.horizontal, 8)

                    Image(systemName: "arrow.left").foregroundStyle(.tertiary).font(.caption2)
                        .frame(width: 30)

                    Picker("", selection: csvBinding(for: c.name)) {
                        Text("(skip)").tag(Optional<Int>.none)
                        ForEach(Array(vm.csvColumns.enumerated()), id: \.offset) { ci, name in
                            Text(name).tag(Optional<Int>.some(ci))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 240)
                    .padding(.horizontal, 8)
                }
                .padding(.vertical, 3)
                .background(idx % 2 != 0 ? Color.primary.opacity(0.04) : Color.clear)
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    @ViewBuilder
    private var previewTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(vm.csvColumns.enumerated()), id: \.offset) { _, name in
                    Text(name)
                        .font(.caption.monospaced().bold())
                        .frame(minWidth: 120, alignment: .leading)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            Divider()
            ForEach(Array(vm.preview.enumerated()), id: \.offset) { idx, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .frame(minWidth: 120, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                    }
                }
                .background(idx % 2 != 0 ? Color.primary.opacity(0.04) : Color.clear)
            }
        }
    }

    @ViewBuilder
    private var progressBody: some View {
        VStack(spacing: 16) {
            Spacer()
            if vm.importing {
                ProgressView(value: Double(vm.importProgress),
                             total: Double(max(vm.importTotal, 1)))
                    .frame(width: 360)
                Text("Imported \(vm.importProgress) / \(vm.importTotal)")
                    .font(.callout.monospaced())
            } else if vm.importDone {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text("Done — \(vm.importedRows) rows imported")
                    .font(.title3)
            } else if let err = vm.importError {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.red)
                Text("Import failed").font(.title3)
                ScrollView {
                    Text(err)
                        .font(.callout.monospaced())
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: 600, maxHeight: 200)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Spacer()
            Button("Close") { onClose() }
                .keyboardShortcut(.cancelAction)
                .disabled(vm.importing)
            if !vm.importing && !vm.importDone && vm.importError == nil {
                Button("Import") {
                    Task { await vm.performImport(env: env) }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!vm.canImport)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private func col(_ s: String, width: CGFloat) -> some View {
        Text(s)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 8)
    }

    private func csvBinding(for tableCol: String) -> Binding<Int?> {
        Binding(
            get: { vm.mapping[tableCol] ?? nil },
            set: { vm.mapping[tableCol] = $0 }
        )
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            vm.setFile(url, separator: separatorChoice.character, hasHeader: vm.hasHeader)
        }
    }
}

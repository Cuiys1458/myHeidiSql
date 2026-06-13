import SwiftUI
import MacHeidiCore

struct SessionManagerView: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var isPresented: Bool

    @State private var selectedId: UUID?
    @State private var draft: SessionConfig = .blank()   // 始终 non-nil，由 hasSelection 控制可见
    @State private var hasSelection = false

    @State private var error: String?
    @State private var testing = false
    @State private var testResult: String?

    // 自动保存：每次 draft 改动 600ms 内无新改动则落盘
    @State private var saveDebounceTask: Task<Void, Never>?

    var body: some View {
        HSplitView {
            // ── 左：列表 + 工具栏
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    Button {
                        addNew()
                    } label: { Image(systemName: "plus") }
                    .help("New session")

                    Button {
                        guard let id = selectedId else { return }
                        try? env.duplicateSession(id)
                        env.reloadSessions()
                        selectedId = env.sessions.last?.id
                        loadDraft()
                    } label: { Image(systemName: "doc.on.doc") }
                    .help("Duplicate selected")
                    .disabled(selectedId == nil)

                    Button {
                        guard let id = selectedId else { return }
                        try? env.deleteSession(id)
                        selectedId = nil
                        hasSelection = false
                    } label: { Image(systemName: "minus") }
                    .help("Delete selected")
                    .disabled(selectedId == nil)

                    Spacer()
                }
                .padding(8)

                List(env.sessions, selection: $selectedId) { s in
                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundStyle(.secondary)
                        Text(s.name)
                    }
                    .tag(s.id)
                }
                .onChange(of: selectedId) { _, _ in loadDraft() }
            }
            .frame(minWidth: 220, idealWidth: 260)

            // ── 右：表单 / 空态
            if hasSelection {
                ScrollView {
                    SessionForm(draft: $draft)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .frame(minWidth: 360, idealWidth: 400)   // 强制宽度，避免字段折行
                .onChange(of: draft) { _, newVal in
                    scheduleAutoSave(newVal)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text(env.sessions.isEmpty
                         ? "No sessions yet. Click  +  on the left to create one."
                         : "Select a session on the left to edit, or click  +  to add a new one.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                    Button {
                        addNew()
                    } label: {
                        Label("New Connection…", systemImage: "plus.circle.fill")
                    }
                    .controlSize(.large)
                    .keyboardShortcut("n", modifiers: .command)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            HStack {
                if let err = error {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.callout)
                        .textSelection(.enabled)
                } else if let r = testResult {
                    Label(r, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.callout)
                } else if hasSelection {
                    Text("Changes save automatically")
                        .foregroundStyle(.tertiary).font(.caption)
                }
                Spacer()
                Button("Test") { testConnection() }
                    .disabled(!hasSelection || testing)
                Button("Open") { openSelected() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasSelection)
                Button("Close") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(.bar)
        }
        .onAppear {
            // 首次打开自动选第一个；新用户走 "New Connection…" CTA
            if selectedId == nil, let first = env.sessions.first {
                selectedId = first.id
                loadDraft()
            }
        }
    }

    // MARK: - Actions

    private func addNew() {
        let new = SessionConfig(
            name: nextDefaultName(),
            hostname: "127.0.0.1",
            port: 3306,
            user: "root"
        )
        do {
            try env.addSession(new)
            env.reloadSessions()
            if let added = env.sessions.first(where: { $0.id == new.id }) {
                selectedId = added.id
            } else {
                // 名字被规范化后 id 可能仍然是 new.id（add 用了原 id）
                selectedId = env.sessions.last?.id
            }
            loadDraft()
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }

    private func nextDefaultName() -> String {
        let used = Set(env.sessions.map(\.name))
        if !used.contains("New Connection") { return "New Connection" }
        var n = 2
        while used.contains("New Connection (\(n))") { n += 1 }
        return "New Connection (\(n))"
    }

    private func loadDraft() {
        if let id = selectedId, let s = env.sessions.first(where: { $0.id == id }) {
            // 编辑表单：尝试从 Keychain 读密码（一次性，触发授权弹窗 1 次）
            // 失败容忍：留空密码，用户输入即可
            var withPw = s
            if let loaded = try? env.sessionManager.loadOneWithPassword(id: s.id) {
                withPw = loaded
            }
            draft = withPw
            hasSelection = true
        } else {
            draft = .blank()
            hasSelection = false
        }
        error = nil
        testResult = nil
        saveDebounceTask?.cancel()
        saveDebounceTask = nil
    }

    /// 自动保存：debounce 600ms。期间不再改动就落盘。
    /// 这样用户输入流畅，又不会丢"忘点 Save"。
    private func scheduleAutoSave(_ value: SessionConfig) {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            if Task.isCancelled { return }
            do {
                try env.updateSession(value)
                env.reloadSessions()
                error = nil
                testResult = nil
            } catch {
                self.error = String(describing: error)
            }
        }
    }

    private func openSelected() {
        // 触发一次立即保存（取消 debounce）
        saveDebounceTask?.cancel()
        do {
            try env.updateSession(draft)
        } catch {
            self.error = String(describing: error)
            return
        }
        env.reloadSessions()
        let toOpen = draft
        isPresented = false
        Task { await env.openSession(toOpen) }
    }

    private func testConnection() {
        // 测试前先 flush 一次
        saveDebounceTask?.cancel()
        try? env.updateSession(draft)
        env.reloadSessions()

        let d = draft
        testing = true
        testResult = nil
        error = nil
        Task {
            let client = MySQLClientFactory.make()
            let cfg = ConnectionConfig(
                hostname: d.hostname, port: d.port, user: d.user, password: d.password,
                defaultDatabase: nil, useSSL: d.useSSL,
                connectTimeout: .seconds(10), queryTimeout: nil
            )
            do {
                try await client.connect(cfg)
                await client.disconnect()
                testResult = "Connected to \(d.hostname):\(d.port) as \(d.user)"
            } catch let e as DBError {
                error = describe(e)
            } catch {
                self.error = String(describing: error)
            }
            testing = false
        }
    }

    private func describe(_ e: DBError) -> String {
        switch e {
        case .network(let m, _): return "Network: \(m)"
        case .auth(let m, _):    return "Auth: \(m)"
        case .timeout(let m):    return "Timeout: \(m)"
        default:                  return String(describing: e)
        }
    }
}

// MARK: - Form

private struct SessionForm: View {
    @Binding var draft: SessionConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Identity")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)

                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name").font(.caption).foregroundStyle(.secondary)
                        TextField("", text: $draft.name)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Comment").font(.caption).foregroundStyle(.secondary)
                        TextField("", text: $draft.comment, axis: .vertical)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)
                            .frame(minHeight: 52, alignment: .top)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Connection")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)

                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hostname / IP").font(.caption).foregroundStyle(.secondary)
                        TextField("", text: $draft.hostname)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Port").font(.caption).foregroundStyle(.secondary)
                            TextField("", value: $draft.port, format: .number)
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 120)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("User").font(.caption).foregroundStyle(.secondary)
                            TextField("", text: $draft.user)
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Password").font(.caption).foregroundStyle(.secondary)
                        SecureField("", text: $draft.password)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Default Database(s)").font(.caption).foregroundStyle(.secondary)
                        TextField("", text: $draft.defaultDatabases)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack(spacing: 12) {
                        Toggle("Use SSL", isOn: $draft.useSSL)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .padding(.top, 4)
                        Spacer()
                    }
                }
            }

            // ── SSH 隧道（PRD §11 v0.2）
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("SSH Tunnel (optional)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Enable", isOn: sshEnabledBinding)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
                .padding(.leading, 4)

                if draft.sshConfig?.isEnabled == true {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("SSH Host").font(.caption).foregroundStyle(.secondary)
                                TextField("", text: sshHostBinding)
                                    .labelsHidden().textFieldStyle(.roundedBorder)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Port").font(.caption).foregroundStyle(.secondary)
                                TextField("", value: sshPortBinding, format: .number)
                                    .labelsHidden().textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 100)
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SSH User").font(.caption).foregroundStyle(.secondary)
                            TextField("", text: sshUserBinding)
                                .labelsHidden().textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Private Key Path (optional, e.g. ~/.ssh/id_ed25519)")
                                .font(.caption).foregroundStyle(.secondary)
                            TextField("", text: sshKeyBinding)
                                .labelsHidden().textFieldStyle(.roundedBorder)
                        }
                        Text("Note: requires public-key auth (ssh-agent or specified key). Password prompt is not supported.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 8)
        }
    }

    // MARK: SSH bindings

    private var sshEnabledBinding: Binding<Bool> {
        Binding(
            get: { draft.sshConfig?.isEnabled ?? false },
            set: { newValue in
                if newValue {
                    if draft.sshConfig == nil {
                        draft.sshConfig = SSHTunnelConfig(sshHost: "", sshUser: "")
                    }
                } else {
                    draft.sshConfig = nil
                }
            }
        )
    }
    private var sshHostBinding: Binding<String> {
        Binding(
            get: { draft.sshConfig?.sshHost ?? "" },
            set: { draft.sshConfig?.sshHost = $0 }
        )
    }
    private var sshPortBinding: Binding<Int> {
        Binding(
            get: { draft.sshConfig?.sshPort ?? 22 },
            set: { draft.sshConfig?.sshPort = $0 }
        )
    }
    private var sshUserBinding: Binding<String> {
        Binding(
            get: { draft.sshConfig?.sshUser ?? "" },
            set: { draft.sshConfig?.sshUser = $0 }
        )
    }
    private var sshKeyBinding: Binding<String> {
        Binding(
            get: { draft.sshConfig?.privateKeyPath ?? "" },
            set: { draft.sshConfig?.privateKeyPath = $0 }
        )
    }
}

// MARK: - Helpers

private extension SessionConfig {
    static func blank() -> SessionConfig {
        SessionConfig(name: "", hostname: "", port: 0, user: "")
    }
}

// 桥到 MacHeidiMySQL 模块（避免在视图层直接 import）
enum MySQLClientFactory {
    static func make() -> any DBClient {
        _make()
    }
}

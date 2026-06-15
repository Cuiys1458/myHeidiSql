import SwiftUI
import MacHeidiCore

struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showSessionManager = false
    @State private var showHistory = false

    var body: some View {
        VStack(spacing: 0) {
            if env.connectionLost {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.icloud.fill")
                        .foregroundStyle(.red)
                    Text("Connection to '\(env.activeSession?.name ?? "")' was lost.")
                        .foregroundStyle(.primary)
                    Button(L("data.reconnect")) {
                        Task { await env.reconnectActive() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .controlSize(.small)
                    Button(L("data.dismiss")) {
                        env.disconnectActive()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.red.opacity(0.08))
                .frame(maxWidth: .infinity)
            }

            NavigationSplitView {
                SidebarView(onEditSession: { showSessionManager = true })
                    .frame(minWidth: 220)
            } detail: {
                VStack(spacing: 0) {
                    if env.openTabs.isEmpty {
                        EmptyMainView(onNewSession: { showSessionManager = true })
                    } else {
                        TabBarView()
                        Divider()
                        if let id = env.selectedTabId,
                           let tab = env.openTabs.first(where: { $0.id == id }) {
                            switch tab.kind {
                            case .query(let title):
                                QueryTabView(tabId: tab.id, title: title)
                                    .id(tab.id)
                            case .data(let db, let table):
                                DataTabView(database: db, table: table)
                                    .id(tab.id)
                            case .tableInfo(let db, let table):
                                TableInfoView(database: db, table: table)
                                    .id(tab.id)
                            }
                        }
                    }
                }
            }

            // 底部状态栏（PRD §6.4）
            StatusBar()
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    showSessionManager = true
                } label: {
                    Label(L("toolbar.sessions"), systemImage: "server.rack")
                }
                .help("Manage connections (⌘⇧S)")
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showHistory = true
                } label: {
                    Label(L("toolbar.history"), systemImage: "clock.arrow.circlepath")
                }
                .help("Query history (⌘Y)")
                .keyboardShortcut("y", modifiers: .command)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await env.refreshSelected() }
                } label: {
                    Label(L("toolbar.refresh"), systemImage: "arrow.clockwise")
                }
                .help("Refresh current node (F5 / ⌘R)")
                .keyboardShortcut("r", modifiers: .command)
                .disabled(env.activeSession == nil || env.connectionState != .connected)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    env.openNewQueryTab()
                } label: {
                    Label(L("toolbar.newQuery"), systemImage: "plus.rectangle")
                }
                .disabled(env.activeSession == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    env.disconnectActive()
                } label: {
                    Label(L("toolbar.disconnect"), systemImage: "eject")
                }
                .disabled(env.activeSession == nil)
            }
        }
        .sheet(isPresented: $showSessionManager) {
            SessionManagerView(isPresented: $showSessionManager)
                .frame(minWidth: 820, idealWidth: 880,
                       minHeight: 560, idealHeight: 600)
        }
        .sheet(isPresented: $showHistory) {
            QueryHistoryView(isPresented: $showHistory) { sql in
                // 找到当前 active query tab，把 sql 灌进去；找不到就新建
                env.openNewQueryTab()
                env.pendingHistorySQL = sql
            }
        }
        .navigationTitle(env.activeSession?.name ?? "MacHeidi")
        .task {
            // 首次启动：没有任何已保存 session → 自动弹 Session Manager
            // 之后启动：留给用户主动点 Sessions 按钮
            if env.sessions.isEmpty && env.activeSession == nil {
                showSessionManager = true
            }
        }
    }
}

private struct StatusBar: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        HStack(spacing: 12) {
            // 连接圆点
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
            Text(stateLabel)
                .foregroundStyle(.secondary)

            if let info = env.serverInfo {
                Divider().frame(height: 12)
                Text("MySQL \(info.version)")
                    .foregroundStyle(.secondary)
                if !info.timeZone.isEmpty {
                    Divider().frame(height: 12)
                    Text("tz: \(info.timeZone)")
                        .foregroundStyle(.secondary)
                }
            }
            if let db = env.currentDatabase, !db.isEmpty {
                Divider().frame(height: 12)
                Image(systemName: "cylinder")
                    .foregroundStyle(.secondary).font(.caption2)
                Text(db)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
            }

            Spacer()

            if let s = env.activeSession {
                Text("\(s.user)@\(s.hostname):\(s.port)")
                    .foregroundStyle(.tertiary)
                    .font(.caption.monospaced())
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var dotColor: Color {
        switch env.connectionState {
        case .connected:  return .green
        case .connecting: return .orange
        case .failed:     return .red
        case .idle:       return .gray
        }
    }
    private var stateLabel: String {
        switch env.connectionState {
        case .connected:  return "Connected"
        case .connecting: return "Connecting…"
        case .failed:     return "Disconnected"
        case .idle:       return "Idle"
        }
    }
}

private struct EmptyMainView: View {
    @Environment(AppEnvironment.self) private var env
    let onNewSession: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "cylinder.split.1x2")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)

            if env.sessions.isEmpty {
                Text("Welcome to MacHeidi")
                    .font(.title2.bold())
                Text("Create a connection to your MySQL server to get started.")
                    .foregroundStyle(.secondary)
                Button {
                    onNewSession()
                } label: {
                    Label("New Connection…", systemImage: "plus.circle.fill")
                }
                .controlSize(.large)
                .keyboardShortcut("n", modifiers: .command)
            } else {
                Text(L("welcome.title"))
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(L("welcome.subtitle"))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                Button {
                    onNewSession()
                } label: {
                    Label(L("welcome.openManager"), systemImage: "server.rack")
                }
                .controlSize(.large)
            }

            if case .failed(let msg) = env.connectionState {
                Text(msg)
                    .foregroundStyle(.red)
                    .padding(.top)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

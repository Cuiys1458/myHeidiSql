import SwiftUI

struct TabBarView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var env = env
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(env.openTabs) { tab in
                        TabChip(tab: tab,
                                isSelected: env.selectedTabId == tab.id,
                                onSelect: { env.selectedTabId = tab.id },
                                onClose: { env.closeTab(tab.id) })
                    }
                }
                .padding(.horizontal, 6)
            }
            Spacer()
            Button {
                env.openNewQueryTab()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
        }
        .frame(height: 28)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

private struct TabChip: View {
    let tab: WorkspaceTab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(tab.title)
                .font(.callout)
                .lineLimit(1)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private var icon: String {
        switch tab.kind {
        case .query: return "terminal"
        case .data:  return "tablecells"
        case .tableInfo: return "info.circle"
        }
    }
}

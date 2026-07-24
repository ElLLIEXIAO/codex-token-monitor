import SwiftUI
import WidgetKit

@main
struct CodexTokenApp: App {
    @State private var status = "正在读取本机 Codex 数据…"

    var body: some Scene {
        WindowGroup("Codex Token") {
            VStack(spacing: 16) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 48))
                    .foregroundStyle(.cyan)
                Text("Codex Token 小组件已安装")
                    .font(.title2.bold())
                Text("在桌面空白处右键，选择“编辑小组件”，搜索 Codex Token 后添加。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 360)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("立即刷新") {
                    refresh()
                }
            }
            .padding(36)
            .frame(minWidth: 460, minHeight: 280)
            .task {
                refresh()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(900))
                    refresh()
                }
            }
        }
    }

    private func refresh() {
        Task.detached {
            do {
                let snapshot = try CodexDataReader.read()
                try SnapshotCache.write(snapshot)
                WidgetCenter.shared.reloadAllTimelines()
                await MainActor.run {
                    status = "已刷新 · \(snapshot.refreshedAt.formatted(date: .omitted, time: .shortened))"
                }
            } catch {
                await MainActor.run { status = "读取失败：\(error.localizedDescription)" }
            }
        }
    }
}

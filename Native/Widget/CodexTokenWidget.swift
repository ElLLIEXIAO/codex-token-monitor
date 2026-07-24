import SwiftUI
import WidgetKit

struct TokenEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
    let error: String?
}

struct TokenProvider: TimelineProvider {
    func placeholder(in context: Context) -> TokenEntry {
        TokenEntry(date: .now, snapshot: .empty, error: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TokenEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TokenEntry>) -> Void) {
        let entry = load()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func load() -> TokenEntry {
        do {
            return TokenEntry(date: .now, snapshot: try SnapshotCache.read(), error: nil)
        } catch {
            return TokenEntry(date: .now, snapshot: .empty, error: "请打开 Codex Token 刷新")
        }
    }
}

struct CodexTokenWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TokenEntry

    var body: some View {
        VStack(spacing: 12) {
            header
            quota
            HStack(spacing: 10) {
                metric("账户累计", entry.snapshot.lifetimeTokens.formattedTokens)
                metric("今日消耗", entry.snapshot.todayTokens.formattedTokens)
            }
            if family == .systemLarge {
                activity
            }
            footer
        }
        .padding(16)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.25, blue: 0.48),
                    Color(red: 0.10, green: 0.18, blue: 0.35)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(entry.error == nil ? .mint : .orange).frame(width: 8, height: 8)
            Text("Codex Token").font(.headline)
            Spacer()
            Image(systemName: "gauge.with.dots.needle.67percent")
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    private var quota: some View {
        HStack(spacing: 16) {
            Gauge(value: entry.snapshot.remainingPercent ?? 0, in: 0...100) {
                Text("剩余")
            } currentValueLabel: {
                Text(entry.snapshot.remainingPercent.map { "\(Int($0.rounded()))%" } ?? "--")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(Gradient(colors: [.mint, .cyan]))
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text("剩余额度")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                Text(entry.snapshot.remainingPercent.map { "\(Int($0.rounded()))%" } ?? "--")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("官方未提供可换算的 Token 总额")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                Text("重置 \(entry.snapshot.resetLabel)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.6))
            Text(value).font(.system(size: 19, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var activity: some View {
        HStack(spacing: 10) {
            Image(systemName: "flame.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("当前最高消耗任务").font(.caption2).foregroundStyle(.white.opacity(0.6))
                Text(entry.snapshot.topActivity.name).font(.caption.bold()).lineLimit(1)
                Text(entry.snapshot.topActivity.detail).font(.caption2).foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Text(entry.snapshot.topActivity.tokens.formattedTokens).font(.headline)
        }
        .padding(10)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var footer: some View {
        HStack {
            if let error = entry.error {
                Text(error).foregroundStyle(.orange).lineLimit(1)
            } else {
                Text("低频刷新 · \(entry.snapshot.refreshedAt.formatted(date: .omitted, time: .shortened))")
            }
            Spacer()
            Text("本机 Codex")
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.55))
    }
}

@main
struct CodexTokenWidget: Widget {
    let kind = "CodexTokenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TokenProvider()) { entry in
            CodexTokenWidgetView(entry: entry)
        }
        .configurationDisplayName("Codex Token")
        .description("查看 Codex 当前额度、重置时间和 Token 用量。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

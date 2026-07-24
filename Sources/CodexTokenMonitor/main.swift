import AppKit
import Foundation
import SwiftUI

@main
struct CodexTokenMonitorApp: App {
    @StateObject private var model = UsageViewModel()

    var body: some Scene {
        WindowGroup("Codex Token") {
            TokenDashboard(model: model)
                .frame(width: 390, height: 430)
                .background(FloatingWindowConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 390, height: 430)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("立即刷新") { model.refresh() }
                    .keyboardShortcut("r")
            }
        }

        MenuBarExtra("Codex Token", systemImage: "gauge.with.dots.needle.67percent") {
            Text(model.statusText)
            Divider()
            Button("立即刷新") { model.refresh() }
            Button("退出小组件") { NSApplication.shared.terminate(nil) }
        }
    }
}

@MainActor
final class UsageViewModel: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot.empty
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var statusText: String {
        if let errorMessage { return "读取失败：\(errorMessage)" }
        if let remaining = snapshot.remainingPercent { return "额度剩余 \(Int(remaining.rounded()))%" }
        return "正在读取 Codex 用量"
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil

        Task {
            do {
                let fresh = try await Task.detached(priority: .utility) {
                    try CodexDataReader.read()
                }.value
                snapshot = fresh
            } catch {
                errorMessage = error.localizedDescription
            }
            isRefreshing = false
        }
    }
}

struct TokenDashboard: View {
    @ObservedObject var model: UsageViewModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.32), lineWidth: 0.8)
                }

            VStack(spacing: 16) {
                header
                quota
                HStack(spacing: 12) {
                    MetricCard(title: "账户累计", value: model.snapshot.lifetimeTokens.formattedTokens, caption: "官方账户统计")
                    MetricCard(title: "今日消耗", value: model.snapshot.todayTokens.formattedTokens, caption: "本地日期统计")
                }
                activity
                footer
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle().fill(model.errorMessage == nil ? Color.mint : Color.orange).frame(width: 8, height: 8)
            Text("Codex Token")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Spacer()
            Button { model.refresh() } label: {
                Image(systemName: model.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .rotationEffect(.degrees(model.isRefreshing ? 180 : 0))
                    .animation(.easeInOut(duration: 0.5), value: model.isRefreshing)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("立即刷新")
        }
    }

    private var quota: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 11)
                Circle()
                    .trim(from: 0, to: max(0.02, (model.snapshot.remainingPercent ?? 0) / 100))
                    .stroke(AngularGradient(colors: [.mint, .cyan, .blue], center: .center), style: StrokeStyle(lineWidth: 11, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text(model.snapshot.remainingPercent.map { "\(Int($0.rounded()))%" } ?? "--")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                    Text("额度剩余")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 94, height: 94)

            VStack(alignment: .leading, spacing: 8) {
                Text("当前额度窗口")
                    .font(.system(size: 14, weight: .medium))
                Text(model.snapshot.windowLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(model.snapshot.resetLabel, systemImage: "clock")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                if let error = model.errorMessage {
                    Text(error).font(.caption2).foregroundStyle(.orange).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var activity: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill").foregroundStyle(.orange).font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text("当前最高消耗任务")
                    .font(.caption).foregroundStyle(.secondary)
                Text(model.snapshot.topActivity.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(model.snapshot.topActivity.detail)
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(model.snapshot.topActivity.tokens.formattedTokens)
                .font(.system(size: 15, weight: .bold, design: .rounded))
        }
        .padding(13)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var footer: some View {
        HStack {
            Text("每 30 秒刷新 · \(model.snapshot.refreshedAt.formatted(date: .omitted, time: .shortened))")
            Spacer()
            Text("来自本机 Codex")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 21, weight: .bold, design: .rounded)).contentTransition(.numericText())
            Text(caption).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct FloatingWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isMovableByWindowBackground = true
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct UsageSnapshot: Sendable {
    var remainingPercent: Double?
    var usedPercent: Double?
    var resetAt: Date?
    var windowMinutes: Int?
    var lifetimeTokens: Int64?
    var todayTokens: Int64?
    var topActivity: ActivityUsage
    var refreshedAt: Date

    static let empty = UsageSnapshot(remainingPercent: nil, usedPercent: nil, resetAt: nil, windowMinutes: nil, lifetimeTokens: nil, todayTokens: nil, topActivity: .empty, refreshedAt: .now)

    var windowLabel: String {
        guard let usedPercent else { return "等待 Codex 返回官方额度" }
        if let windowMinutes { return "已用 \(Int(usedPercent.rounded()))% · \(windowMinutes / 60) 小时窗口" }
        return "已用 \(Int(usedPercent.rounded()))%"
    }

    var resetLabel: String {
        guard let resetAt else { return "下次重置时间待返回" }
        let relative = RelativeDateTimeFormatter()
        relative.locale = Locale(identifier: "zh_CN")
        return "\(resetAt.formatted(date: .abbreviated, time: .shortened))（\(relative.localizedString(for: resetAt, relativeTo: .now))）"
    }
}

struct ActivityUsage: Sendable {
    let name: String
    let detail: String
    let tokens: Int64?
    static let empty = ActivityUsage(name: "暂无可验证的活跃任务", detail: "近期本地会话尚未写入 Token 事件", tokens: nil)
}

private extension Optional where Wrapped == Int64 {
    var formattedTokens: String {
        guard let self else { return "--" }
        if self >= 1_000_000 { return String(format: "%.2fM", Double(self) / 1_000_000) }
        if self >= 1_000 { return String(format: "%.1fK", Double(self) / 1_000) }
        return "\(self)"
    }
}

private enum CodexDataReader {
    static let executable = "/Applications/ChatGPT.app/Contents/Resources/codex"

    static func read() throws -> UsageSnapshot {
        let payloads = try readAccountPayloads()
        let rateLimits = try decode(RateLimitsResponse.self, from: payloads.rateLimits)
        let usage = try decode(AccountUsageResponse.self, from: payloads.usage)
        let limit = rateLimits.rateLimitsByLimitId?["codex"] ?? rateLimits.rateLimits
        let window = limit.primary ?? limit.secondary
        let today = DateFormatter.codexDay.string(from: .now)
        let todayTokens = usage.dailyUsageBuckets?.first(where: { $0.startDate == today })?.tokens.value
        return UsageSnapshot(
            remainingPercent: window.map { max(0, 100 - $0.usedPercent) },
            usedPercent: window?.usedPercent,
            resetAt: window?.resetsAt.map(Date.init(timeIntervalSince1970:)),
            windowMinutes: window?.windowDurationMins,
            lifetimeTokens: usage.summary.lifetimeTokens?.value,
            todayTokens: todayTokens,
            topActivity: readTopActivity(),
            refreshedAt: .now
        )
    }

    private static func readAccountPayloads() throws -> (rateLimits: Data, usage: Data) {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw ReaderError.codexNotFound
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        let collector = ResponseCollector()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { collector.append(data) }
        }
        try process.run()
        try send(["method": "initialize", "id": 1, "params": ["clientInfo": ["name": "Codex Token Monitor", "title": "Codex Token Monitor", "version": "1.0"], "capabilities": NSNull()]], to: input.fileHandleForWriting)
        try send(["method": "account/rateLimits/read", "id": 2], to: input.fileHandleForWriting)
        try send(["method": "account/usage/read", "id": 3], to: input.fileHandleForWriting)

        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline && !collector.hasBothAccountResponses {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        guard let rateLimits = collector.response(for: 2), let usage = collector.response(for: 3) else {
            throw ReaderError.noResponse
        }
        return (rateLimits, usage)
    }

    private static func send(_ object: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    private static func readTopActivity() -> ActivityUsage {
        let calendar = Calendar.current
        let root = URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".codex/sessions/\(calendar.component(.year, from: .now))/\(String(format: "%02d", calendar.component(.month, from: .now)))/\(String(format: "%02d", calendar.component(.day, from: .now)))")
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return .empty }
        let recentFiles = files.filter { $0.pathExtension == "jsonl" }.filter {
            ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > Date().addingTimeInterval(-3 * 60 * 60)
        }
        var best: (tokens: Int64, name: String, date: Date)?
        for file in recentFiles {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            var lastTokens: Int64?
            for line in text.split(separator: "\n") {
                guard line.contains("\"type\":\"token_count\""), let data = line.data(using: .utf8), let event = try? JSONDecoder().decode(SessionTokenEvent.self, from: data) else { continue }
                lastTokens = event.payload.info.totalTokenUsage.totalTokens.value
            }
            guard let tokens = lastTokens else { continue }
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let shortID = file.deletingPathExtension().lastPathComponent.split(separator: "-").suffix(5).joined(separator: "-")
            if best == nil || tokens > best!.tokens { best = (tokens, "任务 \(shortID.prefix(12))", date) }
        }
        guard let best else { return .empty }
        let relative = RelativeDateTimeFormatter()
        relative.locale = Locale(identifier: "zh_CN")
        return ActivityUsage(name: best.name, detail: "近期活跃 · 最后更新\(relative.localizedString(for: best.date, relativeTo: .now))", tokens: best.tokens)
    }
}

private final class ResponseCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var responses: [Int: Data] = [:]

    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(data)
        while let newline = buffer.firstRange(of: Data([0x0A])) {
            let line = buffer[..<newline.lowerBound]
            buffer.removeSubrange(...newline.lowerBound)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let id = object["id"] as? Int, let result = object["result"], let resultData = try? JSONSerialization.data(withJSONObject: result) else { continue }
            responses[id] = resultData
        }
    }

    var hasBothAccountResponses: Bool {
        lock.lock(); defer { lock.unlock() }
        return responses[2] != nil && responses[3] != nil
    }

    func response(for id: Int) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return responses[id]
    }
}

private enum ReaderError: LocalizedError {
    case codexNotFound
    case noResponse
    var errorDescription: String? {
        switch self {
        case .codexNotFound: return "未找到 ChatGPT 内置 Codex"
        case .noResponse: return "Codex 未在 12 秒内返回用量"
        }
    }
}

private struct RateLimitsResponse: Decodable {
    let rateLimits: RateLimitSnapshot
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?
}
private struct RateLimitSnapshot: Decodable {
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
}
private struct RateLimitWindow: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: TimeInterval?
}
private struct AccountUsageResponse: Decodable {
    let summary: AccountUsageSummary
    let dailyUsageBuckets: [DailyUsageBucket]?
}
private struct AccountUsageSummary: Decodable { let lifetimeTokens: FlexibleInt? }
private struct DailyUsageBucket: Decodable { let startDate: String; let tokens: FlexibleInt }
private struct SessionTokenEvent: Decodable {
    let payload: SessionTokenPayload
}
private struct SessionTokenPayload: Decodable { let info: SessionTokenInfo }
private struct SessionTokenInfo: Decodable {
    enum CodingKeys: String, CodingKey { case totalTokenUsage = "total_token_usage" }
    let totalTokenUsage: TokenUsage
}
private struct TokenUsage: Decodable {
    enum CodingKeys: String, CodingKey { case totalTokens = "total_tokens" }
    let totalTokens: FlexibleInt
}
private struct FlexibleInt: Decodable, Sendable {
    let value: Int64
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int64.self) { value = int }
        else if let string = try? container.decode(String.self), let int = Int64(string) { value = int }
        else if let double = try? container.decode(Double.self) { value = Int64(double) }
        else { throw DecodingError.typeMismatch(Int64.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected token count")) }
    }
}
private extension DateFormatter {
    static let codexDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

import Foundation

struct UsageSnapshot: Codable, Sendable {
    var remainingPercent: Double?
    var resetAt: Date?
    var windowMinutes: Int?
    var lifetimeTokens: Int64?
    var todayTokens: Int64?
    var topActivity: ActivityUsage
    var refreshedAt: Date

    static let empty = UsageSnapshot(
        remainingPercent: nil,
        resetAt: nil,
        windowMinutes: nil,
        lifetimeTokens: nil,
        todayTokens: nil,
        topActivity: .empty,
        refreshedAt: .now
    )

    var resetLabel: String {
        guard let resetAt else { return "等待重置时间" }
        return resetAt.formatted(date: .abbreviated, time: .shortened)
    }
}

struct ActivityUsage: Codable, Sendable {
    let name: String
    let detail: String
    let tokens: Int64?

    static let empty = ActivityUsage(
        name: "暂无活跃任务",
        detail: "尚未读取到 Token 事件",
        tokens: nil
    )
}

enum SnapshotCache {
    private static let extensionBundleID = "com.ellie.CodexToken.Widget"

    static func read() throws -> UsageSnapshot {
        let data = try Data(contentsOf: cacheURL(forWidget: true))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(UsageSnapshot.self, from: data)
    }

    static func write(_ snapshot: UsageSnapshot) throws {
        let url = cacheURL(forWidget: false)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    private static func cacheURL(forWidget: Bool) -> URL {
        let root: URL
        if forWidget {
            root = FileManager.default.homeDirectoryForCurrentUser
        } else {
            root = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Containers/\(extensionBundleID)/Data")
        }
        return root.appending(path: "Library/Application Support/CodexToken/snapshot.json")
    }
}

extension Optional where Wrapped == Int64 {
    var formattedTokens: String {
        guard let self else { return "--" }
        if self >= 1_000_000_000 { return String(format: "%.2fB", Double(self) / 1_000_000_000) }
        if self >= 1_000_000 { return String(format: "%.2fM", Double(self) / 1_000_000) }
        if self >= 1_000 { return String(format: "%.1fK", Double(self) / 1_000) }
        return "\(self)"
    }
}

enum CodexDataReader {
    private static let executable = "/Applications/ChatGPT.app/Contents/Resources/codex"

    static func read() throws -> UsageSnapshot {
        let payloads = try readAccountPayloads()
        let rateLimits = try JSONDecoder().decode(RateLimitsResponse.self, from: payloads.rateLimits)
        let usage = try JSONDecoder().decode(AccountUsageResponse.self, from: payloads.usage)
        let limit = rateLimits.rateLimitsByLimitId?["codex"] ?? rateLimits.rateLimits
        let window = limit.primary ?? limit.secondary
        let today = DateFormatter.codexDay.string(from: .now)
        return UsageSnapshot(
            remainingPercent: window.map { max(0, 100 - $0.usedPercent) },
            resetAt: window?.resetsAt.map(Date.init(timeIntervalSince1970:)),
            windowMinutes: window?.windowDurationMins,
            lifetimeTokens: usage.summary.lifetimeTokens?.value,
            todayTokens: usage.dailyUsageBuckets?.first(where: { $0.startDate == today })?.tokens.value,
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
        try send([
            "method": "initialize",
            "id": 1,
            "params": [
                "clientInfo": [
                    "name": "Codex Token Widget",
                    "title": "Codex Token Widget",
                    "version": "2.0"
                ],
                "capabilities": NSNull()
            ]
        ], to: input.fileHandleForWriting)
        try send(["method": "account/rateLimits/read", "id": 2], to: input.fileHandleForWriting)
        try send(["method": "account/usage/read", "id": 3], to: input.fileHandleForWriting)

        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline && !collector.hasBothResponses {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }

        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        guard let rateLimits = collector.response(for: 2),
              let usage = collector.response(for: 3) else {
            throw ReaderError.noResponse
        }
        return (rateLimits, usage)
    }

    private static func send(_ object: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }

    private static func readTopActivity() -> ActivityUsage {
        let calendar = Calendar.current
        let dayPath = String(
            format: ".codex/sessions/%04d/%02d/%02d",
            calendar.component(.year, from: .now),
            calendar.component(.month, from: .now),
            calendar.component(.day, from: .now)
        )
        let root = URL(fileURLWithPath: NSHomeDirectory()).appending(path: dayPath)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return .empty }

        var best: (tokens: Int64, name: String, date: Date)?
        for file in files where file.pathExtension == "jsonl" {
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            guard date > Date().addingTimeInterval(-3 * 60 * 60),
                  let text = try? String(contentsOf: file, encoding: .utf8) else { continue }

            var lastTokens: Int64?
            for line in text.split(separator: "\n") where line.contains("\"type\":\"token_count\"") {
                guard let data = line.data(using: .utf8),
                      let event = try? JSONDecoder().decode(SessionTokenEvent.self, from: data) else { continue }
                lastTokens = event.payload.info.totalTokenUsage.totalTokens.value
            }
            guard let tokens = lastTokens else { continue }
            let shortID = file.deletingPathExtension().lastPathComponent.suffix(12)
            if best == nil || tokens > best!.tokens {
                best = (tokens, "任务 \(shortID)", date)
            }
        }

        guard let best else { return .empty }
        let relative = RelativeDateTimeFormatter()
        relative.locale = Locale(identifier: "zh_CN")
        return ActivityUsage(
            name: best.name,
            detail: "更新于\(relative.localizedString(for: best.date, relativeTo: .now))",
            tokens: best.tokens
        )
    }
}

private final class ResponseCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var responses: [Int: Data] = [:]

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        while let newline = buffer.firstRange(of: Data([0x0A])) {
            let line = buffer[..<newline.lowerBound]
            buffer.removeSubrange(...newline.lowerBound)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = object["id"] as? Int,
                  let result = object["result"],
                  let resultData = try? JSONSerialization.data(withJSONObject: result) else { continue }
            responses[id] = resultData
        }
    }

    var hasBothResponses: Bool {
        lock.lock()
        defer { lock.unlock() }
        return responses[2] != nil && responses[3] != nil
    }

    func response(for id: Int) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return responses[id]
    }
}

private enum ReaderError: LocalizedError {
    case codexNotFound
    case noResponse

    var errorDescription: String? {
        switch self {
        case .codexNotFound: "未找到 ChatGPT 内置 Codex"
        case .noResponse: "Codex 未返回用量数据"
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

private struct AccountUsageSummary: Decodable {
    let lifetimeTokens: FlexibleInt?
}

private struct DailyUsageBucket: Decodable {
    let startDate: String
    let tokens: FlexibleInt
}

private struct SessionTokenEvent: Decodable {
    let payload: SessionTokenPayload
}

private struct SessionTokenPayload: Decodable {
    let info: SessionTokenInfo
}

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
        else {
            throw DecodingError.typeMismatch(
                Int64.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected token count")
            )
        }
    }
}

private extension DateFormatter {
    static let codexDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // account/usage/read groups daily buckets by UTC date.
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

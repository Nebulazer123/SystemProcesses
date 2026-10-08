import Foundation

struct UsageTotals: Codable {
    var requests = 0
    var completed = 0
    var inputTokens = 0
    var outputTokens = 0
    var reasoningTokens = 0
    var tokenReports = 0
}
struct UsageLedger: Codable {
    // This read status is not persisted: a damaged ledger must remain available
    // for recovery, rather than being overwritten by manual request accounting.
    var automaticUsageAvailable = true
    var automaticCount = 0
    var automaticDay: Date? = nil
    var lastAutomatic: Date? = nil
    var providers: [String: UsageTotals] = [:]
    enum CodingKeys: String, CodingKey { case automaticCount, automaticDay, lastAutomatic, providers }
    static var path: URL { URL(fileURLWithPath: CONFIG_DIR).appendingPathComponent("usage.json") }
    static func load(at url: URL = path) -> UsageLedger {
        do {
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            let data = try file.read(upToCount: 65_537) ?? Data()
            guard data.count <= 65_536 else { throw CocoaError(.fileReadCorruptFile) }
            let value = try JSONDecoder().decode(Self.self, from: data)
            guard value.providers.count <= 32, value.providers.keys.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 64 }), value.automaticCount >= 0, value.automaticCount <= 1_000_000_000, value.providers.values.allSatisfy({
                (0...1_000_000_000).contains($0.requests) && (0...1_000_000_000).contains($0.completed) && (0...1_000_000_000).contains($0.tokenReports) &&
                (0...1_000_000_000_000).contains($0.inputTokens) && (0...1_000_000_000_000).contains($0.outputTokens) && (0...1_000_000_000_000).contains($0.reasoningTokens)
            }) else { throw CocoaError(.fileReadCorruptFile) }
            return value
        } catch {
            let error = error as NSError
            if (error.domain == NSCocoaErrorDomain && [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(error.code)) || (error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT)) { return .init() }
            var unavailable = UsageLedger(); unavailable.automaticUsageAvailable = false
            return unavailable
        }
    }
    @discardableResult
    func save() -> Bool {
        guard automaticUsageAvailable else { return false }
        do {
            let data = try JSONEncoder().encode(self)
            try FileManager.default.createDirectory(atPath: CONFIG_DIR, withIntermediateDirectories: true)
            try data.write(to: Self.path, options: .atomic)
            return true
        } catch { return false }
    }
    mutating func attempted(provider: String) {
        var total = providers[provider] ?? UsageTotals(); total.requests += 1; providers[provider] = total; save()
    }
    mutating func completed(provider: String, usage: AIUsage?) {
        var total = providers[provider] ?? UsageTotals(); total.completed += 1
        if let usage = usage {
            total.inputTokens += Self.validTokens(usage.inputTokens) ?? 0
            total.outputTokens += Self.validTokens(usage.outputTokens) ?? 0
            total.reasoningTokens += Self.validTokens(usage.reasoningTokens) ?? 0
            if Self.validTokens(usage.inputTokens) != nil || Self.validTokens(usage.outputTokens) != nil { total.tokenReports += 1 }
        }
        providers[provider] = total; save()
    }
    static func validTokens(_ value: Int?) -> Int? { guard let value = value, (0...1_000_000).contains(value) else { return nil }; return value }
    var summary: String {
        let requests = providers.values.reduce(0) { $0+$1.requests }
        let tokens = providers.values.reduce(0) { $0+$1.inputTokens+$1.outputTokens }
        return "App requests: \(requests) · reported tokens: \(tokens). Account limits unavailable."
            + (automaticUsageAvailable ? "" : " Automatic analysis paused: usage history unavailable.")
    }
}

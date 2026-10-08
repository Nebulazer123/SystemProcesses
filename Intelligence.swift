import Foundation
import CryptoKit

// Lightweight, in-memory evidence collection. This module intentionally makes
// recommendations only; process termination remains outside its responsibility.
struct ProcessIdentity: Hashable, Comparable {
    let pid: Int32
    let startTime: Date

    init(pid: Int32, startTime: Date) {
        self.pid = pid
        self.startTime = startTime
    }

    init(_ process: ProcInfo) {
        self.init(pid: Int32(process.pid), startTime: process.startTime)
    }

    static func < (lhs: ProcessIdentity, rhs: ProcessIdentity) -> Bool {
        if lhs.pid != rhs.pid { return lhs.pid < rhs.pid }
        return lhs.startTime < rhs.startTime
    }

    var stableKey: String {
        "\(pid):\(Int64((startTime.timeIntervalSince1970 * 1_000_000).rounded()))"
    }
}

struct ProcessEvidence {
    let owner: String?
    let ancestry: [String]
    let activeDevelopment: Bool
    let memoryGrowth: Bool
    let growthBytes: UInt64
    let observationSeconds: Double
    let parentExited: Bool
    let knownAbandoned: Bool
    let cpuSampleValid: Bool

    init(owner: String?, ancestry: [String], activeDevelopment: Bool,
         memoryGrowth: Bool, growthBytes: UInt64, observationSeconds: Double,
         parentExited: Bool, knownAbandoned: Bool = false, cpuSampleValid: Bool) {
        self.owner = owner
        self.ancestry = ancestry
        self.activeDevelopment = activeDevelopment
        self.memoryGrowth = memoryGrowth
        self.growthBytes = growthBytes
        self.observationSeconds = observationSeconds
        self.parentExited = parentExited
        // No currently collected fact is enough to establish abandonment.
        self.knownAbandoned = false
        self.cpuSampleValid = cpuSampleValid
    }
}

final class ProcessIntelligence {
    static let maximumProcesses = 512
    static let maximumSamplesPerProcess = 240
    static let sampleInterval: TimeInterval = 15
    static let historyWindow: TimeInterval = 60 * 60
    static let growthWindow: TimeInterval = 5 * 60
    static let minimumGrowthBytes: UInt64 = 256 * 1024 * 1024

    private struct Sample {
        let time: Date
        let residentBytes: UInt64
        let cpuPct: Double
        let cpuValid: Bool
    }

    private struct Record {
        var lastSeen: Date
        var name: String
        var owner: String?
        var executablePath: String?
        var executableFileID: String?
        var ppid: Int32
        var observedParent: ProcessIdentity?
        var parentExited = false
        var ancestry: [String] = []
        var activeDevelopment = false
        var latestCPUValid = false
        var samples: [Sample] = []
    }

    private var records: [ProcessIdentity: Record] = [:]
    private var insertionOrder: [ProcessIdentity] = []

    var retainedProcessCount: Int { records.count }
    func sampleCount(for identity: ProcessIdentity) -> Int { records[identity]?.samples.count ?? 0 }

    func reset() {
        records.removeAll(keepingCapacity: false)
        insertionOrder.removeAll(keepingCapacity: false)
    }

    func ingest(_ procs: [ProcInfo], now: Date = Date()) {
        // Keep the full current snapshot briefly for parent resolution, but retain histories
        // only for high-RSS processes and already observed processes with rising memory.
        let bounded = selectedHistoryProcesses(procs)
        let byPID = Dictionary(procs.map { (Int32($0.pid), $0) }, uniquingKeysWith: { first, _ in first })
        let identities = Dictionary(procs.map { (Int32($0.pid), ProcessIdentity($0)) }, uniquingKeysWith: { first, _ in first })
        let activeIdentities = Set(identities.values)
        let selectedIdentities = Set(bounded.map(ProcessIdentity.init))

        for process in bounded {
            let identity = ProcessIdentity(process)
            var record = records[identity] ?? Record(lastSeen: now, name: process.name,
                owner: nil, executablePath: nil, executableFileID: nil, ppid: Int32(process.ppid))
            if records[identity] == nil { insertionOrder.append(identity) }

            let newPath = nonempty(process.executablePath)
            let newFileID = nonempty(process.executableFileID)
            let executableChanged = (newPath != nil && record.executablePath != nil && newPath != record.executablePath)
                || (newFileID != nil && record.executableFileID != nil && newFileID != record.executableFileID)
            if executableChanged {
                record.owner = nil
                record.ancestry = []
                record.activeDevelopment = false
                record.observedParent = nil
                record.parentExited = false
                // A PID that execs a different binary is a new measurement baseline too.
                record.samples.removeAll(keepingCapacity: false)
            }

            record.lastSeen = now
            record.name = process.name
            record.ppid = Int32(process.ppid)
            record.latestCPUValid = process.cpuSampleValid
            if let suppliedOwner = process.ownerName?.trimmingCharacters(in: .whitespacesAndNewlines), !suppliedOwner.isEmpty {
                record.owner = suppliedOwner
            } else if let path = nonempty(process.executablePath), let pathOwner = verifiedOwner(forExecutablePath: path) {
                record.owner = pathOwner
            }
            if let path = newPath { record.executablePath = path }
            if let fileID = newFileID { record.executableFileID = fileID }

            if process.ramBytes > 0 {
                let sample = Sample(time: now, residentBytes: process.ramBytes,
                                    cpuPct: process.cpuPct, cpuValid: process.cpuSampleValid)
                if let last = record.samples.last {
                    if now.timeIntervalSince(last.time) >= Self.sampleInterval {
                        record.samples.append(sample)
                    }
                } else {
                    record.samples.append(sample)
                }
            }
            trim(&record, now: now)

            if let parent = identities[Int32(process.ppid)] {
                if record.observedParent == nil { record.observedParent = parent }
                if let previousParent = record.observedParent, previousParent != parent,
                   !activeIdentities.contains(previousParent) { record.parentExited = true }
            } else if let parent = record.observedParent, !activeIdentities.contains(parent) {
                // Keep this as historical evidence only. It never implies the child is abandoned.
                record.parentExited = true
            }
            records[identity] = record
        }

        // Build ancestry from observed process identities. Names are useful for display,
        // but only verified app ownership or executable identity affects activeDevelopment.
        for process in bounded {
            let identity = ProcessIdentity(process)
            guard var record = records[identity] else { continue }
            var chain: [String] = []
            var verifiedOwners: [String] = []
            var seen = Set<ProcessIdentity>([identity])
            var parentPID = Int32(process.ppid)
            var depth = 0
            while depth < 32, let parentIdentity = identities[parentPID],
                  !seen.contains(parentIdentity), let parentProcess = byPID[parentPID] {
                seen.insert(parentIdentity)
                chain.append(parentProcess.name)
                if let owner = verifiedOwner(for: parentProcess) { verifiedOwners.append(owner) }
                parentPID = Int32(parentProcess.ppid)
                depth += 1
            }
            if record.parentExited, !record.ancestry.isEmpty {
                chain.append(contentsOf: record.ancestry)
            }
            if chain.isEmpty, let priorParent = record.observedParent,
               let formerParent = records[priorParent] {
                chain.append(formerParent.name)
                if let owner = formerParent.owner { verifiedOwners.append(owner) }
                chain.append(contentsOf: formerParent.ancestry)
            } else if chain.isEmpty, record.observedParent != nil {
                // The parent's metadata may have been observed in the full process snapshot
                // without retaining a separate history entry for that parent.
                chain = record.ancestry
                if let owner = record.owner { verifiedOwners.append(owner) }
            }
            record.ancestry = Array(chain.prefix(32))
            let directOwner = verifiedOwner(for: process) ?? record.owner
            record.owner = directOwner ?? verifiedOwners.first ?? record.owner
            record.activeDevelopment = record.activeDevelopment || isDevelopmentOwner(directOwner)
                || verifiedOwners.contains(where: isDevelopmentOwner)
            records[identity] = record
        }

        // Retain exited processes' bounded numeric history for up to one hour, then evict.
        for identity in insertionOrder where !selectedIdentities.contains(identity) {
            guard var record = records[identity] else { continue }
            trim(&record, now: now)
            records[identity] = record
            if now.timeIntervalSince(record.lastSeen) > Self.historyWindow { records.removeValue(forKey: identity) }
        }
        insertionOrder.removeAll { records[$0] == nil }
        while insertionOrder.count > Self.maximumProcesses {
            let index = insertionOrder.firstIndex(where: { !selectedIdentities.contains($0) }) ?? 0
            let oldest = insertionOrder.remove(at: index)
            records.removeValue(forKey: oldest)
        }
    }

    private func selectedHistoryProcesses(_ procs: [ProcInfo]) -> [ProcInfo] {
        guard procs.count > Self.maximumProcesses else { return procs }
        let trendCapacity = Self.maximumProcesses / 4
        let rising = procs.compactMap { process -> (ProcInfo, UInt64)? in
            guard let last = records[ProcessIdentity(process)]?.samples.last,
                  process.ramBytes > last.residentBytes else { return nil }
            return (process, process.ramBytes - last.residentBytes)
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.ramBytes > $1.0.ramBytes
        }
        var selected = Set(rising.prefix(trendCapacity).map { ProcessIdentity($0.0) })
        let byRSS = procs.sorted {
            if $0.ramBytes != $1.ramBytes { return $0.ramBytes > $1.ramBytes }
            return $0.pid < $1.pid
        }
        for process in byRSS where selected.count < Self.maximumProcesses {
            selected.insert(ProcessIdentity(process))
        }
        return procs.filter { selected.contains(ProcessIdentity($0)) }
    }

    func evidence(for process: ProcInfo, now: Date = Date()) -> ProcessEvidence {
        let identity = ProcessIdentity(process)
        guard let record = records[identity] else {
            let directOwner = verifiedOwner(for: process)
            return ProcessEvidence(owner: directOwner, ancestry: [],
                activeDevelopment: isDevelopmentOwner(directOwner), memoryGrowth: false,
                growthBytes: 0, observationSeconds: 0, parentExited: false,
                knownAbandoned: false, cpuSampleValid: process.cpuSampleValid)
        }
        let growth = growthAssessment(record.samples, now: now)
        return ProcessEvidence(owner: record.owner, ancestry: record.ancestry,
            activeDevelopment: record.activeDevelopment, memoryGrowth: growth.detected,
            growthBytes: growth.bytes, observationSeconds: growth.duration,
            parentExited: record.parentExited, knownAbandoned: false,
            cpuSampleValid: process.cpuSampleValid)
    }

    private func trim(_ record: inout Record, now: Date) {
        record.samples.removeAll { now.timeIntervalSince($0.time) > Self.historyWindow }
        if record.samples.count > Self.maximumSamplesPerProcess {
            record.samples.removeFirst(record.samples.count - Self.maximumSamplesPerProcess)
        }
    }

    private func growthAssessment(_ samples: [Sample], now: Date) -> (detected: Bool, bytes: UInt64, duration: Double) {
        let observed = max(0, (samples.last?.time.timeIntervalSince(samples.first?.time ?? now)) ?? 0)
        guard samples.count >= 5, let last = samples.last else { return (false, 0, observed) }
        // Compare the most recent observation with a sample at least five minutes earlier,
        // rather than allowing a slow rise over the entire one-hour retention window.
        guard let first = samples.last(where: { $0.time <= last.time.addingTimeInterval(-Self.growthWindow) }) else {
            return (false, 0, observed)
        }
        let duration = last.time.timeIntervalSince(first.time)
        guard duration >= Self.growthWindow, now.timeIntervalSince(last.time) <= Self.sampleInterval * 2,
              last.residentBytes > first.residentBytes else { return (false, 0, max(0, duration)) }
        let growth = last.residentBytes - first.residentBytes
        let percent = Double(growth) / Double(max(first.residentBytes, 1)) * 100
        return (growth >= Self.minimumGrowthBytes && percent >= 25, growth, duration)
    }

    private func verifiedOwner(for process: ProcInfo) -> String? {
        if let owner = process.ownerName?.trimmingCharacters(in: .whitespacesAndNewlines), !owner.isEmpty { return owner }
        guard !process.executableFileID.isEmpty, let path = nonempty(process.executablePath) else { return nil }
        return verifiedOwner(forExecutablePath: path)
    }

    private func verifiedOwner(forExecutablePath path: String) -> String? {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        let known: [(String, String)] = [
            ("/Codex.app/", "Codex"), ("/Claude.app/", "Claude"),
            ("/OpenCode.app/", "OpenCode"), ("/Visual Studio Code.app/", "Visual Studio Code"),
            ("/Cursor.app/", "Cursor"), ("/Terminal.app/", "Terminal"),
            ("/iTerm.app/", "iTerm"), ("/Xcode.app/", "Xcode"),
            ("/UnrealEditor.app/", "Unreal Editor")
        ]
        return known.first { standardized.localizedCaseInsensitiveContains($0.0) }?.1
    }

    private func isDevelopmentOwner(_ owner: String?) -> Bool {
        guard let owner else { return false }
        let name = owner.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().replacingOccurrences(of: ".app", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let knownDevelopmentOwners: Set<String> = [
            "codex", "codex app", "codex desktop",
            "claude", "claude desktop",
            "opencode", "opencode go",
            "visual studio code", "visual studio code insiders",
            "cursor", "cursor editor",
            "terminal", "macos terminal",
            "iterm", "iterm2",
            "ghostty", "warp",
            "xcode", "xcode beta",
            "unreal editor", "unreal engine", "unrealeditor"
        ]
        return knownDevelopmentOwners.contains(name)
    }

    private func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct AutomaticAnalysisPolicy {
    static let cooldown: TimeInterval = 10 * 60
    static let pressureDuration: TimeInterval = 30
    static let largeProcessDuration: TimeInterval = 120
    static let dailyLimit = 6
    static let largeProcessBytes: UInt64 = 1024 * 1024 * 1024

    private(set) var requestsIssuedToday = 0
    private(set) var lastIssuedAt: Date?
    private var day: Date?
    private var pressureBeganAt: Date?
    private var largeBeganAt: [ProcessIdentity: Date] = [:]

    mutating func reset() {
        requestsIssuedToday = 0
        lastIssuedAt = nil
        day = nil
        pressureBeganAt = nil
        largeBeganAt.removeAll()
    }

    mutating func restore(count: Int, lastIssuedAt savedLastIssuedAt: Date?, day savedDay: Date?, now: Date = Date()) {
        self.lastIssuedAt = nil
        requestsIssuedToday = 0
        day = nil
        pressureBeganAt = nil
        largeBeganAt.removeAll()
        guard let savedDay else { return }
        let today = Calendar.current.startOfDay(for: now)
        guard Calendar.current.startOfDay(for: savedDay) == today else { return }
        day = today
        requestsIssuedToday = min(max(count, 0), Self.dailyLimit)
        self.lastIssuedAt = savedLastIssuedAt
    }

    /// A true result reserves the request immediately. Call it only when the provider is
    /// enabled and ready to issue one request; failures still consume cooldown and daily cap.
    mutating func shouldAnalyze(procs: [ProcInfo], evidence: [ProcessIdentity: ProcessEvidence],
                                pressure: MemPressure, now: Date = Date(),
                                providerIsApple: Bool = false) -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        if day == nil || day != today {
            day = today
            requestsIssuedToday = 0
        }

        if pressure == .elevated || pressure == .critical {
            if pressureBeganAt == nil { pressureBeganAt = now }
        } else {
            pressureBeganAt = nil
        }

        let activeIdentities = Set(procs.map(ProcessIdentity.init))
        largeBeganAt = largeBeganAt.filter { activeIdentities.contains($0.key) }
        for process in procs {
            let identity = ProcessIdentity(process)
            if process.ramBytes >= Self.largeProcessBytes {
                if largeBeganAt[identity] == nil { largeBeganAt[identity] = now }
            } else {
                largeBeganAt.removeValue(forKey: identity)
            }
        }

        guard requestsIssuedToday < Self.dailyLimit,
              lastIssuedAt.map({ now.timeIntervalSince($0) >= Self.cooldown }) ?? true else { return false }

        // On-device inference is deferred while pressure is elevated or critical.
        if providerIsApple && (pressure == .elevated || pressure == .critical) { return false }

        let sustainedPressure = pressureBeganAt.map { now.timeIntervalSince($0) >= Self.pressureDuration } ?? false
        let sustainedGrowth = evidence.values.contains(where: \.memoryGrowth)
        let contextualGrowth = evidence.values.contains(where: \.memoryGrowth)
        let sustainedLarge = largeBeganAt.values.contains { now.timeIntervalSince($0) >= Self.largeProcessDuration }
        let pressureContext = pressure == .elevated || pressure == .critical
        let largeWithContext = sustainedLarge && (pressureContext || contextualGrowth)
        guard sustainedPressure || sustainedGrowth || largeWithContext else { return false }

        lastIssuedAt = now
        requestsIssuedToday += 1
        return true
    }
}

func analysisAgeBand(_ process: ProcInfo, now: Date = Date()) -> String {
    let age = now.timeIntervalSince(process.startTime)
    if age < 2 * 60 { return "new" }
    if age < 60 * 60 { return "recent" }
    return "longRunning"
}

func analysisSnapshotHash(procs: [ProcInfo], evidence: [ProcessIdentity: ProcessEvidence],
                          pressure: MemPressure, ignored: Set<ProcessIdentity> = [],
                          protected: Set<ProcessIdentity> = [], now: Date = Date()) -> String {
    let pressureKey: String
    switch pressure {
    case .healthy: pressureKey = "healthy"
    case .elevated: pressureKey = "elevated"
    case .critical: pressureKey = "critical"
    case .unavailable: pressureKey = "unavailable"
    @unknown default: pressureKey = "unknown"
    }

    let entries = procs.map { process -> String in
        let identity = ProcessIdentity(process)
        let sample = evidence[identity]
        let memoryBucket = process.ramBytes / (64 * 1024 * 1024)
        let cpuKnown = process.cpuSampleValid
        let cpuActivity = cpuKnown && process.cpuPct.isFinite && process.cpuPct > 1
        let ancestry = sample?.ancestry.joined(separator: ">") ?? ""
        let growthBucket = (sample?.growthBytes ?? 0) / (64 * 1024 * 1024)
        let pathHash = process.executablePath.isEmpty ? "" : stableDigest(process.executablePath)
        return [identity.stableKey, process.name, String(memoryBucket), String(cpuKnown), String(cpuActivity),
                process.executableFileID, pathHash, process.type.rawValue, analysisAgeBand(process, now: now),
                process.isProtected || protected.contains(identity) ? "protected" : "ordinary",
                ignored.contains(identity) ? "ignored" : "visible",
                sample?.owner ?? "?", ancestry, sample?.activeDevelopment == true ? "dev" : "",
                sample?.memoryGrowth == true ? "growth" : "", String(growthBucket),
                sample?.parentExited == true ? "parent-exited" : ""]
            .map { "\($0.utf8.count):\($0)" }.joined()
    }.sorted()
    let normalized = ([pressureKey] + entries).map { "\($0.utf8.count):\($0)" }.joined()

    return stableDigest(normalized)
}

/// SHA-256 is used for opaque local preference keys and request deduplication.
/// It is not an authentication or signature mechanism.
func stableDigest(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}

final class AnalysisResultCache {
    static let lifetime: TimeInterval = 10 * 60
    static let maximumEntries = 64
    private struct Entry { let data: Data; let storedAt: Date }
    private var entries: [String: Entry] = [:]
    private var order: [String] = []

    var count: Int { entries.count }

    func value(for hash: String, now: Date = Date()) -> Data? {
        guard let entry = entries[hash] else { return nil }
        guard now.timeIntervalSince(entry.storedAt) >= 0,
              now.timeIntervalSince(entry.storedAt) <= Self.lifetime else {
            entries.removeValue(forKey: hash)
            order.removeAll { $0 == hash }
            return nil
        }
        return entry.data
    }

    func store(_ data: Data, for hash: String, now: Date = Date()) {
        entries[hash] = Entry(data: data, storedAt: now)
        order.removeAll { $0 == hash }
        order.append(hash)
        while order.count > Self.maximumEntries {
            entries.removeValue(forKey: order.removeFirst())
        }
    }

    func removeAll() {
        entries.removeAll(keepingCapacity: false)
        order.removeAll(keepingCapacity: false)
    }
}

import Foundation

func intelligenceChecks(_ check: (Bool, String) -> Void) {
    func process(_ pid: Int32, _ name: String = "worker", _ bytes: UInt64 = 500_000_000,
                 _ start: TimeInterval = 1, _ ppid: Int32 = 1, path: String = "",
                 owner: String? = nil, cpuValid: Bool = false, cpu: Double = 0,
                 executableID: String = "", type: ProcessType = .background) -> ProcInfo {
        ProcInfo(pid: pid, name: name, ramBytes: bytes, cpuPct: cpu, icon: nil,
                 type: type, isProtected: false, threads: 1,
                 startTime: Date(timeIntervalSince1970: start), ppid: ppid, childCount: 0,
                 executablePath: path, cpuSampleValid: cpuValid, footprintBytes: nil, ownerName: owner,
                 executableFileID: executableID)
    }
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    let shortHistory = ProcessIntelligence()
    let observedProcess = process(699, "worker", 500_000_000)
    for seconds in stride(from: 0, through: 180, by: 15) { shortHistory.ingest([observedProcess], now: t0.addingTimeInterval(Double(seconds))) }
    let observedEvidence = shortHistory.evidence(for: observedProcess, now: t0.addingTimeInterval(180))
    check(observedEvidence.observationSeconds == 180 && !observedEvidence.memoryGrowth, "Three minutes of history is reported accurately without a growth conclusion")

    // A verified application identity is inherited through observed ancestry.
    let intelligence = ProcessIntelligence()
    let parent = process(700, "Codex", 900_000_000, 700, 1,
                         path: "/Applications/Codex.app/Contents/MacOS/Codex", executableID: "dev:700")
    let child = process(701, "node", 800_000_000, 701, 700, path: "/opt/homebrew/bin/node")
    intelligence.ingest([parent, child], now: t0)
    let childEvidence = intelligence.evidence(for: child, now: t0)
    check(childEvidence.activeDevelopment && childEvidence.owner == "Codex" && childEvidence.ancestry.contains("Codex"),
          "verified app ownership passes down observed process ancestry")
    check(!childEvidence.knownAbandoned, "ordinary parent/owner history never claims abandonment")

    let spoofed = process(702, "claude", 800_000_000, 702, 1, path: "/tmp/claude")
    intelligence.ingest([spoofed], now: t0.addingTimeInterval(15))
    let spoofedEvidence = intelligence.evidence(for: spoofed, now: t0.addingTimeInterval(15))
    check(!spoofedEvidence.activeDevelopment && spoofedEvidence.owner == nil,
          "a process name alone does not establish development ownership")

    let codexBar = process(704, "CodexBar", 400_000_000, 704, owner: "CodexBar")
    check(!intelligence.evidence(for: codexBar, now: t0).activeDevelopment,
          "CodexBar is not mistaken for the Codex development app")
    for (offset, owner) in ["Codex", "Codex.app", "Claude", "Terminal", "OpenCode", "Xcode", "Unreal Editor", "Ghostty", "Warp"].enumerated() {
        let app = process(Int32(710 + offset), "helper", 100_000_000, Double(710 + offset), owner: owner)
        check(intelligence.evidence(for: app, now: t0).activeDevelopment,
              "known development owner \(owner) is recognized")
    }

    let identified = process(703, "worker", 400_000_000, 703, 1,
        path: "/Applications/Codex.app/Contents/MacOS/Codex", executableID: "dev:703")
    let changedExecutable = ProcessIntelligence()
    changedExecutable.ingest([identified], now: t0)
    var replacement = identified
    replacement.executablePath = "/tmp/replacement"
    replacement.executableFileID = "dev:704"
    changedExecutable.ingest([replacement], now: t0.addingTimeInterval(15))
    let replacementEvidence = changedExecutable.evidence(for: replacement, now: t0.addingTimeInterval(15))
    check(!replacementEvidence.activeDevelopment && replacementEvidence.owner == nil,
          "changing executable identity expires cached ownership metadata")

    let terminalTracker = ProcessIntelligence()
    let terminal = process(720, "Ghostty", 100_000_000, 720, owner: "Ghostty")
    let terminalWorker = process(721, "node", 800_000_000, 721, 720, path: "/opt/homebrew/bin/node")
    terminalTracker.ingest([terminal, terminalWorker], now: t0)
    check(terminalTracker.evidence(for: terminalWorker, now: t0).activeDevelopment,
          "Jobs descended from the user's Ghostty terminal retain the active-work warning")

    // Exited parent facts stay available without being interpreted as abandonment.
    let afterParentExit = process(701, "node", 810_000_000, 701, 700, path: "/opt/homebrew/bin/node")
    intelligence.ingest([afterParentExit], now: t0.addingTimeInterval(30))
    let exitedEvidence = intelligence.evidence(for: afterParentExit, now: t0.addingTimeInterval(30))
    check(exitedEvidence.parentExited && exitedEvidence.owner == "Codex" && exitedEvidence.activeDevelopment,
          "observed former parent and owner survive parent exit")
    check(!exitedEvidence.knownAbandoned, "parent exit alone is not proof of abandonment")

    // Memory growth requires >=5 observations across >=5 minutes and both byte and percent thresholds.
    let growthTracker = ProcessIntelligence()
    let growthID = ProcessIdentity(pid: 800, startTime: Date(timeIntervalSince1970: 800))
    var growing = process(800, "worker", 500_000_000, 800)
    for minute in 0...20 {
        growing.ramBytes = 500_000_000 + UInt64(minute) * 15_000_000
        let when = t0.addingTimeInterval(Double(minute) * 15)
        growthTracker.ingest([growing], now: when)
    }
    let growth = growthTracker.evidence(for: growing, now: t0.addingTimeInterval(300))
    check(growthTracker.sampleCount(for: growthID) == 21, "history samples at most once per 15 second interval")
    check(growth.memoryGrowth && growth.growthBytes == 300_000_000 && growth.observationSeconds >= 300,
          "memory growth requires sustained byte and percentage thresholds")
    let insufficientTracker = ProcessIntelligence()
    var small = process(801, "worker", 500_000_000, 801)
    for minute in 0...20 {
        small.ramBytes = 500_000_000 + UInt64(minute) * 2_000_000
        insufficientTracker.ingest([small], now: t0.addingTimeInterval(Double(minute) * 15))
    }
    check(!insufficientTracker.evidence(for: small, now: t0.addingTimeInterval(300)).memoryGrowth,
          "small memory increases do not trigger leak evidence")
    var plateau = growing
    plateau.ramBytes = 800_000_000
    for index in 21...81 {
        growthTracker.ingest([plateau], now: t0.addingTimeInterval(Double(index) * 15))
    }
    check(!growthTracker.evidence(for: plateau, now: t0.addingTimeInterval(1_215)).memoryGrowth,
          "a completed older growth event does not count as current five minute growth")

    let executableGrowth = ProcessIntelligence()
    var changingBinary = process(802, "worker", 500_000_000, 802,
        path: "/Applications/Codex.app/Contents/MacOS/worker", executableID: "dev:802")
    for minute in 0...20 {
        changingBinary.ramBytes = 500_000_000 + UInt64(minute) * 15_000_000
        executableGrowth.ingest([changingBinary], now: t0.addingTimeInterval(Double(minute) * 15))
    }
    check(executableGrowth.evidence(for: changingBinary, now: t0.addingTimeInterval(300)).memoryGrowth,
          "valid executable history can establish growth before exec")
    changingBinary.executablePath = "/tmp/worker"
    changingBinary.executableFileID = "dev:803"
    executableGrowth.ingest([changingBinary], now: t0.addingTimeInterval(315))
    check(executableGrowth.sampleCount(for: ProcessIdentity(changingBinary)) == 1
          && !executableGrowth.evidence(for: changingBinary, now: t0.addingTimeInterval(315)).memoryGrowth,
          "executable identity change clears memory growth history")

    // All history structures have explicit upper bounds.
    let bounded = ProcessIntelligence()
    let many = (1...600).map { process(Int32(10_000 + $0), "fixture", 100_000_000, Double($0)) }
    bounded.ingest(many, now: t0)
    check(bounded.retainedProcessCount <= ProcessIntelligence.maximumProcesses,
          "retained process history stays within its process cap")
    let sampled = process(900, "sampled", 100_000_000, 900)
    for index in 0...300 {
        bounded.ingest([sampled], now: t0.addingTimeInterval(Double(index) * 15))
    }
    check(bounded.sampleCount(for: ProcessIdentity(sampled)) <= ProcessIntelligence.maximumSamplesPerProcess,
          "per-process sample history stays within its sample cap")
    check(bounded.evidence(for: sampled, now: t0.addingTimeInterval(4_500)).observationSeconds <= ProcessIntelligence.historyWindow,
          "history observations stay within the one hour window")

    let prioritized = ProcessIntelligence()
    let rssSet = (1...600).map { index in
        process(Int32(3_000 + index), "rss-\(index)", UInt64(index) * 10_000_000, Double(3_000 + index))
    }
    prioritized.ingest(rssSet, now: t0)
    let highestRSS = rssSet.last!
    check(prioritized.sampleCount(for: ProcessIdentity(highestRSS)) == 1,
          "bounded history prioritizes the highest-RSS process over input ordering")

    let trendTracker = ProcessIntelligence()
    let watched = process(4_000, "rising-worker", 100_000_000, 4_000)
    let initialSet = [watched] + (1...511).map { process(Int32(4_000 + $0), "stable-\($0)", 2_000_000_000, Double(4_000 + $0)) }
    trendTracker.ingest(initialSet, now: t0)
    let risingWatched = process(4_000, "rising-worker", 600_000_000, 4_000)
    let expandedSet = [risingWatched] + Array(initialSet.dropFirst()) + (1...88).map {
        process(Int32(5_000 + $0), "new-heavy-\($0)", 3_000_000_000, Double(5_000 + $0))
    }
    trendTracker.ingest(expandedSet, now: t0.addingTimeInterval(15))
    check(trendTracker.sampleCount(for: ProcessIdentity(risingWatched)) == 2,
          "rising memory history remains sampled when heavier processes arrive")

    let ancestryTracker = ProcessIntelligence()
    let lightParent = process(6_000, "Codex", 1_000_000, 6_000, path: "/Applications/Codex.app/Contents/MacOS/Codex",
                              executableID: "dev:6000")
    let trackedChild = process(6_001, "worker", 4_000_000_000, 6_001, 6_000)
    let filler = (1...600).map { process(Int32(7_000 + $0), "filler", 2_000_000_000, Double(7_000 + $0)) }
    ancestryTracker.ingest([lightParent, trackedChild] + filler, now: t0)
    let trackedEvidence = ancestryTracker.evidence(for: trackedChild, now: t0)
    check(trackedEvidence.activeDevelopment && trackedEvidence.owner == "Codex",
          "full process snapshot resolves a verified parent outside the retained history cap")
    ancestryTracker.ingest([trackedChild], now: t0.addingTimeInterval(15))
    let formerParentEvidence = ancestryTracker.evidence(for: trackedChild, now: t0.addingTimeInterval(15))
    check(formerParentEvidence.parentExited && formerParentEvidence.activeDevelopment
          && formerParentEvidence.owner == "Codex" && !formerParentEvidence.knownAbandoned,
          "former unretained parent metadata persists without implying abandonment")

    // The scheduler reserves an attempt on true, honors sustained triggers, cooldown, and daily cap.
    let policyProcess = process(1_000, "worker", 500_000_000, 1_000)
    var policy = AutomaticAnalysisPolicy()
    check(!policy.shouldAnalyze(procs: [policyProcess], evidence: [:], pressure: .elevated, now: t0),
          "pressure must persist before analysis")
    check(!policy.shouldAnalyze(procs: [policyProcess], evidence: [:], pressure: .elevated,
                                now: t0.addingTimeInterval(29)), "pressure trigger waits full 30 seconds")
    check(policy.shouldAnalyze(procs: [policyProcess], evidence: [:], pressure: .elevated,
                               now: t0.addingTimeInterval(30)), "sustained pressure reserves an analysis request")
    check(!policy.shouldAnalyze(procs: [policyProcess], evidence: [:], pressure: .elevated,
                                now: t0.addingTimeInterval(629)), "cooldown blocks repeat requests")
    check(policy.shouldAnalyze(procs: [policyProcess], evidence: [:], pressure: .elevated,
                               now: t0.addingTimeInterval(630)), "cooldown permits analysis at ten minutes")
    for request in 3...6 {
        let at = t0.addingTimeInterval(630 + Double(request - 2) * AutomaticAnalysisPolicy.cooldown)
        check(policy.shouldAnalyze(procs: [policyProcess], evidence: [:], pressure: .elevated, now: at),
              "daily request (request) is issued within the cap")
    }
    check(!policy.shouldAnalyze(procs: [policyProcess], evidence: [:], pressure: .elevated,
                                now: t0.addingTimeInterval(3_630)), "six requests is the daily maximum")

    var pressurePolicy = AutomaticAnalysisPolicy()
    check(!pressurePolicy.shouldAnalyze(procs: [policyProcess], evidence: [:], pressure: .elevated,
                                        now: t0.addingTimeInterval(30), providerIsApple: true),
          "Apple inference defers during elevated pressure")
    let growthEvidence = ProcessEvidence(owner: nil, ancestry: [], activeDevelopment: false,
        memoryGrowth: true, growthBytes: 300_000_000, observationSeconds: 300,
        parentExited: false, cpuSampleValid: false)
    let evidenceMap = [ProcessIdentity(policyProcess): growthEvidence]
    check(pressurePolicy.shouldAnalyze(procs: [policyProcess], evidence: evidenceMap, pressure: .healthy,
                                       now: t0.addingTimeInterval(31), providerIsApple: true),
          "Apple can analyze sustained growth when memory pressure is healthy")

    var largePolicy = AutomaticAnalysisPolicy()
    let large = process(1_001, "large", AutomaticAnalysisPolicy.largeProcessBytes, 1_001)
    check(!largePolicy.shouldAnalyze(procs: [large], evidence: [:], pressure: .healthy, now: t0),
          "large process alone does not trigger analysis")
    check(!largePolicy.shouldAnalyze(procs: [large], evidence: [:], pressure: .healthy,
                                     now: t0.addingTimeInterval(120)), "large process requires context")
    check(largePolicy.shouldAnalyze(procs: [large], evidence: evidenceMap, pressure: .healthy,
                                    now: t0.addingTimeInterval(121)), "persistent large process plus growth evidence triggers analysis")

    var restored = AutomaticAnalysisPolicy()
    restored.restore(count: 6, lastIssuedAt: t0, day: t0, now: t0.addingTimeInterval(60))
    check(!restored.shouldAnalyze(procs: [policyProcess], evidence: evidenceMap, pressure: .healthy,
                                  now: t0.addingTimeInterval(601)), "persisted daily request count prevents restart quota bypass")

    // Snapshot normalization and cache lifetime are deterministic and bounded.
    let hashProc = process(1_100, "worker", 128 * 1024 * 1024, t0.timeIntervalSince1970,
                           path: "/Applications/Codex.app/Contents/MacOS/worker",
                           cpuValid: true, cpu: 6, executableID: "dev:1100")
    let hashIdentity = ProcessIdentity(hashProc)
    let hashEvidence = [hashIdentity: growthEvidence]
    let hash1 = analysisSnapshotHash(procs: [hashProc], evidence: hashEvidence, pressure: .healthy,
                                     now: t0.addingTimeInterval(60))
    let reordered = analysisSnapshotHash(procs: [hashProc], evidence: hashEvidence, pressure: .healthy,
                                         now: t0.addingTimeInterval(60))
    check(hash1 == reordered, "equivalent snapshots receive the same normalized hash")
    check(stableDigest("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
          "opaque identity keys use SHA-256")
    check(hash1 != analysisSnapshotHash(procs: [hashProc], evidence: hashEvidence, pressure: .critical,
                                        now: t0.addingTimeInterval(60)),
          "pressure change invalidates the analysis snapshot hash")
    check(hash1 != analysisSnapshotHash(procs: [hashProc], evidence: hashEvidence, pressure: .healthy,
                                        ignored: [hashIdentity], now: t0.addingTimeInterval(60)),
          "ignore preference participates in snapshot identity")
    check(analysisAgeBand(hashProc, now: t0.addingTimeInterval(119)) == "new"
          && analysisAgeBand(hashProc, now: t0.addingTimeInterval(120)) == "recent"
          && analysisAgeBand(hashProc, now: t0.addingTimeInterval(3_600)) == "longRunning",
          "process age bands change at two and sixty minutes")
    let ageHash = analysisSnapshotHash(procs: [hashProc], evidence: hashEvidence, pressure: .healthy,
                                       now: t0.addingTimeInterval(120))
    check(hash1 != ageHash, "process age band participates in analysis hash")
    var changedFileID = hashProc
    changedFileID.executableFileID = "dev:9999"
    check(hash1 != analysisSnapshotHash(procs: [changedFileID], evidence: hashEvidence, pressure: .healthy,
                                        now: t0.addingTimeInterval(60)),
          "executable file identity participates in analysis hash")
    var changedPath = hashProc
    changedPath.executablePath = "/tmp/other-worker"
    check(hash1 != analysisSnapshotHash(procs: [changedPath], evidence: hashEvidence, pressure: .healthy,
                                        now: t0.addingTimeInterval(60)),
          "only the digest of executable path participates in analysis hash")
    let changedType = process(1_100, "worker", 128 * 1024 * 1024, t0.timeIntervalSince1970,
                              path: "/Applications/Codex.app/Contents/MacOS/worker",
                              cpuValid: true, cpu: 6, executableID: "dev:1100", type: .system)
    check(hash1 != analysisSnapshotHash(procs: [changedType], evidence: hashEvidence, pressure: .healthy,
                                        now: t0.addingTimeInterval(60)), "process type participates in analysis hash")
    var inactiveCPU = hashProc
    inactiveCPU.cpuPct = 1
    check(hash1 != analysisSnapshotHash(procs: [inactiveCPU], evidence: hashEvidence, pressure: .healthy,
                                        now: t0.addingTimeInterval(60)), "CPU activity hash uses the prompt's one percent threshold")
    var unknownCPU = inactiveCPU
    unknownCPU.cpuSampleValid = false
    check(analysisSnapshotHash(procs: [unknownCPU], evidence: hashEvidence, pressure: .healthy,
                               now: t0.addingTimeInterval(60))
          != analysisSnapshotHash(procs: [inactiveCPU], evidence: hashEvidence, pressure: .healthy,
                                  now: t0.addingTimeInterval(60)), "CPU-known state participates in snapshot hash")
    let cache = AnalysisResultCache()
    cache.store(Data("result".utf8), for: hash1, now: t0)
    check(cache.value(for: hash1, now: t0.addingTimeInterval(599)) == Data("result".utf8),
          "cached analysis remains available within ten minutes")
    check(cache.value(for: hash1, now: t0.addingTimeInterval(601)) == nil,
          "cached analysis expires after ten minutes")
}

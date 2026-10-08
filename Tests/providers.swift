import Foundation

final class RecordingDiscovery: ModelDiscovering {
    var requests = 0; var cancellations = 0; var closes = 0
    var completion: ((Result<[String], AIFailure>) -> Void)?
    func fetch(_ request: URLRequest, provider: AIProvider, completion: @escaping (Result<[String], AIFailure>) -> Void) -> AnalysisTask {
        requests += 1; self.completion = completion
        return AnalysisTask { self.cancellations += 1 }
    }
    func close() { closes += 1 }
}

func providerChecks(check: (Bool, String) -> Void) {
    func rejects(_ operation: () throws -> Void) -> Bool { do { try operation(); return false } catch { return true } }
    for provider in [AIProvider.openai, .anthropic, .deepseek, .xai, .openrouter, .compatible] {
        do {
            let request = try APIWire.request(provider: provider, custom: "https://fixture.example/v1", model: "fixture-model",
                key: "SYNTHETIC_KEY", instructions: "fixture", prompt: "fixture")
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            check(request.url?.scheme == "https" && request.httpMethod == "POST" && body["model"] as? String == "fixture-model",
                  "API request uses selected model and secure destination: \(provider.rawValue)")
            check(!String(data: request.httpBody!, encoding: .utf8)!.contains("SYNTHETIC_KEY"), "API key stays out of process payload: \(provider.rawValue)")
            let catalog = try APIWire.models(provider: provider, custom: "https://fixture.example/v1", ollama: "", key: "SYNTHETIC_KEY")
            check(catalog.httpMethod == nil || catalog.httpMethod == "GET", "Model discovery never requests inference: \(provider.rawValue)")
            if provider == .openai { check(request.url?.path == "/v1/responses" && body["store"] as? Bool == false, "OpenAI uses Responses without response storage") }
            if provider == .anthropic { check(request.url?.path == "/v1/messages" && request.value(forHTTPHeaderField: "x-api-key") == "SYNTHETIC_KEY" && catalog.url?.query == "limit=500", "Anthropic Messages and paginated model catalog headers") }
            if provider == .deepseek { check((body["thinking"] as? [String: String])?["type"] == "disabled", "DeepSeek defaults to non-reasoning speed") }
            if provider == .openrouter { check((body["provider"] as? [String: Bool])?["allow_fallbacks"] == false, "OpenRouter provider fallback disabled") }
        } catch { check(false, "API request creation: \(provider.rawValue)") }
    }
    for bad in ["http://remote.example/v1", "https://user:key@fixture.example/v1", "https://fixture.example/v1?key=secret", "https://fixture.example/v1#fragment", "file:///private/fixture", "not-a-url"] {
        check(rejects { _ = try APIWire.base(provider: .compatible, custom: bad) }, "Unsafe custom API destination rejected")
    }
    check((try? APIWire.base(provider: .compatible, custom: "http://127.0.0.1:8080/v1")) != nil, "Explicit loopback compatible endpoint accepted")
    let first = try! APIWire.account(provider: .compatible, custom: "https://one.example/v1")
    let second = try! APIWire.account(provider: .compatible, custom: "https://two.example/v1")
    check(first != second && first == (try! APIWire.account(provider: .compatible, custom: "https://one.example/v1/")), "Custom credentials scoped to normalized endpoint")
    check(rejects { _ = try APIWire.request(provider: .openai, custom: "", model: "fixture", key: "bad\nkey", instructions: "", prompt: "") }, "Header control characters in a key rejected")
    check(rejects { _ = try APIWire.models(provider: .opencodeGo, custom: "", ollama: "", key: "fixture") }, "Go model discovery remains permission gated")
    let configFixture = try! JSONDecoder().decode(AppConfig.self, from: Data(#"{"aiProvider":"anthropic","aiModel":"fixture","providerModels":{"openai":"saved"},"customAPIURL":"https://fixture.example/v1","connectionRevision":9223372036854775807}"#.utf8))
    check(configFixture.aiProvider == "anthropic" && configFixture.providerModels["openai"] == "saved" && configFixture.connectionRevision == 1_000_000, "New provider preferences migrate and revisions stay bounded")
    check(UsageLedger.validTokens(Int.max) == nil && UsageLedger.validTokens(-1) == nil && UsageLedger.validTokens(712) == 712, "Untrusted usage cannot overflow numeric accounting")
    let selected = ModelCatalog.normalize(ids: (0..<600).map { "model-\($0)" } + ["zzz-selected"], selected: "zzz-selected")
    check(selected.count == 500 && selected.contains("zzz-selected"), "Model selection survives a catalog larger than the dropdown cap")
    let ledgerFixture = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("systemprocesses-bounded-ledger-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: ledgerFixture) }
    do {
        try Data(repeating: 65, count: 70_000).write(to: ledgerFixture)
        let retainedSize = try Data(contentsOf: ledgerFixture).count
        check(!UsageLedger.load(at: ledgerFixture).automaticUsageAvailable && retainedSize == 70_000, "Oversized usage ledger fails closed and stays intact")
        var ledger = UsageLedger()
        ledger.providers = Dictionary(uniqueKeysWithValues: (0..<33).map { ("provider-\($0)", UsageTotals()) })
        try JSONEncoder().encode(ledger).write(to: ledgerFixture)
        check(!UsageLedger.load(at: ledgerFixture).automaticUsageAvailable, "Oversized provider map fails closed")
        ledger.providers = [String(repeating: "a", count: 65): UsageTotals()]
        try JSONEncoder().encode(ledger).write(to: ledgerFixture)
        check(!UsageLedger.load(at: ledgerFixture).automaticUsageAvailable, "Oversized provider identifier fails closed")
    } catch { check(false, "Bounded usage ledger fixtures were readable") }

    let optedOut = try! JSONDecoder().decode(AppConfig.self, from: Data(#"{"cloudAnalysisEnabled":false,"aiEnabled":true}"#.utf8))
    check(!optedOut.cloudAnalysisEnabled, "Explicit cloud-off preferences survive easier first-run setup")
    let missingSharing = try! JSONDecoder().decode(AppConfig.self, from: Data(#"{"aiEnabled":true}"#.utf8))
    check(!missingSharing.cloudAnalysisEnabled, "Older configurations without a cloud choice are not silently opted in")
    let saved = config
    config = AppConfig(); config.aiEnabled = true; config.aiProvider = "ollama"; config.aiModel = "fixture:cloud"
    let fakeDiscovery = RecordingDiscovery()
    let settings = SettingsView(w: POP_W, discovery: fakeDiscovery)
    let refresh = settings.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Refresh" }!
    let model = settings.subviews.compactMap { $0 as? NSComboBox }.first!
    check(fakeDiscovery.requests == 0, "Opening Settings never performs model discovery")
    refresh.performClick(nil)
    check(fakeDiscovery.requests == 1, "Explicit Refresh starts model discovery")
    settings.cancelDiscovery()
    fakeDiscovery.completion?(.success(["stale-result:cloud"]))
    check(fakeDiscovery.cancellations == 1 && fakeDiscovery.closes == 1 && !model.objectValues.contains(where: { ($0 as? String) == "stale-result:cloud" }), "Cancelling discovery rejects its stale completion")
    config.aiEnabled = false
    refresh.performClick(nil)
    check(fakeDiscovery.requests == 1, "Disabled AI cannot start discovery")
    let enable = settings.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Enable AI recommendations" }!
    enable.state = .off; enable.performClick(nil)
    check(config.aiEnabled && fakeDiscovery.requests == 2, "Enabling AI automatically discovers cloud model choices without inference")
    enable.performClick(nil)
    check(!config.aiEnabled && fakeDiscovery.cancellations == 2, "Disabling AI cancels the setup model lookup")
    config = saved

    let priorConfig = config
    for provider in AIProvider.choices {
        config = AppConfig(); config.aiEnabled = true; config.aiProvider = provider.rawValue
        config.aiModel = "fixture-model"; config.customAPIURL = "https://fixture.example/v1"
        let panel = SettingsView(w: POP_W, discovery: RecordingDiscovery())
        let secure = panel.subviews.compactMap { $0 as? NSSecureTextField }.first!
        let endpoint = panel.subviews.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "API base URL" }!
        let picker = panel.subviews.compactMap { $0 as? NSPopUpButton }.first { $0.toolTip == "AI provider" }!
        check(secure.isEnabled == provider.needsKey && secure.stringValue.isEmpty, "Secure API field follows provider without exposing a saved key: " + provider.rawValue)
        check(endpoint.isEnabled == (provider == .compatible), "Only a custom provider permits endpoint edits: " + provider.rawValue)
        check(picker.numberOfItems == AIProvider.choices.count && picker.indexOfSelectedItem == AIProvider.choices.firstIndex(of: provider), "Provider picker represents the selected protocol: " + provider.rawValue)
        check(picker.item(at: AIProvider.choices.firstIndex(of: .opencodeGo)!)?.isEnabled == false, "Go runtime remains visibly disabled: " + provider.rawValue)
    }
    config = priorConfig

    let hybridGroup = Array(fixtures.prefix(30))
    let (localPartition, cloudPartition) = HybridCoordinator.partitions(hybridGroup, useApple: true)
    check(localPartition.count == 8 && cloudPartition.count == 22 && Set((localPartition + cloudPartition).map { $0.pid }).count == 30, "Hybrid covers every identity once with bounded local context")
    check(HybridCoordinator.partitions(hybridGroup, useApple: false).0.isEmpty, "Pressure or unavailable Apple sends the full bounded workload to cloud")
    let validLocal = AIResp(recommendations: localPartition.map { AIRec(pid: $0.pid, verdict: .caution, reason: "Review local evidence") }, summary: "Review")
    check((try? HybridCoordinator.checked(validLocal, for: localPartition)) != nil, "Complete hybrid stage accepted")
    for records in [Array(validLocal.recommendations.dropLast()), validLocal.recommendations + [validLocal.recommendations[0]], [AIRec(pid: cloudPartition[0].pid, verdict: .safe, reason: "Cross partition")]] {
        check(rejects { _ = try HybridCoordinator.checked(AIResp(recommendations: records, summary: "fixture"), for: localPartition) }, "Partial, duplicate, or cross-partition hybrid output fails closed")
    }
    var pendingHybrid: ((Result<AIResp, AIFailure>) -> Void)?
    var hybridStages: [AIProvider] = [], deliveredHybrid = 0, cancelledHybrid = 0, skippedGroupCount = 0
    let operation = HybridCoordinator(processes: hybridGroup, useApple: true, runner: { provider, _, done in
        hybridStages.append(provider); pendingHybrid = done
        return AnalysisTask { cancelledHybrid += 1 }
    }, completion: { _ in deliveredHybrid += 1 })
    operation.start(); operation.cancel(); pendingHybrid?(.success(validLocal))
    check(hybridStages == [.apple] && deliveredHybrid == 0 && cancelledHybrid == 1, "Cancelling hybrid prevents cloud launch and rejects late local results")
    let skipOperation = HybridCoordinator(processes: hybridGroup, useApple: false, runner: { provider, group, done in
        hybridStages.append(provider); pendingHybrid = done
        skippedGroupCount = group.count
        return AnalysisTask {}
    }, completion: { _ in deliveredHybrid += 1 })
    skipOperation.start()
    let full = AIResp(recommendations: hybridGroup.map { AIRec(pid: $0.pid, verdict: .caution, reason: "Review") }, summary: "Review")
    pendingHybrid?(.success(full)); pendingHybrid?(.success(full))
    check(deliveredHybrid == 1 && skippedGroupCount == 30, "Hybrid completion is delivered exactly once with full skipped workload")
    check(AppConfig().aiProvider == "hybrid" && AppConfig().cloudAnalysisEnabled && !AppConfig().aiEnabled && !AIProvider.hybrid.needsKey, "Fresh hybrid setup is ready for cloud but AI starts off and uses Ollama sign-in")

    let answer = #"{"summary":"fixture","recommendations":[]}"#
    for stop in ["length", "content_filter", "tool_calls", ""] {
        check(rejects { _ = try GoWireAdapter.decode(["choices": [["finish_reason": stop, "message": ["content": answer]]]]) }, "Partial or filtered chat completion rejected: " + stop)
    }
    for stop in ["max_tokens", "tool_use", "pause_turn", ""] {
        check(rejects { _ = try GoWireAdapter.decode(["stop_reason": stop, "content": [["type": "text", "text": answer]]]) }, "Incomplete Messages answer rejected: " + stop)
    }
    for status in ["incomplete", "failed", "cancelled", "in_progress", ""] {
        check(rejects { _ = try GoWireAdapter.decode(["status": status, "output": [["type": "message", "content": [["type": "output_text", "text": answer]]]]]) }, "Incomplete Responses answer rejected: " + status)
    }
    check(rejects { _ = try GoWireAdapter.decode(["status": "completed", "incomplete_details": ["reason": "max_output_tokens"], "output": []]) }, "Contradictory Responses completion is rejected")

}

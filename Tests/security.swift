import Foundation

func securityChecks(_ check: (Bool, String) -> Void) {
    for path in ["/Users/fixture/Documents/tool", "/Users/fixture/Desktop/Tool.app", "/Users/fixture/Downloads/tool", "/Volumes/Private/tool", "/private/var/folders/fixture/tool", "/Applications/../Users/fixture/Documents/tool"] {
        check(!mayInspectExecutablePath(path) && executableFileIdentity(path).isEmpty, "Protected or unknown file location is not inspected: \(path)")
    }
    check(mayInspectExecutablePath("/Applications/Tool.app") && !executableFileIdentity("/bin/sleep").isEmpty, "Installed applications and system tools retain file identity checks")
    var inspectedPaths: [String] = []
    let privateLink = inspectableFilePath("/Applications/Private.app/Contents/MacOS/tool", linkTarget: { path in
        inspectedPaths.append(path)
        return path == "/Applications/Private.app" ? "/Users/fixture/Documents/Private.app" : nil
    })
    check(privateLink == nil && !inspectedPaths.contains(where: { $0.hasPrefix("/Users/") }), "Protected symlink targets are rejected before any file lookup there")
    check(inspectableFilePath("/opt/link/bin/tool", linkTarget: { $0 == "/opt/link" ? "/usr/local" : nil }) == "/usr/local/bin/tool", "Safe installed-tool links retain inspection")
    check(inspectableFilePath("/opt/loop", linkTarget: { $0 == "/opt/loop" ? "/opt/loop" : nil }) == nil, "Symlink loops cannot keep collection busy")
    check(!mayInspectExecutablePath("/System/Volumes/Data/Users/fixture/Documents/tool"), "Data-volume aliases cannot bypass private-folder exclusion")
    let configFixture = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("systemprocesses-config-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: configFixture) }
    check(loadConfig(path: configFixture.path).cloudAnalysisEnabled && !loadConfig(path: configFixture.path).aiEnabled, "Confirmed missing config keeps fresh AI-off cloud-ready defaults")
    try! Data("damaged preferences".utf8).write(to: configFixture)
    check(!loadConfig(path: configFixture.path).cloudAnalysisEnabled && !loadConfig(path: configFixture.path).aiEnabled, "Damaged saved preferences cannot silently enable sharing")
    try! FileManager.default.removeItem(at: configFixture)
    try! FileManager.default.createDirectory(at: configFixture, withIntermediateDirectories: false)
    check(!loadConfig(path: configFixture.path).cloudAnalysisEnabled, "Unreadable saved preferences fail closed for cloud sharing")
    let raw = #"{"recommendations":[{"pid":123,"verdict":"caution","reason":"unknown evidence"}],"summary":"Inspect first"}"#
    func rejects(_ object: [String: Any], provider: AIProvider = .ollama) -> Bool {
        do { _ = try AIManager.decode(data: JSONSerialization.data(withJSONObject: object), status: 200, provider: provider); return false }
        catch { return true }
    }
    check(rejects(["message":["content":raw]]), "Missing Ollama completion rejected")
    check(rejects(["message":["content":raw],"done":false]), "False Ollama completion rejected")
    check(rejects(["message":["content":raw],"done":true,"done_reason":"length"]), "Ollama length truncation rejected")
    for reason in ["load", "cancelled", "content_filter", "unknown"] {
        check(rejects(["message":["content":raw],"done":true,"done_reason":reason]), "Non-stop Ollama completion rejected")
    }
    for reason in ["length", "content_filter", "tool_calls", "unknown"] {
        check(rejects(["choices":[["message":["content":raw],"finish_reason":reason]]], provider:.opencodeGo), "Incomplete Go termination reason rejected")
    }
    for (model, route, header) in [("grok-4.7","responses","Authorization"),("gpt-6-luna","responses","Authorization"),
                                    ("claude-haiku-5-5","messages","x-api-key"),("qwen3.8-flash","messages","x-api-key"),
                                    ("glm-5.3-flash","chat/completions","Authorization")] {
        do {
            let request = try GoWireAdapter.request(model:model,instructions:"fixture",prompt:"fixture",key:"synthetic-key",session:"synthetic-session")
            check(request.url?.absoluteString == "https://opencode.ai/zen/go/v1/"+route && request.value(forHTTPHeaderField:header) != nil, "Correct protocol and fixed destination for \(model)")
        } catch { check(false,"Adapter creation for \(model)") }
    }
    let messages: [String:Any] = ["stop_reason":"end_turn", "content":[["type":"text","text":raw]],"usage":["input_tokens":5,"output_tokens":7]]
    let responses: [String:Any] = ["status":"completed", "output":[["type":"message","content":[["type":"output_text","text":raw]]]],"usage":["input_tokens":5,"output_tokens":7]]
    for object in [messages, responses] {
        do {
            let decoded = try GoWireAdapter.decode(object)
            check(decoded.recommendations.count == 1 && decoded.usage?.inputTokens == 5, "Messages/Responses decoding preserves reported usage")
        } catch { check(false,"Messages/Responses decoded") }
    }
    check(rejects(["stop_reason":"max_tokens","content":[["type":"text","text":raw]]],provider:.opencodeGo), "Messages truncation rejected")
    check(rejects(["status":"incomplete","output":[["type":"message","content":[["type":"output_text","text":raw]]]]],provider:.opencodeGo), "Responses incomplete status rejected")
    let migrated = try! JSONDecoder().decode(AppConfig.self, from:Data(#"{"aiAutoKill":true,"displayMode":"percent","refreshInterval":5}"#.utf8))
    check(!migrated.aiAutoKill && migrated.displayMode == "percent" && migrated.refreshInterval == 5, "Auto-kill migrates off without losing preferences")
    check(!migrated.cloudAnalysisEnabled, "Cloud transmission is opt-in")
    var sent = false
    var nonexistent = ProcInfo(pid:2_147_000_000,name:"fixture",ramBytes:1,cpuPct:0,icon:nil,type:.background,isProtected:false,
        threads:1,startTime:Date(),ppid:1,childCount:0)
    nonexistent.executablePath = "/bin/sleep"; nonexistent.executableFileID = executableFileIdentity("/bin/sleep")
    check(!terminateProcess(nonexistent,signal:{_,_ in sent=true;return 0}) && !sent, "Disappeared process cannot reach injected signal")
    let before = rgApp.procs
    rgApp.procs = []
    let empty = rgApp.snapshotHash([nonexistent])
    rgApp.procs = [nonexistent]
    check(empty != rgApp.snapshotHash([nonexistent]), "Empty live list invalidates submitted evidence")
    var executed = nonexistent
    executed.executablePath = "/bin/bash"; executed.executableFileID = executableFileIdentity("/bin/bash")
    rgApp.stopRequests[ProcessIdentity(nonexistent)] = SystemProcessesApp.StopReservation(process: nonexistent, at: Date(timeIntervalSinceNow: -4))
    rgApp.procs = [executed]
    check(!rgApp.mayForce(executed), "Executable change cannot inherit force-stop reservation")
    rgApp.stopRequests.removeAll()
    rgApp.procs = before
    let unpressured = SysRAM(total:100,appMem:20,wired:20,compressed:10,free:1,pressure:.healthy)
    check(unpressured.pct == 99 && unpressured.pressure == .healthy, "High page occupancy cannot manufacture pressure")
    check(SysRAM.zero.pressure == .unavailable, "Unknown pressure is labeled unavailable")
}
